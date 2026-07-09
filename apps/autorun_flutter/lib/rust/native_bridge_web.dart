/// Web implementation of the Rust-core bridge (R-2 / R-4).
///
/// Selected by [native_bridge.dart]'s conditional export when compiling for the
/// Web. The browser has no `dart:ffi` / `libicp_core`, so the operations that
/// the native core provides are re-implemented here in **pure Dart** using
/// audited crypto packages. Pure-Dart code runs unchanged on both the Dart VM
/// and the JS (web) target, so the same code paths are unit-testable in
/// `flutter test` AND ship to the browser — there is NO `dart:html` /
/// `dart:js_interop` dependency here, and NO mock crypto.
///
/// ## What is REAL here (R-2 / R-4 + WU-2 foundation)
/// - **Ed25519 key generation, signing, verification** (R-2): `package:ed25519_edwards`
///   (pure-Dart port of Go's `crypto/ed25519`). The seed → keypair → principal
///   path is bit-for-bit identical to Rust's `ed25519_dalek` (verified by
///   cross-compat tests against the live `libicp_core`).
/// - **secp256k1 key generation, signing, principal** (WU-2): BIP32
///   `m/44'/223'/0'/0/0` derivation (`package:bip32`) + RFC 6979 deterministic
///   low-S ECDSA (hand-rolled over `package:elliptic` + `package:crypto` HMAC)
///   in `web/secp256k1.dart`. Byte-for-byte identical to Rust's
///   `generate_secp256k1_keypair` / `sign_secp256k1` (verified by golden
///   vectors). Both alg=0 and alg=1 are fully real on Web.
/// - **IC self-authenticating principal derivation** (R-2 + WU-2): SPKI DER
///   (RFC 8410 for Ed25519, RFC 5480 for secp256k1) → SHA-224 → `[0x02]++hash`
///   → CRC32 → base32. Matches `candid::Principal`. ONE shared
///   `_selfAuthPrincipalFromDer` algorithm + two DER prefixes (DRY).
/// - **Vault crypto** (R-4): Argon2id KDF via `package:cryptography`'s
///   `DartArgon2id` (pure Dart) + AES-256-GCM. The Argon2id output is
///   bit-for-bit identical to Rust's `argon2` crate (verified by a known
///   vector), so vault blobs round-trip across native ↔ web.
///
/// ## What is still STUBBED (fail-fast, staged)
/// - **QuickJS script execution / linting** (R-3): `jsExec`, `jsAppInit/View/
///   Update`, `jsLint`, and `validateJsComprehensive` are ALL REAL on Web
///   (WU-1..WU-5). R-3 static analysis + execution are at parity with native.
/// - **IC canister calls**: `fetchCandid`, `parseCandid`, `callAnonymous`,
///   `callAuthenticated`. These need a web HTTP agent (planned follow-up).
///
/// ## Why Argon2id is async (vault methods)
/// `DartArgon2id` is a pure-Dart but inherently `Future`-returning API (it
/// cooperatively yields between memory-hard passes). `encryptVault` /
/// `decryptVault` therefore return `Future`s on BOTH the IO and Web targets so
/// the conditional-export interface stays uniform — see `vault_crypto_service.dart`
/// for the isolate / direct-call orchestration.
library;

import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto show Hmac, sha224, sha512;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

import 'native_bridge.dart';
// R-3 WU-4: the QuickJS-WASM engine is browser-only (`dart:js_interop`). This
// file is imported DIRECTLY by the R-2/R-4 web-crypto VM tests, so it must stay
// pure-Dart (VM-compilable). The engine singleton + exec wrappers live in the
// conditionally-selected access module: on Web → the real engine, on VM
// (`dart.library.io`) → a throwing stub (the VM production path uses
// `native_bridge_io.dart`'s FFI; the web-crypto tests never call these).
import 'web/quickjs_engine_web_access.dart'
    if (dart.library.io) 'web/quickjs_engine_vm_stub.dart' as qjs;
// R-3 WU-5: the JS static-analysis rules (pure-Dart port of the native
// `static_analysis` mod). Pure-Dart → no conditional import needed; compiles
// unchanged on VM and Web. The runtime syntax/exports check rides on the
// `qjs` engine access module above (browser-only).
import 'web/js_static_analysis.dart';
// R-3b WU-2: the IC-agent bridge. `fetchCandid` is browser-only (agent-js
// network I/O via the CORS proxy) → routed through the conditionally-selected
// access module (mirrors `qjs` above) so this file stays VM-compilable.
// `parseCandid` is a PURE-Dart port (`candid_interface_parser.dart`) → no
// conditional import, runs unchanged on VM and Web (VM-testable, mirrors
// `js_static_analysis.dart`).
import 'web/ic_agent_engine_web_access.dart'
    if (dart.library.io) 'web/ic_agent_engine_vm_stub.dart' as icagent;
import 'web/candid_interface_parser.dart';
// WU-2 — pure-Dart secp256k1 (BIP32 keygen + RFC 6979 deterministic low-S
// ECDSA + uncompressed pubkey). Pure-Dart → no conditional import; compiles
// unchanged on VM and Web (VM-testable, mirrors `js_static_analysis.dart`).
import 'web/secp256k1.dart';

/// Web readiness probe — delegates to the conditionally-selected engine access
/// module (loads the singleton on Web; [QuickJsReady] on the VM stub).
Future<QuickJsReadiness> probeQuickJsReadiness() =>
    qjs.probeWebQuickJsReadiness();

/// R-3b WU-5 — IC-agent readiness probe. Delegates to the conditionally-selected
/// IC-agent access module: on Web it lazily loads + awaits the singleton
/// agent-js bundle (bounded by a 30s timeout) and returns [IcAgentReady] /
/// [IcAgentUnavailable]; on the VM stub it returns [IcAgentReady] immediately
/// (the Rust FFI is the production path; agent-js is Web-only). Awaited
/// alongside [probeQuickJsReadiness] at boot so a failed Web load surfaces
/// honestly via the existing busy/error UI (never a silent no-op later).
Future<IcAgentReadiness> probeIcAgentReadiness() =>
    icagent.probeIcAgentReadiness();

/// Algorithm code: 0 = Ed25519 (the ICP-critical path).
/// 1 = secp256k1 (BIP32 m/44'/223'/... ; Bitcoin/Ethereum compatible — both
///    algorithms are fully implemented on Web as of WU-2, at native parity).
const int _algEd25519 = 0;
const int _algSecp256k1 = 1;

// ─────────────────────────────────────────────────────────────────────────────
// Principal derivation helpers (IC self-authenticating principal).
//
// Mirrors `crates/icp_core/src/principal.rs` + `ic_principal::Principal`
// (re-exported as `candid::Principal`). The authoritative algorithm
// (`ic_principal-0.1.1/src/lib.rs`):
//   1. hash = SHA-224(der_bytes)            → 28 bytes
//   2. principal = hash ++ [0x02]           → 29 bytes  (tag 0x02 is APPENDED)
//   3. crc = CRC32(principal).to_be_bytes() → 4 bytes  (zlib/IEEE, big-endian)
//   4. checksummed = crc ++ principal       → 33 bytes
//   5. base32 (RFC 4648, NO-PAD, then LOWERCASE), grouped 5-chars per '-'.
//
// SPKI DER for Ed25519 (RFC 8410), captured from Rust as a known vector:
//   30 2a 30 05 06 03 2b 65 70 03 21 00 || <32-byte pubkey>  (44 bytes total)
// ─────────────────────────────────────────────────────────────────────────────

/// RFC 8410 SubjectPublicKeyInfo prefix for a raw Ed25519 public key.
/// Verified byte-for-byte against Rust's `der_encode_public_key("ed25519", ..)`
/// (probe captured DER for the zero pubkey =
/// `302a300506032b6570032100` ++ 32 zero bytes).
final List<int> _ed25519DerPrefix = [
  0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
];

/// RFC 5480 SubjectPublicKeyInfo prefix for an uncompressed secp256k1 public
/// key. Verified byte-for-byte against Rust's `der_encode_public_key(
/// "secp256k1", ..)` (probe captured DER =
/// `3056301006072a8648ce3d020106052b8104000a034200` ++ 65-byte point).
///
/// Structure: `SEQUENCE { SEQUENCE { OID ecPublicKey(1.2.840.10045.2.1),
/// OID secp256k1(1.3.132.0.10) }, BIT STRING <0x00 || point> }`. The trailing
/// `0x00` is the BIT STRING "unused bits" byte — so appending the 65-byte
/// uncompressed point (`0x04||X||Y`) yields the complete 88-byte SPKI DER.
final List<int> _secp256k1DerPrefix = [
  0x30, 0x56, // outer SEQUENCE, length 86
  0x30, 0x10, //   algorithm SEQUENCE, length 16
  0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, // OID 1.2.840.10045.2.1
  0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x0a, // OID 1.3.132.0.10 (secp256k1)
  0x03, 0x42, 0x00, // BIT STRING, length 66, 0 unused bits
];

/// RFC 4648 base32 alphabet (lowercase, no padding). `ic_principal` encodes
/// uppercase then lowercases the result — equivalent to using this alphabet.
const _base32Alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

/// Standard CRC32 (IEEE 802.3 / zlib): poly 0xEDB88320, init 0xFFFFFFFF,
/// reflected input/output, final XOR 0xFFFFFFFF. Same value zlib /
/// `crc32fast::hash` produces.
int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc >>> 1) ^ (0xEDB88320 & -(crc & 1));
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// Base32-encode (RFC 4648, lowercase, no padding) then group into 5-char
/// chunks separated by '-' — the textual principal format.
String _base32Grouped(List<int> bytes) {
  final sb = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      sb.write(_base32Alphabet[(buffer >>> bits) & 0x1F]);
    }
  }
  if (bits > 0) {
    sb.write(_base32Alphabet[(buffer << (5 - bits)) & 0x1F]);
  }
  final encoded = sb.toString();
  // Group into chunks of 5, joined by '-' (no trailing padding).
  final out = StringBuffer();
  for (var i = 0; i < encoded.length; i += 5) {
    final end = i + 5 < encoded.length ? i + 5 : encoded.length;
    if (i > 0) {
      out.write('-');
    }
    out.write(encoded.substring(i, end));
  }
  return out.toString();
}

/// Derive the ICP self-authenticating principal text from a DER-encoded
/// SubjectPublicKeyInfo. Pure function — identical output to
/// `candid::Principal::self_authenticating(der).to_text()`.
///
/// The algorithm (`ic_principal-0.1.1`):
///   1. hash = SHA-224(der_bytes)            → 28 bytes
///   2. principal = hash ++ [0x02]           → 29 bytes  (tag 0x02 is APPENDED)
///   3. crc = CRC32(principal).to_be_bytes() → 4 bytes  (zlib/IEEE, big-endian)
///   4. checksummed = crc ++ principal       → 33 bytes
///   5. base32 (RFC 4648, NO-PAD, then LOWERCASE), grouped 5-chars per '-'.
///
/// Shared between Ed25519 (RFC 8410 DER) and secp256k1 (RFC 5480 DER) — only
/// the DER prefix differs (DRY: one principal algorithm, two prefixes).
String _selfAuthPrincipalFromDer(List<int> der) {
  // 1. SHA-224 → 28 bytes.
  final hash = crypto.sha224.convert(der).bytes;
  // 2. self-auth principal = hash ++ [0x02] (tag APPENDED — matches ic_principal).
  final principalBytes = Uint8List.fromList([...hash, 0x02]); // 29 bytes
  // 3. CRC32 over the principal, big-endian.
  final crc = _crc32(principalBytes);
  final crcBytes = [
    (crc >>> 24) & 0xFF,
    (crc >>> 16) & 0xFF,
    (crc >>> 8) & 0xFF,
    crc & 0xFF,
  ];
  // 4. checksummed payload.
  final checksummed = Uint8List.fromList([...crcBytes, ...principalBytes]);
  // 5. base32 (lowercase) + group.
  return _base32Grouped(checksummed);
}

/// Derive the ICP principal from a raw Ed25519 32-byte public key.
String _principalFromEd25519PublicKey(Uint8List publicKey) {
  if (publicKey.length != 32) {
    throw ArgumentError(
        'Ed25519 public key must be 32 bytes, got ${publicKey.length}');
  }
  // SPKI DER (RFC 8410) = prefix ++ 32-byte pubkey.
  return _selfAuthPrincipalFromDer([..._ed25519DerPrefix, ...publicKey]);
}

/// Derive the ICP principal from a secp256k1 public key. Accepts the
/// uncompressed 65-byte form (`0x04||X||Y`) OR the raw 64-byte form (`X||Y`,
/// which is normalized by prepending `0x04`) — matching the native
/// `der_encode_public_key("secp256k1", ..)` (principal.rs:26-41). Mirrors the
/// native `k256::PublicKey::from_sec1_bytes` → `to_public_key_der()` path.
String _principalFromSecp256k1PublicKey(Uint8List publicKey) {
  final List<int> point;
  if (publicKey.length == 65) {
    if (publicKey[0] != 0x04) {
      throw ArgumentError(
          'A 65-byte secp256k1 public key must start with 0x04 (uncompressed), '
          'got 0x${publicKey[0].toRadixString(16).padLeft(2, '0')}');
    }
    point = publicKey;
  } else if (publicKey.length == 64) {
    // Raw X||Y → prepend the uncompressed-point marker.
    point = [0x04, ...publicKey];
  } else {
    throw ArgumentError(
        'secp256k1 public key must be 65 bytes (0x04||X||Y) or 64 bytes '
        '(X||Y), got ${publicKey.length}');
  }
  // SPKI DER (RFC 5480) = prefix (ends in the BIT STRING 0x00) ++ 65-byte point.
  return _selfAuthPrincipalFromDer([..._secp256k1DerPrefix, ...point]);
}

/// Derive the Ed25519 public key (32 bytes) from a 32-byte seed.
/// Deterministic (RFC 8032) — same seed always yields the same public key,
/// matching `ed25519_dalek`.
Uint8List _ed25519PublicKeyFromSeed(Uint8List seed) {
  if (seed.length != 32) {
    throw ArgumentError('Ed25519 seed must be 32 bytes, got ${seed.length}');
  }
  final priv = ed.newKeyFromSeed(seed); // PrivateKey = seed(32) || pub(32)
  return Uint8List.fromList(ed.public(priv).bytes);
}

/// BIP39 `to_seed` — PBKDF2-HMAC-SHA512 over the mnemonic, salt
/// `"mnemonic" + passphrase`, 2048 iterations, 64-byte output (RFC 2898 /
/// BIP39). Pure-Dart and synchronous via `package:crypto`.
///
/// NOTE: `package:bip39`'s `mnemonicToSeed` produces a DIFFERENT (incorrect)
/// value for 24-word mnemonics — verified against the Rust reference
/// (`bip39` v2 crate `Mnemonic::to_seed("")`) and the standard Trezor BIP39
/// vectors. This manual implementation is bit-for-bit identical to Rust and to
/// the BIP39 spec (12- and 24-word vectors both match), so keypairs derived
/// here match the native `libicp_core` exactly.
Uint8List _bip39MnemonicToSeed(String mnemonic, {String passphrase = ''}) {
  final password = utf8.encode(mnemonic);
  final salt = utf8.encode('mnemonic$passphrase');
  // PBKDF2: dkLen=64 == hlen(64) → a single block T_1 = U_1 ^ U_2 ^ ... ^ U_c.
  var u = crypto.Hmac(crypto.sha512, password).convert([...salt, 0, 0, 0, 1]).bytes;
  final result = List<int>.from(u);
  for (var i = 1; i < 2048; i++) {
    u = crypto.Hmac(crypto.sha512, password).convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return Uint8List.fromList(result);
}

// ─────────────────────────────────────────────────────────────────────────────
// Argon2id + AES-256-GCM constants — SINGLE source of truth on Web.
//
// These MUST match `crates/icp_core/src/vault.rs:18-24` exactly for native ↔
// web vault interoperability. The Argon2id vector test guarantees this.
// ─────────────────────────────────────────────────────────────────────────────
const int _argon2MemoryCost = 65536; // 64 MiB (KiB blocks)
const int _argon2TimeCost = 3;
const int _argon2Parallelism = 4;
const int _argon2HashLength = 32;
const int _saltLength = 16;
const int _nonceLength = 12;
const int _aesGcmTagLength = 16;

/// Lazily-built Argon2id instance with the Bitwarden-level params above.
/// `DartArgon2id` is a pure-Dart implementation (RFC 9106, version 0x13) —
/// its `version` getter returns 19, matching Rust's `argon2::Version::V0x13`.
DartArgon2id _argon2id() => const DartArgon2id(
      parallelism: _argon2Parallelism,
      memory: _argon2MemoryCost,
      iterations: _argon2TimeCost,
      hashLength: _argon2HashLength,
    );

/// Derive the 32-byte AES-256 key from `password` and `salt` via Argon2id.
Future<Uint8List> _deriveVaultKey({
  required String password,
  required Uint8List salt,
}) async {
  final secret = await _argon2id().deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: salt,
  );
  return Uint8List.fromList(await secret.extractBytes());
}

class RustBridgeLoader {
  const RustBridgeLoader();

  /// Generate a keypair from a BIP39 mnemonic.
  ///
  /// [mnemonic] MUST be a valid BIP39 phrase (the Dart caller
  /// `KeypairGenerator._resolveMnemonic` always supplies one).
  /// - alg=0 (Ed25519): the Ed25519 secret is the first 32 bytes of the BIP39
  ///   seed — identical to Rust's `generate_ed25519_keypair`.
  /// - alg=1 (secp256k1, BIP32 `m/44'/223'/0'/0/0`): 32-byte private key +
  ///   65-byte uncompressed public key — identical to Rust's
  ///   `generate_secp256k1_keypair` (WU-2, native parity).
  RustKeypairResult? generateKeypair({required int alg, String? mnemonic}) {
    if (alg != _algEd25519 && alg != _algSecp256k1) {
      throw ArgumentError.value(alg, 'alg', 'Unsupported algorithm code');
    }
    if (mnemonic == null || mnemonic.trim().isEmpty) {
      // The Dart caller always resolves a mnemonic first; reaching here is a
      // programming error. Fail loud rather than inventing entropy.
      throw ArgumentError(
          'generateKeypair on Web requires a non-empty BIP39 mnemonic');
    }
    // BIP39 mnemonic → 64-byte seed (PBKDF2-HMAC-SHA512, 2048 iters). The
    // standard derivation is implemented inline (see `_bip39MnemonicToSeed`)
    // because `package:bip39`'s `mnemonicToSeed` is incorrect for 24-word
    // mnemonics. Pure Dart — works on VM and Web.
    final seedFull = _bip39MnemonicToSeed(mnemonic);

    if (alg == _algEd25519) {
      final seed = Uint8List.fromList(seedFull.sublist(0, 32));
      final publicKey = _ed25519PublicKeyFromSeed(seed);
      return RustKeypairResult(
        publicKeyB64: base64.encode(publicKey),
        privateKeyB64: base64.encode(seed), // 32-byte seed (RFC 8032)
        principalText: _principalFromEd25519PublicKey(publicKey),
      );
    }
    // alg == _algSecp256k1: BIP32 m/44'/223'/0'/0/0 (WU-2, native parity).
    final privateKey = secp256k1DerivePrivateKey(seedFull); // 32 bytes
    final publicKey = secp256k1UncompressedPublicKey(privateKey); // 65 bytes
    return RustKeypairResult(
      publicKeyB64: base64.encode(publicKey),
      privateKeyB64: base64.encode(privateKey),
      principalText: _principalFromSecp256k1PublicKey(publicKey),
    );
  }

  /// Derive the ICP principal text from a base64-encoded raw public key.
  ///
  /// - alg=0 (Ed25519): SPKI DER (RFC 8410) → SHA-224 → self-auth principal.
  /// - alg=1 (secp256k1): SPKI DER (RFC 5480) → SHA-224 → self-auth principal
  ///   (WU-2, native parity). Accepts the 65-byte uncompressed key or the
  ///   64-byte raw X||Y form.
  String? principalFromPublicKey({required int alg, required String publicKeyB64}) {
    if (alg != _algEd25519 && alg != _algSecp256k1) {
      throw ArgumentError.value(alg, 'alg', 'Unsupported algorithm code');
    }
    final publicKey = Uint8List.fromList(base64.decode(publicKeyB64));
    if (alg == _algSecp256k1) {
      return _principalFromSecp256k1PublicKey(publicKey);
    }
    return _principalFromEd25519PublicKey(publicKey);
  }

  /// Sign `messageB64` (base64 of raw message bytes) with a private key.
  ///
  /// - alg=0 (Ed25519): signs the message directly (RFC 8032); the private key
  ///   is the 32-byte seed.
  /// - alg=1 (secp256k1): SHA-256(message) → RFC 6979 deterministic low-S
  ///   ECDSA → 64-byte compact signature (WU-2, native parity).
  ///
  /// Returns the SAME JSON envelope the native FFI (`icp_sign_message`)
  /// returns — `{"ok":true,"signature":"<base64>"}` — so callers
  /// (`AccountSignatureService` / `ScriptSignatureService`) that `jsonDecode`
  /// the result work unchanged on Web.
  String? signMessage({
    required int alg,
    required String messageB64,
    required String privateKeyB64,
  }) {
    if (alg != _algEd25519 && alg != _algSecp256k1) {
      throw ArgumentError.value(alg, 'alg', 'Unsupported algorithm code');
    }
    final message = Uint8List.fromList(base64.decode(messageB64));
    final privateKey = Uint8List.fromList(base64.decode(privateKeyB64));

    final List<int> signature;
    if (alg == _algSecp256k1) {
      signature = secp256k1Sign(message, privateKey); // 64 bytes, RFC 6979 low-S
    } else {
      if (privateKey.length != 32) {
        throw ArgumentError(
            'Ed25519 private key (seed) must be 32 bytes, got ${privateKey.length}');
      }
      final publicKey = _ed25519PublicKeyFromSeed(privateKey);
      // ed25519_edwards PrivateKey is seed(32) || pub(32) (Go convention).
      signature = ed.sign(
        ed.PrivateKey(Uint8List.fromList([...privateKey, ...publicKey])),
        message,
      );
    }
    final sigB64 = base64.encode(signature);
    // Match the native FFI contract exactly (json!({"ok":true,"signature":..})).
    return jsonEncode(<String, dynamic>{'ok': true, 'signature': sigB64});
  }

  /// R-3b WU-2 — fetch a canister's Candid `.did` interface (mainnet parity
  /// with native `fetch_candid`, `canister_client.rs:529`). On Web this drives
  /// the vendored `@dfinity/agent` bundle's `fetchCandid` (a certified
  /// `read_state` for the `candid:service` metadata, with the
  /// `__get_candid_interface_tmp_hack` query fallback — the SAME two sources
  /// agent-js + the native client consult). The agent is routed through the
  /// backend CORS byte-relay proxy (`/api/v1/ic`, plan §7.2) because `ic0.app`
  /// sends no CORS headers for `/api/v2/*`.
  ///
  /// [host] is IGNORED on Web — the agent's `host` is fixed to `https://ic0.app`
  /// (so the mainnet root key is baked in + `verifyQuerySignatures` works) and
  /// the proxy is single-upstream (§7.8.5). The native `host` override (used to
  /// point at a testnet) has no Web equivalent; this is a documented, scoped
  /// deviation (R-3b decisions locked: proxy single-upstream).
  ///
  /// Returns the raw candid TEXT (byte-identical to native) or `null` on any
  /// failure (network / canister not found / no candid metadata) — parity with
  /// the native FFI (`null_c_string` on `Err`, `ffi.rs:228`). The agent-js
  /// bundle must have loaded first (`probeIcAgentReadiness`); if not, this
  /// throws a loud `StateError` (never silently no-ops).
  Future<String?> fetchCandid({required String canisterId, String? host}) async {
    return icagent.webFetchCandid(canisterId: canisterId);
  }

  /// R-3b WU-2 — parse a Candid `.did` interface into the
  /// `{"methods":[{"name","kind","args","rets"}]}` JSON shape (pure-Dart port
  /// of native `parse_candid_interface`, `canister_client.rs:161-201`). Pure
  /// compute — no network, no `dart:js_interop` — so this is SYNCHRONOUS on Web
  /// exactly as on native (`String? parseCandid`, not `Future`). Runs unchanged
  /// on the VM (VM-testable via `candid_parse_golden_vectors_test.dart`).
  ///
  /// Returns the compact JSON string (byte-identical to the native FFI's
  /// `serde_json::to_string` output) or `null` on any parse error (parity:
  /// native returns `null_c_string` on `Err`, `ffi.rs:243-247`).
  String? parseCandid({required String candidText}) {
    return parseCandidInterface(candidText);
  }

  /// R-3b WU-3 — anonymous canister call. Mirrors native `call_anonymous`
  /// (`canister_client.rs:569-651`) via agent-js routed through the CORS proxy.
  ///
  /// Returns the JSON envelope:
  /// - `{"ok":true,"result":<json>}` on success
  /// - `{"ok":false,"kind":"invalid_canister_id"|"net"|"candid","error":"…"}`
  ///   on failure (parity with the native FFI `canister_err_ptr`, `ffi.rs:78-87`)
  ///
  /// [args] supports `()` / `base64:` raw bytes / JSON (`build_args_from_json`
  /// parity via the pure-Dart candid parser). Textual candid arg expressions
  /// are an honest deviation (typed `candid` error — see plan §7.5).
  ///
  /// Async (WU-4 signature widening) — the agent-js calls are inherently async
  /// (network). The native FFI is sync but returns `Future.value(...)` for
  /// facade uniformity (greenfield, no back-compat — plan §7.6).
  ///
  /// [host] is IGNORED on Web (the agent's host is fixed to `https://ic0.app`
  /// so the mainnet root key is baked in; the proxy is single-upstream — plan
  /// §7.2/§7.8.5). Documented, scoped deviation.
  Future<String?> callAnonymous({
    required String canisterId,
    required String method,
    required int mode,
    String args = '()',
    String? host,
  }) =>
      icagent.webCallAnonymous(
        canisterId: canisterId,
        method: method,
        mode: mode,
        args: args,
      );

  /// R-3b WU-4 — authenticated canister call with an Ed25519 identity.
  /// Mirrors native `call_authenticated` (`canister_client.rs:653-746`).
  /// [privateKeyB64] is the base64 32-byte Ed25519 seed — `Ed25519KeyIdentity
  /// .fromSecretKey(seed)` ≡ native `BasicIdentity::from_raw_key` (byte-parity,
  /// plan §7.3.3). Same envelope + args contract as [callAnonymous].
  Future<String?> callAuthenticated({
    required String canisterId,
    required String method,
    required int mode,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) =>
      icagent.webCallAuthenticated(
        canisterId: canisterId,
        method: method,
        mode: mode,
        privateKeyB64: privateKeyB64,
        args: args,
      );

  /// R-3: execute a JS bundle and return the `{ok,result,messages}` /
  /// `{ok,error}` envelope (mirrors the native FFI `icp_js_exec`). The engine
  /// MUST be loaded first — see [probeQuickJsReadiness] / the readiness gate.
  String? jsExec({required String script, String? jsonArg}) {
    return qjs.execWebJs(script, jsonArg: jsonArg);
  }

  String? jsLint({required String script}) {
    // `lint_js` (`runtime.rs:257-267`): auto-detects context (context=None →
    // default_context) and wraps `validate_js_comprehensive`. Envelope:
    //   {ok, errors:[{message}], warnings:[string], line_count, character_count}
    final result = _validateComprehensive(script, defaultContext(script));
    return jsonEncode(<String, dynamic>{
      'ok': result.isValid,
      'errors': result.syntaxErrors
          .map((e) => <String, dynamic>{'message': e})
          .toList(growable: false),
      'warnings': result.warnings,
      'line_count': result.lineCount,
      'character_count': result.characterCount,
    });
  }

  String? validateJsComprehensive({
    required String script,
    bool isExample = false,
    bool isTest = false,
    bool isProduction = false,
  }) {
    // `icp_js_validate_comprehensive` (`ffi.rs:348-376`): context built
    // DIRECTLY from the caller's flags (no auto-detect). Envelope:
    //   {is_valid, syntax_errors:[string], warnings, line_count, character_count}
    final context = JsValidationContext(
      isExample: isExample,
      isTest: isTest,
      isProduction: isProduction,
    );
    final result = _validateComprehensive(script, context);
    return jsonEncode(<String, dynamic>{
      'is_valid': result.isValid,
      'syntax_errors': result.syntaxErrors,
      'warnings': result.warnings,
      'line_count': result.lineCount,
      'character_count': result.characterCount,
    });
  }

  /// Port of `validate_js_comprehensive` (`runtime.rs:188-255`): run the
  /// pure-Dart static stages; if they pass, run the runtime stage (syntax +
  /// required-exports) via the loaded Web engine. The static stages are
  /// VM-testable; the runtime stage is browser-only (rides on the `qjs` access
  /// module) — the early-return when static stages fail keeps the common
  /// negative cases VM-testable end-to-end.
  JsValidationResult _validateComprehensive(
      String script, JsValidationContext context) {
    final result = runStaticStages(script, context);
    if (!result.isValid) return result; // runtime.rs:193-195
    result.syntaxErrors.addAll(qjs.webJsValidateRuntimeStage(script));
    result.isValid = result.syntaxErrors.isEmpty;
    return result;
  }

  /// R-3: app lifecycle — `init(arg)→{state,effects}` (mirrors native
  /// `icp_js_app_init`). Engine must be loaded (readiness gate).
  String? jsAppInit({required String script, String? jsonArg, int budgetMs = 50}) {
    return qjs.webJsAppInit(script, jsonArg: jsonArg, budgetMs: budgetMs);
  }

  /// R-3: app lifecycle — `view(state)→{ok,ui}` (mirrors native
  /// `icp_js_app_view`).
  String? jsAppView({required String script, required String stateJson, int budgetMs = 50}) {
    return qjs.webJsAppView(script, stateJson: stateJson, budgetMs: budgetMs);
  }

  /// R-3: app lifecycle — `update(msg,state)→{state,effects}` (mirrors native
  /// `icp_js_app_update`).
  String? jsAppUpdate({
    required String script,
    required String msgJson,
    required String stateJson,
    int budgetMs = 50,
  }) {
    return qjs.webJsAppUpdate(script,
        msgJson: msgJson, stateJson: stateJson, budgetMs: budgetMs);
  }

  /// Encrypt `plaintextB64` under `password` (Argon2id KDF + AES-256-GCM).
  ///
  /// Produces a blob byte-compatible with `crates/icp_core::encrypt_vault`:
  /// the AES-GCM authentication tag is APPENDED to the ciphertext (16 bytes),
  /// matching the `aes-gcm` crate's `Aead::encrypt` layout, so a blob created
  /// on Web can be decrypted by native and vice-versa.
  ///
  /// Async because Argon2id is a cooperatively-scheduled pure-Dart computation.
  Future<EncryptedVaultResult?> encryptVault({
    required String password,
    required String plaintextB64,
  }) async {
    final plaintext = Uint8List.fromList(base64.decode(plaintextB64));
    final random = Random.secure();
    final salt =
        Uint8List.fromList(List<int>.generate(_saltLength, (_) => random.nextInt(256)));
    final nonce =
        Uint8List.fromList(List<int>.generate(_nonceLength, (_) => random.nextInt(256)));

    final key = await _deriveVaultKey(password: password, salt: salt);

    final cipher = AesGcm.with256bits();
    final secretBox = await cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    // ciphertext || tag — native-compatible layout.
    final ciphertextWithTag = Uint8List.fromList(
      [...secretBox.cipherText, ...secretBox.mac.bytes],
    );

    return EncryptedVaultResult(
      encryptedDataB64: base64.encode(ciphertextWithTag),
      saltB64: base64.encode(salt),
      nonceB64: base64.encode(nonce),
    );
  }

  /// Decrypt an Argon2id + AES-256-GCM blob. Throws
  /// [VaultDecryptionException] on a wrong password or tampered ciphertext
  /// (GCM auth-tag failure) — fail-fast, never returns garbage plaintext.
  ///
  /// Async because Argon2id is a cooperatively-scheduled pure-Dart computation.
  Future<String?> decryptVault({
    required String password,
    required String encryptedDataB64,
    required String saltB64,
    required String nonceB64,
  }) async {
    final encrypted = base64.decode(encryptedDataB64);
    if (encrypted.length < _aesGcmTagLength) {
      throw VaultDecryptionException(
          'Decryption failed: ciphertext too short (${encrypted.length} bytes)');
    }
    final salt = Uint8List.fromList(base64.decode(saltB64));
    final nonce = Uint8List.fromList(base64.decode(nonceB64));

    final key = await _deriveVaultKey(password: password, salt: salt);

    // Split ciphertext || tag (native-compatible layout).
    final cipherText = encrypted.sublist(0, encrypted.length - _aesGcmTagLength);
    final mac = encrypted.sublist(encrypted.length - _aesGcmTagLength);

    final cipher = AesGcm.with256bits();
    try {
      final plaintext = await cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
      );
      return base64.encode(plaintext);
    } on SecretBoxAuthenticationError {
      // Not a silent swallow: this is the deliberate, loud translation of the
      // AEAD auth-tag failure into the same VaultDecryptionException the native
      // FFI throws (vault.rs::decrypt_vault returns the identical message).
      throw VaultDecryptionException(
          'Decryption failed: invalid password or corrupted data');
    }
  }
}

class NativeBridge {
  final RustBridgeLoader _loader = const RustBridgeLoader();

  String validateJsComprehensive({
    required String script,
    bool isExample = false,
    bool isTest = false,
    bool isProduction = false,
  }) {
    return _loader.validateJsComprehensive(
          script: script,
          isExample: isExample,
          isTest: isTest,
          isProduction: isProduction,
        ) ??
        '';
  }

  String? jsExec({required String script, String? jsonArg}) {
    return _loader.jsExec(script: script, jsonArg: jsonArg);
  }

  String? jsLint({required String script}) {
    return _loader.jsLint(script: script);
  }
}
