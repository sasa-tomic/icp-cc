@TestOn('linux')
// End-to-end proof that the authenticated app-lifecycle canister path works.
//
// Gated on `ICPCC_LIVE_CANISTER` (the backend poll canister id) AND
// `ICPCC_LIVE_HOST` (the replica URL). Skips cleanly with a clear message when
// the live replica is unavailable, so this file is safe to leave in the suite.
//
// Run it for real:
//   export PATH="/home/ubuntu/.cache/data/dfx/bin:$PATH"
//   dfx start --background --clean && dfx deploy   # in examples/icp_poll_dapp
//   ICPCC_LIVE_CANISTER=uxrrr-q7777-77774-qaaaq-cai \
//   ICPCC_LIVE_HOST=http://127.0.0.1:4943 \
//   cd apps/autorun_flutter && flutter test \
//     test/features/scripts/live_canister_auth_test.dart --timeout=180s
library;

import 'dart:convert';
import 'dart:io';

import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart';

const String _anonymousPrefix = '2vxsx-faaaa';

bool _liveEnvAvailable() {
  return Platform.environment['ICPCC_LIVE_CANISTER'] != null &&
      Platform.environment['ICPCC_LIVE_CANISTER']!.trim().isNotEmpty;
}

/// A FRESH Ed25519 identity each call. `icp_generate_keypair` with no mnemonic
/// is deterministic (zero entropy) — reusing it would make the same principal
/// vote twice, and the canister dedupes votes per principal, so the tally would
/// not change. A unique mnemonic per run guarantees a never-before-seen voter.
RustKeypairResult _freshKeypair(RustBridgeLoader loader) {
  final String mnemonic = bip39.generateMnemonic();
  final RustKeypairResult? kp =
      loader.generateKeypair(alg: 0, mnemonic: mnemonic);
  expect(kp, isNotNull, reason: 'keypair generation failed for mnemonic');
  return kp!;
}

void main() {
  final RustBridgeLoader loader = const RustBridgeLoader();

  group('live authenticated canister path', () {
    // Verifies the FFI library actually loaded in this environment. If it
    // didn't, every assertion below is meaningless — fail loud, not silent.
    test('FFI lib loads (icp_js_exec probe)', () {
      final String? probe = loader.jsExec(script: '1', jsonArg: null);
      expect(probe, isNotNull, reason: 'libicp_core.so did not load');
    });

    test('captured JSON shapes: listPolls, getTally, whoami', () {
      if (!_liveEnvAvailable()) {
        stdout.writeln('SKIP: ICPCC_LIVE_CANISTER env var not set');
        return;
      }
      final canister = Platform.environment['ICPCC_LIVE_CANISTER']!.trim();
      final host = Platform.environment['ICPCC_LIVE_HOST']?.trim().isNotEmpty == true
          ? Platform.environment['ICPCC_LIVE_HOST']!.trim()
          : null;

      final listOut = loader.callAnonymous(
        canisterId: canister,
        method: 'listPolls',
        mode: 0,
        args: '()',
        host: host,
      );
      stdout.writeln('SHAPE listPolls raw => $listOut');
      expect(listOut, isNotNull);
      expect(listOut!.trim().isNotEmpty, true);

      // Parse to confirm the structure: {"ok":true,"result":[{...}, ...]}
      final listObj = json.decode(listOut) as Map<String, dynamic>;
      expect(listObj['ok'], true);
      final result = listObj['result'];
      expect(result, isA<List>(),
          reason: 'listPolls must return an array of poll records');
      if ((result as List).isNotEmpty) {
        final poll = result.first as Map<String, dynamic>;
        stdout.writeln('SHAPE poll record => ${json.encode(poll)}');
        expect(poll.containsKey('id'), true);
        expect(poll.containsKey('question'), true);
        expect(poll.containsKey('options'), true);
        expect(poll.containsKey('creator'), true);
        // creator is a principal -> serialized as a STRING by idl_value_to_json
        expect(poll['creator'], isA<String>(),
            reason: 'principal must serialize as JSON string');
      }
    });

    test('authenticated whoami returns a NON-anonymous principal', () {
      if (!_liveEnvAvailable()) {
        stdout.writeln('SKIP: ICPCC_LIVE_CANISTER env var not set');
        return;
      }
      final canister = Platform.environment['ICPCC_LIVE_CANISTER']!.trim();
      final host = Platform.environment['ICPCC_LIVE_HOST']?.trim().isNotEmpty == true
          ? Platform.environment['ICPCC_LIVE_HOST']!.trim()
          : null;

      // Generate a FRESH Ed25519 identity via the same FFI the app uses.
      final kp = _freshKeypair(loader);
      stdout.writeln('AUTH identity principal => ${kp.principalText}');

      final out = loader.callAuthenticated(
        canisterId: canister,
        method: 'whoami',
        mode: 0, // query
        privateKeyB64: kp.privateKeyB64,
        args: '()',
        host: host,
      );
      stdout.writeln('AUTH whoami raw => $out');
      expect(out, isNotNull);
      expect(out!.trim().isNotEmpty, true);

      final obj = json.decode(out) as Map<String, dynamic>;
      expect(obj['ok'], true);
      // whoami returns text = Principal.toText(msg.caller)
      final caller = obj['result'].toString();
      stdout.writeln('AUTH caller principal => $caller');
      expect(caller.startsWith(_anonymousPrefix), isFalse,
          reason:
              'authenticated whoami returned the ANONYMOUS principal ($caller); '
              'the auth path is broken — DO NOT proceed');
      // The caller must match the principal derived from the generated keypair.
      expect(caller, kp.principalText);
    });

    test('authenticated vote changes getTally', () {
      if (!_liveEnvAvailable()) {
        stdout.writeln('SKIP: ICPCC_LIVE_CANISTER env var not set');
        return;
      }
      final canister = Platform.environment['ICPCC_LIVE_CANISTER']!.trim();
      final host = Platform.environment['ICPCC_LIVE_HOST']?.trim().isNotEmpty == true
          ? Platform.environment['ICPCC_LIVE_HOST']!.trim()
          : null;

      final kp = _freshKeypair(loader);

      // Discover a poll id to vote on.
      final listOut = loader.callAnonymous(
        canisterId: canister,
        method: 'listPolls',
        mode: 0,
        args: '()',
        host: host,
      );
      final listObj = json.decode(listOut!) as Map<String, dynamic>;
      final polls = listObj['result'] as List;
      expect(polls, isNotEmpty, reason: 'seed a poll before running this test');
      final poll = polls.first as Map<String, dynamic>;
      final pollId = poll['id'] as String;

      // getTally before vote. vec nat -> array of numeric strings.
      final beforeOut = loader.callAnonymous(
        canisterId: canister,
        method: 'getTally',
        mode: 0,
        args: '("$pollId")',
        host: host,
      );
      stdout.writeln('SHAPE getTally($pollId) before => $beforeOut');
      final beforeObj = json.decode(beforeOut!) as Map<String, dynamic>;
      final beforeTally = (beforeObj['result'] as List).map((e) => e.toString()).toList();
      stdout.writeln('AUTH tally before vote => $beforeTally');

      // Vote for option index 0 via an authenticated UPDATE call.
      // `0 : nat` annotation is required — the candid parser otherwise infers a
      // type the canister rejects with "unexpected IDL type when parsing Nat".
      final voteOut = loader.callAuthenticated(
        canisterId: canister,
        method: 'vote',
        mode: 1, // update
        privateKeyB64: kp.privateKeyB64,
        args: '("$pollId", 0 : nat)',
        host: host,
      );
      stdout.writeln('AUTH vote raw => $voteOut');
      expect(voteOut, isNotNull);
      final voteObj = json.decode(voteOut!) as Map<String, dynamic>;
      expect(voteObj['ok'], true,
          reason: 'authenticated vote failed: $voteOut');

      // getTally after vote — option 0 must have increased by 1.
      final afterOut = loader.callAnonymous(
        canisterId: canister,
        method: 'getTally',
        mode: 0,
        args: '("$pollId")',
        host: host,
      );
      final afterObj = json.decode(afterOut!) as Map<String, dynamic>;
      final afterTally = (afterObj['result'] as List).map((e) => e.toString()).toList();
      stdout.writeln('AUTH tally after vote  => $afterTally');

      final before0 = int.parse(beforeTally[0]);
      final after0 = int.parse(afterTally[0]);
      expect(after0, before0 + 1,
          reason: 'authenticated vote did not increment option 0 tally; '
              'before=$before0 after=$after0');
    });
  });
}
