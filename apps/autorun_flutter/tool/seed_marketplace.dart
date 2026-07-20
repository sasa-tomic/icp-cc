// ignore_for_file: avoid_print

/// Bulk marketplace script seeder — `dart run tool/seed_marketplace.dart`.
///
/// Uploads N signed, public scripts to a marketplace backend so the e2e
/// harness can exercise pagination-dependent flows (`scripts.load_more`)
/// without needing the backend's 3 hand-seeded scripts to exceed the page
/// threshold.
///
/// Usage:
///   dart run tool/seed_marketplace.dart --count=25
///   dart run tool/seed_marketplace.dart --count=25 --endpoint=http://127.0.0.1:35735
///   dart run tool/seed_marketplace.dart --clean        # delete all bulk_seed scripts first
///
/// Idempotency:
///   Each script is uploaded with slug `bulk-seed-script-{i}` + tag
///   `bulk_seed`. The seeder first queries the backend for existing
///   bulk_seed scripts (via the search endpoint) and skips indices that
///   already exist. So `dart run seed_marketplace.dart --count=25` followed
///   by the same command uploads 25 scripts TOTAL (not 50).
///
/// Real cryptography:
///   Uses a deterministic Ed25519 keypair (the same one TestSignatureUtils
///   uses — `package:ed25519_edwards` over the canonical-JSON upload
///   payload) so every upload's signature verifies against the backend's
///   signature check. No mocked cryptography.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// CLI entry point. Parses --count / --endpoint / --clean / --purge / --paid,
/// then uploads (or purges).
Future<void> main(List<String> args) async {
  final opts = _parseArgs(args);
  if (opts.help) {
    _printUsage();
    exitCode = 0;
    return;
  }
  final endpoint = opts.endpoint;
  Uri createUri;
  Uri searchUri;
  try {
    createUri = Uri.parse('$endpoint/api/v1/scripts');
    searchUri = Uri.parse('$endpoint/api/v1/scripts/search');
  } on FormatException catch (e) {
    stderr.writeln('❌ Invalid endpoint "$endpoint": $e');
    exitCode = 64;
    return;
  }

  print('==> seed_marketplace: endpoint=$endpoint '
      'mode=${opts.purge ? "purge" : opts.paid ? "paid-seed" : "seed"} '
      'count=${opts.count} clean=${opts.clean} paid=${opts.paid}');

  final client = HttpClient();
  // The seeder uses a single deterministic keypair for ALL bulk seeds (the
  // principal is `bulk_seed@seed.local` — no real account exists, but the
  // backend only requires a verifiable signature against the public key; it
  // doesn't require the key to be tied to a registered account for upload).
  final keypair = _bulkSeedKeypair();
  final publicKeyB64 = base64Encode(keypair.publicBytes);
  final principal = 'bulk_seed@seed.local';

  // --purge: discover ALL bulk-seed OR paid-seed scripts by this keypair and
  // DELETE them. Use this to reset the backend to a clean state before
  // seeding. Each delete is signed (real Ed25519 over the canonical delete
  // payload) so the backend's auth + ownership checks pass.
  if (opts.purge) {
    final existing = await _discoverExistingBulkSeedsWithIds(
        client, searchUri, publicKeyB64);
    print('   purge: ${existing.length} bulk_seed/paid_seed scripts to delete.');
    var deleted = 0;
    for (final entry in existing.entries) {
      final ok = await _deleteOne(
        client: client,
        deleteUri: Uri.parse('$endpoint/api/v1/scripts/${entry.key}'),
        scriptId: entry.key,
        title: entry.value,
        principal: principal,
        publicKeyB64: publicKeyB64,
        keypair: keypair,
      );
      if (ok) {
        deleted++;
      } else {
        exitCode = 1;
      }
    }
    client.close(force: true);
    print('==> seed_marketplace: purge done — deleted=$deleted.');
    return;
  }

  // --paid: upload a SINGLE paid script (price > 0) so e2e flows can
  // exercise the scripts.buy + scripts.download_paid paths. The slug + tag
  // are stable so the flow can locate it deterministically, and purge mode
  // cleans it up alongside the free bulk seeds.
  if (opts.paid) {
    final existing = await _discoverExistingPaidSeedWithId(
        client, searchUri, publicKeyB64);
    if (existing != null) {
      print('   paid-seed: already exists (id=$existing); skipping upload.');
      client.close(force: true);
      print('==> seed_marketplace: paid-seed idempotent — already present.');
      return;
    }
    final ok = await _uploadOne(
      client: client,
      createUri: createUri,
      index: 0,
      title: 'Paid Seed Script',
      principal: principal,
      publicKeyB64: publicKeyB64,
      keypair: keypair,
      paid: true,
    );
    client.close(force: true);
    print('==> seed_marketplace: paid-seed ${ok ? "uploaded" : "FAILED"}.');
    exitCode = ok ? 0 : 1;
    return;
  }

  final count = opts.count;
  if (count <= 0) {
    stderr.writeln('❌ --count must be > 0 (got $count).');
    exitCode = 64;
    return;
  }

  // Idempotency: discover which bulk-seed indices already exist.
  final existingTitles = <String>{};
  if (!opts.clean) {
    existingTitles.addAll(await _discoverExistingBulkSeeds(
        client, searchUri, publicKeyB64));
    if (existingTitles.isNotEmpty) {
      print('   idempotency: ${existingTitles.length} bulk_seed scripts '
          'already present; skipping those indices.');
    }
  }

  var created = 0;
  var skipped = 0;
  for (var i = 0; i < count; i++) {
    final title = 'Bulk Seed Script $i';
    if (!opts.clean && existingTitles.contains(title)) {
      skipped++;
      continue;
    }
    final ok = await _uploadOne(
      client: client,
      createUri: createUri,
      index: i,
      title: title,
      principal: principal,
      publicKeyB64: publicKeyB64,
      keypair: keypair,
    );
    if (ok) {
      created++;
    } else {
      exitCode = 1;
      break;
    }
  }
  client.close(force: true);
  print('==> seed_marketplace: done — created=$created skipped=$skipped '
      '(target_count=$count)');
}

/// One bulk-seed upload. Builds the canonical upload payload (must match
/// the backend's `build_upload_payload` field-for-field), signs it with the
/// real Ed25519 keypair, POSTs to /api/v1/scripts.
Future<bool> _uploadOne({
  required HttpClient client,
  required Uri createUri,
  required int index,
  required String title,
  required String principal,
  required String publicKeyB64,
  required _Keypair keypair,
  bool paid = false,
}) async {
  // Paid seed: fixed slug 'paid-seed-script', tag 'paid_seed', price 4.99.
  // Bulk seed: slug 'bulk-seed-script-{i}', tag 'bulk_seed', price 0.0.
  final slug = paid ? 'paid-seed-script' : 'bulk-seed-script-$index';
  final description = paid
      ? 'Paid seed script for e2e purchase-flow testing. '
          'Generated by tool/seed_marketplace.dart --paid.'
      : 'Bulk seed script #$index for e2e pagination testing. '
          'Generated by tool/seed_marketplace.dart.';
  final category = paid ? 'utility' : 'utility';
  final bundle = paid
      ? 'print("Paid seed v1.0");'
      : 'print("Bulk seed $index");';
  final version = '1.0.0';
  // tags must be sorted in the payload (matches backend's
  // build_upload_payload: `sorted_tags.sort()`).
  final List<String> tags = paid
      ? <String>['paid_seed', 'seed']
      : <String>['bulk_seed', 'pagination', 'seed'];
  tags.sort();
  final timestamp = DateTime.now().toUtc().toIso8601String();
  final compatibility = 'All ICP Canisters';
  final price = paid ? 4.99 : 0.0;

  // Build the canonical payload — order-invariant via sorted keys.
  final payload = <String, dynamic>{
    'action': 'upload',
    'bundle': bundle,
    'category': category,
    'compatibility': compatibility,
    'description': description,
    'title': title,
    'version': version,
    'author_principal': principal,
    'tags': tags,
    'timestamp': timestamp,
  };
  final canonicalJson = _canonicalJsonEncode(payload);
  final payloadBytes = Uint8List.fromList(utf8.encode(canonicalJson));
  final sigBytes = ed.sign(
    ed.PrivateKey(keypair.privateBytes),
    payloadBytes,
  );
  final signatureB64 = base64Encode(sigBytes);

  final body = jsonEncode(<String, dynamic>{
    'slug': slug,
    'title': title,
    'description': description,
    'category': category,
    'bundle': bundle,
    'version': version,
    'tags': tags,
    'compatibility': compatibility,
    'price': price,
    'is_public': true,
    'author_principal': principal,
    'author_public_key': publicKeyB64,
    'signature': signatureB64,
    'timestamp': timestamp,
  });

  try {
    final request = await client.postUrl(createUri)
      ..headers.contentType = ContentType.json
      ..write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 200 && response.statusCode <= 299) {
      print('   ✓ [$slug] $title');
      return true;
    }
    stderr.writeln('   ✗ [$slug] HTTP ${response.statusCode}: '
        '${responseBody.length > 300 ? '${responseBody.substring(0, 300)}…' : responseBody}');
    return false;
  } catch (e) {
    stderr.writeln('   ✗ [$slug] exception: $e');
    return false;
  }
}

/// Query the backend for existing bulk_seed scripts so we can skip those
/// indices on re-runs. Searches by the unique `bulk_seed` tag.
Future<Set<String>> _discoverExistingBulkSeeds(
    HttpClient client, Uri searchUri, String publicKeyB64) async {
  final found = <String>{};
  try {
    final body = jsonEncode(<String, dynamic>{
      'query': 'Bulk Seed Script',
      // The backend caps search limit at 100; if N > 100 we'd need multiple
      // pages, but the seeder's default is 25 and the e2e flow's threshold
      // is 20, so 100 is plenty.
      'limit': 100,
      'offset': 0,
    });
    final request = await client.postUrl(searchUri)
      ..headers.contentType = ContentType.json
      ..write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) return found;
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map) return found;
    final data = decoded['data'];
    if (data is! Map) return found;
    final scripts = data['scripts'];
    if (scripts is! List) return found;
    for (final s in scripts) {
      if (s is Map) {
        final title = s['title'];
        if (title is String && title.startsWith('Bulk Seed Script ')) {
          // Only count scripts uploaded by THIS keypair (the search may
          // match unrelated scripts that happen to contain "Bulk Seed
          // Script" in the title).
          final sPub = s['author_public_key'];
          if (sPub == publicKeyB64) {
            found.add(title);
          }
        }
      }
    }
  } catch (e) {
    stderr.writeln('   (idempotency probe failed: $e — proceeding without)');
  }
  return found;
}

/// Same as [_discoverExistingBulkSeeds] but returns a Map of id → title for
/// the purge path (needs the id to DELETE by). Matches BOTH bulk_seed and
/// paid_seed scripts (so --purge cleans up everything this seeder created).
Future<Map<String, String>> _discoverExistingBulkSeedsWithIds(
    HttpClient client, Uri searchUri, String publicKeyB64) async {
  final found = <String, String>{};
  try {
    // Two searches: bulk_seed title prefix + paid_seed title prefix.
    // (The backend search is text-based — a single 'Bulk Seed Script'
    // query would miss paid_seed entries.)
    for (final query in ['Bulk Seed Script', 'Paid Seed Script']) {
      final body = jsonEncode(<String, dynamic>{
        'query': query,
        'limit': 100,
        'offset': 0,
      });
      final request = await client.postUrl(searchUri)
        ..headers.contentType = ContentType.json
        ..write(body);
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) continue;
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) continue;
      final data = decoded['data'];
      if (data is! Map) continue;
      final scripts = data['scripts'];
      if (scripts is! List) continue;
      for (final s in scripts) {
        if (s is Map) {
          final title = s['title'];
          final id = s['id'];
          if (title is String &&
              id is String &&
              (title.startsWith('Bulk Seed Script ') ||
                  title == 'Paid Seed Script')) {
            final sPub = s['author_public_key'];
            if (sPub == publicKeyB64) {
              found[id] = title;
            }
          }
        }
      }
    }
  } catch (e) {
    stderr.writeln('   (purge probe failed: $e — proceeding without)');
  }
  return found;
}

/// Looks up the id of an existing paid-seed script (slug 'paid-seed-script')
/// uploaded by THIS keypair. Returns `null` when none exists — used by the
/// `--paid` path to skip re-uploading on idempotent runs.
Future<String?> _discoverExistingPaidSeedWithId(
    HttpClient client, Uri searchUri, String publicKeyB64) async {
  try {
    final body = jsonEncode(<String, dynamic>{
      'query': 'Paid Seed Script',
      'limit': 10,
      'offset': 0,
    });
    final request = await client.postUrl(searchUri)
      ..headers.contentType = ContentType.json
      ..write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map) return null;
    final data = decoded['data'];
    if (data is! Map) return null;
    final scripts = data['scripts'];
    if (scripts is! List) return null;
    for (final s in scripts) {
      if (s is Map) {
        final title = s['title'];
        final id = s['id'];
        if (title == 'Paid Seed Script' && id is String) {
          final sPub = s['author_public_key'];
          if (sPub == publicKeyB64) {
            return id;
          }
        }
      }
    }
  } catch (e) {
    stderr.writeln('   (paid-seed probe failed: $e — proceeding without)');
  }
  return null;
}

/// One bulk-seed delete (for --purge). Builds the canonical delete payload,
/// signs it with the real Ed25519 keypair, sends DELETE /api/v1/scripts/:id.
Future<bool> _deleteOne({
  required HttpClient client,
  required Uri deleteUri,
  required String scriptId,
  required String title,
  required String principal,
  required String publicKeyB64,
  required _Keypair keypair,
}) async {
  final timestamp = DateTime.now().toUtc().toIso8601String();
  // Matches backend's build_deletion_payload (auth.rs:94-116): action,
  // script_id, author_principal, timestamp.
  final payload = <String, dynamic>{
    'action': 'delete',
    'script_id': scriptId,
    'author_principal': principal,
    'timestamp': timestamp,
  };
  final canonicalJson = _canonicalJsonEncode(payload);
  final payloadBytes = Uint8List.fromList(utf8.encode(canonicalJson));
  final sigBytes = ed.sign(
    ed.PrivateKey(keypair.privateBytes),
    payloadBytes,
  );
  final signatureB64 = base64Encode(sigBytes);

  final body = jsonEncode(<String, dynamic>{
    'action': 'delete',
    'script_id': scriptId,
    'author_principal': principal,
    'author_public_key': publicKeyB64,
    'signature': signatureB64,
    'timestamp': timestamp,
  });

  try {
    final request = await client.openUrl('DELETE', deleteUri)
      ..headers.contentType = ContentType.json
      ..write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 200 && response.statusCode <= 299) {
      print('   ✓ [purge] $title ($scriptId)');
      return true;
    }
    stderr.writeln('   ✗ [purge] $title ($scriptId) HTTP ${response.statusCode}: '
        '${responseBody.length > 300 ? '${responseBody.substring(0, 300)}…' : responseBody}');
    return false;
  } catch (e) {
    stderr.writeln('   ✗ [purge] $title ($scriptId) exception: $e');
    return false;
  }
}

/// Deterministic Ed25519 keypair used for all bulk seeds. The seed is the
/// same one `TestKeypairFactory.getEd25519Keypair()` uses (the canonical
/// BIP39 zero-mnemonic seed) so the public key matches the test suite's
/// default. This means a real e2e flow can verify bulk-seed signatures
/// with the same TestSignatureUtils.
_Keypair _bulkSeedKeypair() {
  // From apps/autorun_flutter/tool/print_vector.dart over the zero-mnemonic
  // (TestKeypairFactory._ed25519TestMnemonic). The cryptography package's
  // extractPrivateKeyBytes() returns the 32-byte SEED; newKeyPairFromSeed
  // derives the full keypair. Public key is the matching 32-byte point.
  //   ed25519 seed   (base64): QIsoXBI4NgBPS4hCyJMkwfATgkUMDUOa80W6f8Saz3A=
  //   ed25519 public (base64): HeNS5EzTM2clk/IzSnMOGAqvKQ3omqFtSA3llONOKWE=
  const seedB64 = 'QIsoXBI4NgBPS4hCyJMkwfATgkUMDUOa80W6f8Saz3A=';
  const publicB64 = 'HeNS5EzTM2clk/IzSnMOGAqvKQ3omqFtSA3llONOKWE=';
  // ed25519_edwards.PrivateKey expects seed||pub (64 bytes, Go convention).
  // Construct it from the seed via newKeyFromSeed, then extract the full
  // 64-byte form so ed.sign(PrivateKey, msg) works.
  final seedBytes = base64Decode(seedB64);
  final pubBytes = base64Decode(publicB64);
  final fullPrivate = Uint8List(64)
    ..setRange(0, 32, seedBytes)
    ..setRange(32, 64, pubBytes);
  return _Keypair(privateBytes: fullPrivate, publicBytes: pubBytes);
}

class _Keypair {
  const _Keypair({required this.privateBytes, required this.publicBytes});
  final Uint8List privateBytes;
  final Uint8List publicBytes;
}

/// Canonical JSON encoder (sorted keys, recursive) — must match
/// TestSignatureUtils._canonicalJsonEncode and the backend's payload
/// reconstruction exactly for the signature to verify.
String _canonicalJsonEncode(Map<String, dynamic> data) {
  final sortedMap = <String, dynamic>{};
  final sortedKeys = data.keys.toList()..sort();
  for (final key in sortedKeys) {
    final value = data[key];
    if (value is Map<String, dynamic>) {
      sortedMap[key] = json.decode(_canonicalJsonEncode(value));
    } else if (value is List) {
      sortedMap[key] = value;
    } else {
      sortedMap[key] = value;
    }
  }
  return json.encode(sortedMap);
}

class _Options {
  _Options({
    required this.count,
    required this.endpoint,
    required this.clean,
    required this.purge,
    required this.paid,
    required this.help,
  });
  int count;
  String endpoint;
  bool clean;
  bool purge;
  /// When true, upload a SINGLE paid-seed script (slug 'paid-seed-script',
  /// price 4.99) instead of N bulk-seed scripts. Used by e2e flows that
  /// exercise scripts.buy + scripts.download_paid.
  bool paid;
  bool help;
}

_Options _parseArgs(List<String> args) {
  var count = 25;
  var endpoint = _resolveEndpoint();
  var clean = false;
  var purge = false;
  var paid = false;
  var help = false;
  for (final arg in args) {
    if (arg == '--help' || arg == '-h') {
      help = true;
    } else if (arg.startsWith('--count=')) {
      final v = int.tryParse(arg.substring('--count='.length));
      if (v != null) count = v;
    } else if (arg.startsWith('--endpoint=')) {
      endpoint = arg.substring('--endpoint='.length);
    } else if (arg == '--clean') {
      clean = true;
    } else if (arg == '--purge') {
      purge = true;
    } else if (arg == '--paid') {
      paid = true;
    }
  }
  return _Options(
      count: count, endpoint: endpoint, clean: clean, purge: purge, paid: paid, help: help);
}

/// Default endpoint resolution: $MARKETPLACE_API_PORT → 127.0.0.1, else
/// fall back to the production endpoint (which will likely reject the
/// uploads — fail loud).
String _resolveEndpoint() {
  final port = Platform.environment['MARKETPLACE_API_PORT'];
  if (port != null && port.isNotEmpty) {
    return 'http://127.0.0.1:$port';
  }
  return 'https://icp-mp.kalaj.org';
}

void _printUsage() {
  print('Usage: dart run tool/seed_marketplace.dart [options]');
  print('');
  print('Options:');
  print('  --count=N          Number of bulk-seed scripts to upload (default 25).');
  print('  --endpoint=URL     Marketplace backend URL (default: from');
  print('                     \$MARKETPLACE_API_PORT, else https://icp-mp.kalaj.org).');
  print('  --clean            Ignore existing bulk_seed scripts and re-create');
  print('                     all N (skips the idempotency probe).');
  print('  --paid             Upload a SINGLE paid-seed script (slug');
  print('                     \'paid-seed-script\', price \$4.99) for e2e');
  print('                     scripts.buy + scripts.download_paid. Idempotent:');
  print('                     skips upload if the paid seed already exists.');
  print('  --purge            Discover and DELETE all bulk_seed + paid_seed');
  print('                     scripts by this seeder\'s keypair, then exit.');
  print('                     Use to reset the backend before a fresh seed.');
  print('  --help, -h         Show this help.');
  print('');
  print('Typical usage:');
  print('  dart run tool/seed_marketplace.dart --purge                # reset');
  print('  dart run tool/seed_marketplace.dart --count=25             # seed');
  print('  dart run tool/seed_marketplace.dart --paid                 # paid fixture');
  print('  dart run tool/seed_marketplace.dart --count=25             # idempotent');
}
