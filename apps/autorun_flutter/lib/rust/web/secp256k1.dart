/// Pure-Dart secp256k1: BIP32 key derivation, uncompressed-public-key
/// computation, and RFC 6979 deterministic low-S ECDSA signing.
///
/// This is the Web port of the native Rust core
/// (`crates/icp_core/src/keypair.rs:43-129`). It is **pure Dart** (no
/// `dart:io`, no `dart:js_interop`, no `dart:html`), so it runs unchanged on
/// the Dart VM AND ships to the browser — the same code paths are exercised by
/// `flutter test` (cross-compat golden vectors vs. `libicp_core`) and by
/// production Web builds. Mirrors the established pattern of
/// `js_static_analysis.dart` / `candid_interface_parser.dart`.
///
/// ## Native parity (byte-for-byte, verified by golden vectors)
/// - **Key derivation** mirrors `generate_secp256k1_keypair` (keypair.rs:43-67):
///   BIP39 seed → `Xpriv::new_master` (HMAC-SHA512 `"Bitcoin seed"`) → derive
///   `m/44'/223'/0'/0/0` → 32-byte private key. `package:bip32`'s `BIP32
///   .fromSeed` + `derivePath` is the same HMAC-SHA512 derivation.
/// - **Public key** mirrors `PublicKey::from_secret_key(...).serialize_uncompressed()`
///   (keypair.rs:55-56): the 65-byte uncompressed point `0x04||X||Y`.
///   `package:elliptic`'s secp256k1 curve computes the same `d*G`.
/// - **Signing** mirrors `sign_secp256k1` (keypair.rs:99-129): SHA-256(message)
///   → RFC 6979 deterministic (HMAC-SHA256) ECDSA → compact 64-byte `r||s`
///   with **low-S** normalization (BIP 146). The `bitcoin` crate's `sign_ecdsa`
///   produces RFC 6979 deterministic low-S signatures, so this implementation
///   is byte-identical for the same key+message.
///
/// ## Why RFC 6979 is implemented here (not from a package)
/// `package:elliptic`'s `sign` uses a **random** k (non-deterministic) — that
/// would NOT match the native deterministic output. `package:pointycastle` has
/// a correct RFC 6979 implementation, but it is a **dev-only** dependency
/// (`pubspec.yaml`) so it is not imported into `lib/`. RFC 6979 (§3.2) is
/// ~40 lines over `package:elliptic`'s curve ops + `package:crypto`'s
/// HMAC-SHA256 — self-contained, auditable, prod-dep-only.
library;

import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:crypto/crypto.dart' as crypto;
import 'package:elliptic/elliptic.dart' as elliptic;

/// BIP32 derivation path for ICP secp256k1 keys — mirrors the native
/// `generate_secp256k1_keypair` (keypair.rs:52). Purpose 44' (BIP44), coin 223'
/// (ICP's registered coin type), account 0', external chain 0, address index 0.
const String secp256k1DerivationPath = "m/44'/223'/0'/0/0";

/// Derive the 32-byte secp256k1 private key from a 64-byte BIP39 seed via BIP32
/// (`m/44'/223'/0'/0/0`). Mirrors `Xpriv::new_master(Network::Bitcoin, &seed)`
/// followed by `derive_priv` (keypair.rs:51-53).
///
/// [seed] is the 64-byte `mnemonic.to_seed("")` (PBKDF2-HMAC-SHA512, 2048
/// iterations) — the SAME seed the native core and the Ed25519 Web path use.
Uint8List secp256k1DerivePrivateKey(Uint8List seed) {
  if (seed.length != 64) {
    throw ArgumentError('BIP39 seed must be 64 bytes, got ${seed.length}');
  }
  final node = bip32.BIP32.fromSeed(seed).derivePath(secp256k1DerivationPath);
  final priv = node.privateKey;
  if (priv == null || priv.length != 32) {
    throw StateError(
        'BIP32 $secp256k1DerivationPath derivation did not yield a 32-byte '
        'private key (got ${priv?.length} bytes)');
  }
  return Uint8List.fromList(priv);
}

/// Compute the uncompressed secp256k1 public key (65 bytes: `0x04||X||Y`) for a
/// 32-byte private key. Mirrors
/// `PublicKey::from_secret_key(...).serialize_uncompressed()` (keypair.rs:55-56).
///
/// The point is `d*G` over secp256k1 — the same point `k256` computes for the
/// same scalar, so the DER / principal derived downstream is identical.
Uint8List secp256k1UncompressedPublicKey(Uint8List privateKey) {
  final d = _validatePrivateKey(privateKey);
  final curve = elliptic.getS256();
  final pub = elliptic.PrivateKey(curve, d).publicKey;
  final out = Uint8List(65);
  out[0] = 0x04;
  out.setRange(1, 33, _bigIntToFixedBytes(pub.X, 32));
  out.setRange(33, 65, _bigIntToFixedBytes(pub.Y, 32));
  return out;
}

/// Sign [message] with a 32-byte secp256k1 private key using RFC 6979
/// deterministic (HMAC-SHA256) low-S ECDSA. Returns the 64-byte compact
/// signature (`r||s`). Byte-identical to the native `sign_secp256k1`
/// (keypair.rs:99-129) for the same inputs.
///
/// Steps (mirror the native code exactly):
/// 1. `hash = SHA-256(message)` (32 bytes).
/// 2. RFC 6979 deterministic k (HMAC-SHA256, no extra entropy — matches the
///    `secp256k1` C library's `secp256k1_ecdsa_sign`).
/// 3. `r = (k*G).x mod n`; `s = k⁻¹(e + x·r) mod n` (retry next k on r=0/s=0).
/// 4. low-S: if `s > n/2`, `s = n - s`.
/// 5. Output `r(32) || s(32)`.
Uint8List secp256k1Sign(Uint8List message, Uint8List privateKey) {
  final x = _validatePrivateKey(privateKey);
  final curve = elliptic.getS256();
  final n = curve.n;

  // 1. SHA-256(message) → 32-byte digest (keypair.rs:118-120).
  final h1 = Uint8List.fromList(crypto.sha256.convert(message).bytes);
  // 2. ECDSA e = bits2int(hash) (no truncation for 256-bit hash / 256-bit n).
  final e = _bits2int(n, h1);

  // 3. RFC 6979 §3.2 deterministic k + ECDSA signing loop.
  final kGen = _Rfc6979K(n, x, h1);
  while (true) {
    final k = kGen.next();
    final point = curve.scalarBaseMul(_bigIntToFixedBytes(k, 32));
    final r = point.X % n;
    if (r == BigInt.zero) continue; // RFC 6979: reject, fetch next k
    final s = (k.modInverse(n) * (e + x * r)) % n;
    if (s == BigInt.zero) continue; // RFC 6979: reject, fetch next k
    // 4. low-S normalization (BIP 146 — the secp256k1 library default).
    final sLow = s > (n >> 1) ? n - s : s;
    // 5. r(32) || s(32).
    final sig = Uint8List(64);
    sig.setRange(0, 32, _bigIntToFixedBytes(r, 32));
    sig.setRange(32, 64, _bigIntToFixedBytes(sLow, 32));
    return sig;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RFC 6979 §3.2 — deterministic k generation (HMAC-SHA256).
//
// Faithful to the RFC; the only curve-specific inputs are the order `n` and the
// private scalar `x`. For secp256k1 + SHA-256: hlen = qlen = 256, rolen = 32.
// This is the SAME algorithm the `secp256k1` C library uses internally
// (`secp256k1_ecdsa_sign` with NULL extra data → RFC 6979 SHA-256), so the
// generated k (and hence r, s) is byte-identical to the native output.
// ─────────────────────────────────────────────────────────────────────────────

class _Rfc6979K {
  _Rfc6979K(this._n, this._x, Uint8List h1)
      : _qlen = _n.bitLength,
        _rolen = (_n.bitLength + 7) ~/ 8 {
    // §3.2 step b: V = 0x01 * hlen.
    _v = Uint8List(32)..fillRange(0, 32, 0x01);
    // §3.2 step c: K = 0x00 * hlen.
    _k = Uint8List(32);
    final xOct = _int2octets(_x);
    final h1Oct = _bits2octets(h1);

    // §3.2 step d: K = HMAC_K(V || 0x00 || int2octets(x) || bits2octets(h1)).
    _k = _hmac(_k, [..._v, 0x00, ...xOct, ...h1Oct]);
    // §3.2 step e: V = HMAC_K(V).
    _v = _hmac(_k, _v);
    // §3.2 step f: K = HMAC_K(V || 0x01 || int2octets(x) || bits2octets(h1)).
    _k = _hmac(_k, [..._v, 0x01, ...xOct, ...h1Oct]);
    // §3.2 step g: V = HMAC_K(V).
    _v = _hmac(_k, _v);
  }

  final BigInt _n;
  final BigInt _x;
  final int _qlen;
  final int _rolen;
  late Uint8List _v;
  late Uint8List _k;

  /// Whether the previously-returned k was consumed (and thus rejected by the
  /// caller). The next [next] must first apply the RFC 6979 post-rejection
  /// retry step (K = HMAC_K(V || 0x00); V = HMAC_K(V)) before regenerating T.
  var _consumed = false;

  /// Return the next valid k in `[1, n-1]`. The caller may reject it (ECDSA
  /// r=0 / s=0) and call [next] again — the post-rejection retry step is then
  /// applied automatically, exactly as RFC 6979 prescribes.
  BigInt next() {
    if (_consumed) {
      _retry();
      _consumed = false;
    }
    // §3.2 step h.
    while (true) {
      // h.2: T = (while tlen < qlen: V = HMAC_K(V); T = T || V).
      final t = <int>[];
      while (t.length < _rolen) {
        _v = _hmac(_k, _v);
        t.addAll(_v);
      }
      // h.3: k = bits2int(T).
      final k = _bits2int(_n, Uint8List.fromList(t));
      // h.4: if 1 <= k < n, return k.
      if (k >= BigInt.one && k < _n) {
        _consumed = true;
        return k;
      }
      // k out of range → retry step, then regenerate T.
      _retry();
    }
  }

  /// RFC 6979 retry step: `K = HMAC_K(V || 0x00); V = HMAC_K(V)`.
  void _retry() {
    _k = _hmac(_k, [..._v, 0x00]);
    _v = _hmac(_k, _v);
  }

  Uint8List _hmac(Uint8List key, List<int> data) =>
      Uint8List.fromList(crypto.Hmac(crypto.sha256, key).convert(data).bytes);

  /// RFC 6979 bits2int: big-endian decode of [b], then right-shift to `qlen`
  /// bits if the input is longer.
  BigInt _bits2intInt(Uint8List b) {
    var z = _bytesToBigInt(b);
    final blen = b.length * 8;
    if (blen > _qlen) {
      z = z >> (blen - _qlen);
    }
    return z;
  }

  /// RFC 6979 int2octets: `rolen`-byte big-endian of `z` (`z < n`).
  Uint8List _int2octets(BigInt z) => _bigIntToFixedBytes(z, _rolen);

  /// RFC 6979 bits2octets: `z1 = bits2int(b); z2 = z1 - n; z = (z2 >= 0) ? z2 : z1`.
  Uint8List _bits2octets(Uint8List b) {
    final z1 = _bits2intInt(b);
    final z2 = z1 - _n;
    return _int2octets(z2.isNegative ? z1 : z2);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BigInt / byte helpers.
// ─────────────────────────────────────────────────────────────────────────────

final BigInt _byteMask = BigInt.from(0xff);

/// Decode [bytes] as a big-endian unsigned integer.
BigInt _bytesToBigInt(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b);
  }
  return r;
}

/// Encode [value] as a big-endian, zero-padded fixed-length byte array.
Uint8List _bigIntToFixedBytes(BigInt value, int len) {
  final out = Uint8List(len);
  var x = value;
  for (var i = len - 1; i >= 0; i--) {
    out[i] = (x & _byteMask).toInt();
    x = x >> 8;
  }
  return out;
}

/// RFC 6979 bits2int (top-level): big-endian decode then right-shift to `qlen`
/// bits. Used for the ECDSA value `e = bits2int(H(m))`.
BigInt _bits2int(BigInt n, Uint8List b) {
  var z = _bytesToBigInt(b);
  final qlen = n.bitLength;
  final blen = b.length * 8;
  if (blen > qlen) {
    z = z >> (blen - qlen);
  }
  return z;
}

/// Validate a 32-byte secp256k1 private key and return its scalar in `[1, n-1]`.
BigInt _validatePrivateKey(Uint8List privateKey) {
  if (privateKey.length != 32) {
    throw ArgumentError(
        'secp256k1 private key must be 32 bytes, got ${privateKey.length}');
  }
  final d = _bytesToBigInt(privateKey);
  final n = elliptic.getS256().n;
  if (d < BigInt.one || d >= n) {
    throw ArgumentError('secp256k1 private key scalar out of range [1, n-1]');
  }
  return d;
}
