// WU-2 Web runtime — secp256k1 keypair / ICP principal / signing.
//
// Tests the PURE-DART Web implementation against hardcoded reference vectors
// captured from the Rust core (`crates/icp_core`) — the source of truth — and,
// when the native `libicp_core` loads, against the live FFI (proving native ↔
// Web bit-for-bit parity). Because the Web impl is pure Dart (no
// `dart:html`/`dart:js_interp`), these tests run in the standard Dart VM under
// `flutter test`. No browser required.
//
// Vector provenance: captured from `crates/icp_core` via a one-off probe
// (`generate_secp256k1_keypair`, `sign_secp256k1`, `der_encode_public_key` for
// the standard zero-entropy BIP39 mnemonic — the SAME mnemonic used by the
// Ed25519 cross-compat tests and `crates/icp_core/tests/common/mod.rs`).

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/native_bridge.dart' as native;
import 'package:icp_autorun/rust/native_bridge_web.dart' as web;
import 'package:icp_autorun/rust/web/secp256k1.dart' as secp;
// pointycastle is a dev-dependency — used ONLY here as an INDEPENDENT ECDSA
// verifier (the production code uses `package:elliptic`).
import 'package:pointycastle/api.dart' as pc show PublicKeyParameter;
import 'package:pointycastle/ecc/api.dart' as pc show ECPublicKey, ECSignature;
import 'package:pointycastle/ecc/curves/secp256k1.dart' as pc
    show ECCurve_secp256k1;
import 'package:pointycastle/signers/ecdsa_signer.dart' as pc show ECDSASigner;

/// Standard BIP39 test mnemonic (24 words, all-zero 32-byte entropy). Same one
/// used by `crates/icp_core/tests/common/mod.rs` and the Ed25519 parity tests.
const _kTestMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon art';

// ── Reference vectors (captured from Rust `icp_core`) ───────────────────────
// Source: crates/icp_core/tests/common/mod.rs (canonical vectors) + a one-off
// probe for the signature/DER vectors.
const _kSecp256k1PrivateB64 = 'Yb+9dY8vXeoLiLMSqhpHbE4MhT2HkGRk0Ai8NkBcD/I=';
const _kSecp256k1PublicB64 =
    'BBz+IZWfHzq8STHpP6u3hU/DOJS6Fy5m3ewbQautk0Vd3u79WEhh0/0gvh886bxxFK9et89Fi2sBc4LDysmVe4g=';
const _kSecp256k1Principal =
    'm7bn6-s5er4-xouui-ymkqf-azncv-qfche-3qghk-2fvpm-atfyh-ozg2w-iqe';

// Signature vector. Source: Rust `sign_secp256k1(b"icp-cc-secp256k1-parity", priv)`.
// Proves RFC 6979 determinism (byte-identical across native ↔ Web).
const _kMessageText = 'icp-cc-secp256k1-parity';
const _kMessageB64 = 'aWNwLWNjLXNlY3AyNTZrMS1wYXJpdHk=';
const _kExpectedSigB64 =
    'i8upqbApiNIBQcBvSrW/3eqH9T67kzzaCNLsFZgPDSdR3BsESwq0qWWQzgNFlGBh+DSFYIHngSzhTarov1Yqqg==';

/// True when the native `libicp_core` is loadable in this test environment
/// (Linux dev box with the release `.so` built). When false, the live
/// cross-compat assertions skip gracefully (benign — the hardcoded Rust vectors
/// still assert Web parity, which is the authoritative proof). Mirrors the
/// Ed25519 parity test's `_nativeAvailable`.
bool get _nativeAvailable {
  try {
    return const native.RustBridgeLoader().jsExec(script: '1', jsonArg: null) !=
        null;
  } catch (_) {
    return false;
  }
}

/// Independent ECDSA verification (pointycastle — dev-only) of a compact
/// `r||s` signature against an uncompressed secp256k1 public key. Used as a
/// cross-check ON TOP of the golden-vector match. The message is pre-hashed
/// with SHA-256 (matching the signing path); the no-digest `ECDSASigner`
/// treats the input as the digest directly.
bool _verifyEcdsa(Uint8List message, Uint8List pubUncompressed, Uint8List sig) {
  final params = pc.ECCurve_secp256k1();
  final q = params.curve.decodePoint(pubUncompressed)!;
  final signer = pc.ECDSASigner(); // no digest → caller pre-hashes
  signer.init(false, pc.PublicKeyParameter(pc.ECPublicKey(q, params)));
  final hash = crypto.sha256.convert(message).bytes;
  return signer.verifySignature(
    Uint8List.fromList(hash),
    pc.ECSignature(_b64BigInt(sig.sublist(0, 32)), _b64BigInt(sig.sublist(32))),
  );
}

BigInt _b64BigInt(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

void main() {
  group('WU-2 generateKeypair (secp256k1, Web pure-Dart)', () {
    test('reproduces the Rust keypair for the standard test mnemonic', () {
      final r = const web.RustBridgeLoader().generateKeypair(
        alg: 1,
        mnemonic: _kTestMnemonic,
      );
      expect(r, isNotNull);
      expect(r!.publicKeyB64, equals(_kSecp256k1PublicB64));
      expect(r.privateKeyB64, equals(_kSecp256k1PrivateB64));
      expect(r.principalText, equals(_kSecp256k1Principal));
    });

    test('public key is the 65-byte uncompressed form (0x04||X||Y)', () {
      final r = const web.RustBridgeLoader().generateKeypair(
        alg: 1,
        mnemonic: _kTestMnemonic,
      )!;
      final pub = base64.decode(r.publicKeyB64);
      expect(pub.length, 65);
      expect(pub[0], 0x04);
    });

    test('empty mnemonic fails loud (caller must resolve one first)', () {
      expect(
        () => const web.RustBridgeLoader().generateKeypair(alg: 1, mnemonic: ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('WU-2 principalFromPublicKey (secp256k1, Web pure-Dart)', () {
    test('derives the known principal for the golden public key', () {
      final principal = const web.RustBridgeLoader().principalFromPublicKey(
        alg: 1,
        publicKeyB64: _kSecp256k1PublicB64,
      );
      expect(principal, equals(_kSecp256k1Principal));
    });

    test('round-trips the generateKeypair public key to the same principal', () {
      final r = const web.RustBridgeLoader().generateKeypair(
        alg: 1,
        mnemonic: _kTestMnemonic,
      )!;
      final p = const web.RustBridgeLoader().principalFromPublicKey(
        alg: 1,
        publicKeyB64: r.publicKeyB64,
      );
      expect(p, equals(r.principalText));
    });

    test('accepts the raw 64-byte X||Y form (prepends 0x04)', () {
      // Strip the 0x04 prefix → 64-byte raw X||Y; must yield the SAME principal.
      final pub65 = base64.decode(_kSecp256k1PublicB64);
      final pub64 = pub65.sublist(1); // drop 0x04
      final p = const web.RustBridgeLoader().principalFromPublicKey(
        alg: 1,
        publicKeyB64: base64.encode(pub64),
      );
      expect(p, equals(_kSecp256k1Principal));
    });

    test('rejects a malformed public key length (not 64 or 65 bytes)', () {
      expect(
        () => const web.RustBridgeLoader()
            .principalFromPublicKey(alg: 1, publicKeyB64: base64.encode([1, 2])),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('matches the native FFI principal (live cross-compat)', () {
      if (!_nativeAvailable) {
        // ignore: avoid_print
        print('SKIP native cross-compat: libicp_core not loaded');
        return;
      }
      final nativeP = const native.RustBridgeLoader().principalFromPublicKey(
        alg: 1,
        publicKeyB64: _kSecp256k1PublicB64,
      );
      expect(nativeP, equals(_kSecp256k1Principal));
    }, skip: !_nativeAvailable ? 'libicp_core not loaded' : false);
  });

  group('WU-2 signMessage (secp256k1, Web pure-Dart)', () {
    test('reproduces the Rust signature for the known message (RFC 6979)', () {
      final result = const web.RustBridgeLoader().signMessage(
        alg: 1,
        messageB64: _kMessageB64,
        privateKeyB64: _kSecp256k1PrivateB64,
      )!;
      // Native FFI contract: JSON envelope {"ok":true,"signature":"<b64>"}.
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['signature'] as String, equals(_kExpectedSigB64));
    });

    test('signature is the 64-byte compact form (r||s)', () {
      final result = const web.RustBridgeLoader().signMessage(
        alg: 1,
        messageB64: _kMessageB64,
        privateKeyB64: _kSecp256k1PrivateB64,
      )!;
      final sigB64 = (jsonDecode(result) as Map<String, dynamic>)['signature']
          as String;
      expect(base64.decode(sigB64).length, 64);
    });

    test('signing is deterministic — same key+message → same signature', () {
      final s1 = const web.RustBridgeLoader().signMessage(
        alg: 1,
        messageB64: _kMessageB64,
        privateKeyB64: _kSecp256k1PrivateB64,
      );
      final s2 = const web.RustBridgeLoader().signMessage(
        alg: 1,
        messageB64: _kMessageB64,
        privateKeyB64: _kSecp256k1PrivateB64,
      );
      expect(s1, equals(s2));
    });

    test('signature verifies against the public key (independent ECDSA check)',
        () {
      final result = const web.RustBridgeLoader().signMessage(
        alg: 1,
        messageB64: _kMessageB64,
        privateKeyB64: _kSecp256k1PrivateB64,
      )!;
      final sigB64 = (jsonDecode(result) as Map<String, dynamic>)['signature']
          as String;
      final ok = _verifyEcdsa(
        Uint8List.fromList(utf8.encode(_kMessageText)),
        Uint8List.fromList(base64.decode(_kSecp256k1PublicB64)),
        Uint8List.fromList(base64.decode(sigB64)),
      );
      expect(ok, isTrue, reason: 'ECDSA signature failed independent verification');
    });

    test('different messages produce different signatures', () {
      final a = const web.RustBridgeLoader().signMessage(
        alg: 1,
        messageB64: base64.encode(utf8.encode('message one')),
        privateKeyB64: _kSecp256k1PrivateB64,
      );
      final b = const web.RustBridgeLoader().signMessage(
        alg: 1,
        messageB64: base64.encode(utf8.encode('message two')),
        privateKeyB64: _kSecp256k1PrivateB64,
      );
      expect(a, isNot(equals(b)));
    });

    test('rejects a wrong-length private key (not 32 bytes)', () {
      expect(
        () => const web.RustBridgeLoader().signMessage(
          alg: 1,
          messageB64: _kMessageB64,
          privateKeyB64: base64.encode(List.filled(31, 1)),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('matches the native FFI signature (live cross-compat)', () {
      if (!_nativeAvailable) {
        // ignore: avoid_print
        print('SKIP native cross-compat: libicp_core not loaded');
        return;
      }
      final nativeResult = const native.RustBridgeLoader().signMessage(
        alg: 1,
        messageB64: _kMessageB64,
        privateKeyB64: _kSecp256k1PrivateB64,
      );
      final webResult = const web.RustBridgeLoader().signMessage(
        alg: 1,
        messageB64: _kMessageB64,
        privateKeyB64: _kSecp256k1PrivateB64,
      );
      // Both return the identical JSON envelope (byte-for-byte).
      expect(webResult, equals(nativeResult));
    }, skip: !_nativeAvailable ? 'libicp_core not loaded' : false);
  });

  group('WU-2 low-level secp256k1 primitives (web/secp256k1.dart)', () {
    test('secp256k1UncompressedPublicKey matches the golden public key', () {
      final priv = Uint8List.fromList(base64.decode(_kSecp256k1PrivateB64));
      final pub = secp.secp256k1UncompressedPublicKey(priv);
      expect(base64.encode(pub), equals(_kSecp256k1PublicB64));
      expect(pub.length, 65);
      expect(pub[0], 0x04);
    });

    test('secp256k1Sign matches the golden signature (RFC 6979 low-S)', () {
      final priv = Uint8List.fromList(base64.decode(_kSecp256k1PrivateB64));
      final msg = Uint8List.fromList(utf8.encode(_kMessageText));
      final sig = secp.secp256k1Sign(msg, priv);
      expect(base64.encode(sig), equals(_kExpectedSigB64));
      expect(sig.length, 64);
    });

    test('secp256k1Sign is deterministic at the primitive level', () {
      final priv = Uint8List.fromList(base64.decode(_kSecp256k1PrivateB64));
      final msg = Uint8List.fromList(utf8.encode(_kMessageText));
      expect(secp.secp256k1Sign(msg, priv), equals(secp.secp256k1Sign(msg, priv)));
    });

    test('secp256k1UncompressedPublicKey rejects a non-32-byte key', () {
      expect(
        () => secp.secp256k1UncompressedPublicKey(Uint8List(31)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('secp256k1Sign rejects a non-32-byte key', () {
      expect(
        () => secp.secp256k1Sign(Uint8List(8), Uint8List(31)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('WU-2 algorithm-code validation', () {
    test('generateKeypair rejects an unknown algorithm code', () {
      expect(
        () => const web.RustBridgeLoader()
            .generateKeypair(alg: 2, mnemonic: _kTestMnemonic),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('principalFromPublicKey rejects an unknown algorithm code', () {
      expect(
        () => const web.RustBridgeLoader()
            .principalFromPublicKey(alg: 99, publicKeyB64: _kSecp256k1PublicB64),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('signMessage rejects an unknown algorithm code', () {
      expect(
        () => const web.RustBridgeLoader().signMessage(
          alg: -1,
          messageB64: _kMessageB64,
          privateKeyB64: _kSecp256k1PrivateB64,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
