import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart' as convert;

import '../models/identity_record.dart';

/// Utilities for deriving and formatting Internet Computer principals
/// from locally generated public keys.
class PrincipalUtils {
  const PrincipalUtils._();

  // DER SubjectPublicKeyInfo prefixes
  // Ed25519: 302a300506032b6570032100 || 32-byte raw public key
  static final Uint8List _ed25519DerPrefix = Uint8List.fromList(
    convert.hex.decode('302a300506032b6570032100'),
  );

  // secp256k1 SPKI:
  // 30 56                        ; SEQUENCE (len 86)
  //    30 10                     ; SEQUENCE (len 16)
  //       06 07 2a8648ce3d0201   ; OID 1.2.840.10045.2.1 (ecPublicKey)
  //       06 05 2b8104000a       ; OID 1.3.132.0.10 (secp256k1)
  //    03 42 00                  ; BIT STRING (len 66), 0 unused bits
  //       04 <X:32><Y:32>        ; uncompressed point (65 bytes)
  // We split before the 0x04 so we can append the full 65-byte uncompressed key as-is.
  static final Uint8List _secp256k1DerPrefix = Uint8List.fromList(
    convert.hex.decode('3056301006072a8648ce3d020106052b8104000a034200'),
  );

  /// Compute the DER-encoded SubjectPublicKeyInfo for the given algorithm
  /// and public key bytes.
  static Uint8List derEncodePublicKey(
    KeyAlgorithm algorithm,
    Uint8List publicKeyBytes,
  ) {
    switch (algorithm) {
      case KeyAlgorithm.ed25519:
        if (publicKeyBytes.length != 32) {
          throw ArgumentError('Ed25519 public key must be 32 bytes');
        }
        return Uint8List.fromList(<int>[
          ..._ed25519DerPrefix,
          ...publicKeyBytes,
        ]);
      case KeyAlgorithm.secp256k1:
        // Expect uncompressed 65-byte point (0x04 | X:32 | Y:32)
        if (publicKeyBytes.length == 64) {
          // If 64 bytes without 0x04 prefix, prepend it.
          publicKeyBytes = Uint8List.fromList(<int>[0x04, ...publicKeyBytes]);
        }
        if (publicKeyBytes.length != 65 || publicKeyBytes[0] != 0x04) {
          throw ArgumentError(
            'secp256k1 public key must be uncompressed 65 bytes starting with 0x04',
          );
        }
        return Uint8List.fromList(<int>[
          ..._secp256k1DerPrefix,
          ...publicKeyBytes,
        ]);
    }
  }

  /// Derive the self-authenticating principal raw bytes from a DER-encoded
  /// public key. This is SHA-224(der) || 0x02.
  static Uint8List principalFromDer(Uint8List derPublicKey) {
    final List<int> digest = _sha224(derPublicKey);
    return Uint8List.fromList(<int>[...digest, 0x02]);
  }

  /// Compute the self-authenticating principal bytes directly from raw
  /// algorithm+publicKey.
  static Uint8List principalFromPublicKey(
    KeyAlgorithm algorithm,
    Uint8List publicKeyBytes,
  ) {
    final Uint8List der = derEncodePublicKey(algorithm, publicKeyBytes);
    return principalFromDer(der);
  }

  /// Format principal bytes to textual form used on the IC.
  /// Algorithm:
  /// 1) prefix with 4-byte CRC32 (big-endian)
  /// 2) base32 encode (lowercase, no padding)
  /// 3) insert dashes every 5 chars
  static String toText(Uint8List principalBytes) {
    final int checksum = _crc32(principalBytes);
    final Uint8List withCrc = Uint8List(principalBytes.length + 4);
    // Big-endian
    withCrc[0] = (checksum >> 24) & 0xff;
    withCrc[1] = (checksum >> 16) & 0xff;
    withCrc[2] = (checksum >> 8) & 0xff;
    withCrc[3] = checksum & 0xff;
    withCrc.setRange(4, withCrc.length, principalBytes);
    final String base32 = _base32Encode(withCrc);
    return _addDashes(base32);
  }

  /// Parse textual principal back to raw bytes and validate checksum.
  /// Throws [FormatException] if invalid.
  static Uint8List fromText(String text) {
    final String compact = text.replaceAll('-', '').trim().toLowerCase();
    final Uint8List decoded = _base32Decode(compact);
    if (decoded.length < 5) {
      throw const FormatException('Invalid principal: too short');
    }
    final Uint8List crcBytes = decoded.sublist(0, 4);
    final Uint8List body = decoded.sublist(4);
    final int expected = _crc32(body);
    final int actual =
        (crcBytes[0] << 24) |
        (crcBytes[1] << 16) |
        (crcBytes[2] << 8) |
        crcBytes[3];
    if (expected != actual) {
      throw const FormatException('Invalid principal: checksum mismatch');
    }
    return body;
  }

  /// Convenience: derive textual principal from an [IdentityRecord].
  static String textFromRecord(IdentityRecord record) {
    final Uint8List publicKeyBytes = base64Decode(record.publicKey);
    final Uint8List principalBytes = principalFromPublicKey(
      record.algorithm,
      publicKeyBytes,
    );
    return toText(principalBytes);
  }

  // ---- Helpers ----

  static String _addDashes(String input) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      if (i > 0 && i % 5 == 0) {
        buffer.write('-');
      }
      buffer.write(input[i]);
    }
    return buffer.toString();
  }

  static const String _alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

  static String _base32Encode(Uint8List input) {
    int buffer = 0;
    int bitsLeft = 0;
    final StringBuffer out = StringBuffer();
    for (final int byte in input) {
      buffer = (buffer << 8) | (byte & 0xff);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        final int index = (buffer >> bitsLeft) & 0x1f;
        out.write(_alphabet[index]);
      }
    }
    if (bitsLeft > 0) {
      final int index = (buffer << (5 - bitsLeft)) & 0x1f;
      out.write(_alphabet[index]);
    }
    return out.toString();
  }

  static Uint8List _base32Decode(String input) {
    int buffer = 0;
    int bitsLeft = 0;
    final List<int> out = <int>[];
    for (final int codeUnit in input.codeUnits) {
      final int idx = _alphabet.indexOf(String.fromCharCode(codeUnit));
      if (idx < 0) {
        throw const FormatException('Invalid base32 character');
      }
      buffer = (buffer << 5) | idx;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        out.add((buffer >> bitsLeft) & 0xff);
      }
    }
    return Uint8List.fromList(out);
  }

  // CRC32 (IEEE 802.3), big-endian output
  static final List<int> _crcTable = _makeCrcTable();

  static List<int> _makeCrcTable() {
    const int polynomial = 0xEDB88320;
    final List<int> table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int j = 0; j < 8; j++) {
        if ((c & 1) != 0) {
          c = polynomial ^ (c >> 1);
        } else {
          c >>= 1;
        }
      }
      table[i] = c;
    }
    return table;
  }

  static int _crc32(Uint8List data) {
    int c = 0xFFFFFFFF;
    for (final int byte in data) {
      final int index = (c ^ byte) & 0xFF;
      c = _crcTable[index] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  // Minimal SHA-224 implementation via Dart crypto is not available here,
  // so we implement it by reusing SHA-256 with different IV and output.
  // To avoid extra dependencies, include a compact SHA-224 implementation.
  // Based on FIPS 180-4, cut-down from SHA-256.
  static Uint8List _sha224(Uint8List input) {
    // Constants (first 32 bits of fractional parts of the cube roots of the first 64 primes)
    const List<int> k = <int>[
      0x428a2f98,
      0x71374491,
      0xb5c0fbcf,
      0xe9b5dba5,
      0x3956c25b,
      0x59f111f1,
      0x923f82a4,
      0xab1c5ed5,
      0xd807aa98,
      0x12835b01,
      0x243185be,
      0x550c7dc3,
      0x72be5d74,
      0x80deb1fe,
      0x9bdc06a7,
      0xc19bf174,
      0xe49b69c1,
      0xefbe4786,
      0x0fc19dc6,
      0x240ca1cc,
      0x2de92c6f,
      0x4a7484aa,
      0x5cb0a9dc,
      0x76f988da,
      0x983e5152,
      0xa831c66d,
      0xb00327c8,
      0xbf597fc7,
      0xc6e00bf3,
      0xd5a79147,
      0x06ca6351,
      0x14292967,
      0x27b70a85,
      0x2e1b2138,
      0x4d2c6dfc,
      0x53380d13,
      0x650a7354,
      0x766a0abb,
      0x81c2c92e,
      0x92722c85,
      0xa2bfe8a1,
      0xa81a664b,
      0xc24b8b70,
      0xc76c51a3,
      0xd192e819,
      0xd6990624,
      0xf40e3585,
      0x106aa070,
      0x19a4c116,
      0x1e376c08,
      0x2748774c,
      0x34b0bcb5,
      0x391c0cb3,
      0x4ed8aa4a,
      0x5b9cca4f,
      0x682e6ff3,
      0x748f82ee,
      0x78a5636f,
      0x84c87814,
      0x8cc70208,
      0x90befffa,
      0xa4506ceb,
      0xbef9a3f7,
      0xc67178f2,
    ];

    int rotateRight(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;
    int choose(int x, int y, int z) => (x & y) ^ (~x & z);
    int majority(int x, int y, int z) => (x & y) ^ (x & z) ^ (y & z);
    int bigSigma0(int x) =>
        rotateRight(x, 2) ^ rotateRight(x, 13) ^ rotateRight(x, 22);
    int bigSigma1(int x) =>
        rotateRight(x, 6) ^ rotateRight(x, 11) ^ rotateRight(x, 25);
    int smallSigma0(int x) =>
        rotateRight(x, 7) ^ rotateRight(x, 18) ^ (x >>> 3);
    int smallSigma1(int x) =>
        rotateRight(x, 17) ^ rotateRight(x, 19) ^ (x >>> 10);

    // SHA-224 initial hash values
    int h0 = 0xc1059ed8;
    int h1 = 0x367cd507;
    int h2 = 0x3070dd17;
    int h3 = 0xf70e5939;
    int h4 = 0xffc00b31;
    int h5 = 0x68581511;
    int h6 = 0x64f98fa7;
    int h7 = 0xbefa4fa4;

    // Pre-processing: padding
    final int bitLen = input.length * 8;
    final List<int> withOne = List<int>.from(input)..add(0x80);
    while ((withOne.length % 64) != 56) {
      withOne.add(0x00);
    }
    final ByteData lenBytes = ByteData(8);
    lenBytes.setUint32(0, (bitLen >> 32) & 0xFFFFFFFF, Endian.big);
    lenBytes.setUint32(4, bitLen & 0xFFFFFFFF, Endian.big);
    withOne.addAll(lenBytes.buffer.asUint8List());

    // Process the message in successive 512-bit chunks:
    for (int i = 0; i < withOne.length; i += 64) {
      final Uint8List chunk = Uint8List.fromList(withOne.sublist(i, i + 64));
      final List<int> w = List<int>.filled(64, 0);
      for (int t = 0; t < 16; t++) {
        final int j = t * 4;
        w[t] =
            (chunk[j] << 24) |
            (chunk[j + 1] << 16) |
            (chunk[j + 2] << 8) |
            (chunk[j + 3]);
      }
      for (int t = 16; t < 64; t++) {
        w[t] =
            (w[t - 16] +
                smallSigma0(w[t - 15]) +
                w[t - 7] +
                smallSigma1(w[t - 2])) &
            0xFFFFFFFF;
      }

      int a = h0;
      int b = h1;
      int c = h2;
      int d = h3;
      int e = h4;
      int f = h5;
      int g = h6;
      int h = h7;

      for (int t = 0; t < 64; t++) {
        final int t1 =
            (h + bigSigma1(e) + choose(e, f, g) + k[t] + w[t]) & 0xFFFFFFFF;
        final int t2 = (bigSigma0(a) + majority(a, b, c)) & 0xFFFFFFFF;
        h = g;
        g = f;
        f = e;
        e = (d + t1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & 0xFFFFFFFF;
      }

      h0 = (h0 + a) & 0xFFFFFFFF;
      h1 = (h1 + b) & 0xFFFFFFFF;
      h2 = (h2 + c) & 0xFFFFFFFF;
      h3 = (h3 + d) & 0xFFFFFFFF;
      h4 = (h4 + e) & 0xFFFFFFFF;
      h5 = (h5 + f) & 0xFFFFFFFF;
      h6 = (h6 + g) & 0xFFFFFFFF;
      h7 = (h7 + h) & 0xFFFFFFFF;
    }

    final Uint8List out = Uint8List(28);
    void writeBe(int value, int offset) {
      out[offset] = (value >> 24) & 0xff;
      out[offset + 1] = (value >> 16) & 0xff;
      out[offset + 2] = (value >> 8) & 0xff;
      out[offset + 3] = value & 0xff;
    }

    writeBe(h0, 0);
    writeBe(h1, 4);
    writeBe(h2, 8);
    writeBe(h3, 12);
    writeBe(h4, 16);
    writeBe(h5, 20);
    writeBe(h6, 24);
    return out;
  }
}
