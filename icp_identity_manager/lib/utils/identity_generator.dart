import 'dart:convert';

import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:convert/convert.dart' as convert;
import 'package:elliptic/elliptic.dart' as elliptic;
import 'package:uuid/uuid.dart';

import '../models/identity_record.dart';

class IdentityGenerator {
  const IdentityGenerator._();

  static const String _dfxDerivationPath = "m/44'/223'/0'/0/0";
  static final Uuid _uuid = const Uuid();

  static Future<IdentityRecord> generate({
    required KeyAlgorithm algorithm,
    String? label,
    String? mnemonic,
    int? identityCount,
  }) async {
    final String resolvedMnemonic = _resolveMnemonic(mnemonic);
    final String resolvedLabel = _resolveLabel(label, identityCount);
    final DateTime now = DateTime.now().toUtc();

    switch (algorithm) {
      case KeyAlgorithm.ed25519:
        final List<int> seedBytes = bip39
            .mnemonicToSeed(resolvedMnemonic)
            .sublist(0, 32);
        final SimpleKeyPair keyPair = await Ed25519().newKeyPairFromSeed(
          seedBytes,
        );
        final SimplePublicKey publicKey = await keyPair.extractPublicKey();
        final List<int> privateKeyBytes = await keyPair
            .extractPrivateKeyBytes();
        return IdentityRecord(
          id: _uuid.v4(),
          label: resolvedLabel,
          algorithm: KeyAlgorithm.ed25519,
          publicKey: base64Encode(publicKey.bytes),
          privateKey: base64Encode(privateKeyBytes),
          mnemonic: resolvedMnemonic,
          createdAt: now,
        );
      case KeyAlgorithm.secp256k1:
        final List<int> seed = bip39.mnemonicToSeed(resolvedMnemonic);
        final bip32.BIP32 root = bip32.BIP32.fromSeed(Uint8List.fromList(seed));
        final bip32.BIP32 node = root.derivePath(_dfxDerivationPath);
        final List<int>? privateKeyBytes = node.privateKey;
        if (privateKeyBytes == null) {
          throw StateError('Derived secp256k1 node is missing a private key.');
        }
        final elliptic.Curve curve = elliptic.getSecp256k1();
        final String compressedHex = convert.hex.encode(node.publicKey);
        final elliptic.PublicKey publicKey = elliptic.PublicKey.fromHex(
          curve,
          compressedHex,
        );
        final List<int> uncompressedBytes = convert.hex.decode(
          curve.publicKeyToHex(publicKey),
        );
        return IdentityRecord(
          id: _uuid.v4(),
          label: resolvedLabel,
          algorithm: KeyAlgorithm.secp256k1,
          publicKey: base64Encode(uncompressedBytes),
          privateKey: base64Encode(privateKeyBytes),
          mnemonic: resolvedMnemonic,
          createdAt: now,
        );
    }
  }

  static String _resolveLabel(String? label, int? identityCount) {
    if (label != null && label.trim().isNotEmpty) {
      return label.trim();
    }
    if (identityCount != null) {
      return 'Identity ${identityCount + 1}';
    }
    return 'New identity';
  }

  static String _resolveMnemonic(String? mnemonic) {
    if (mnemonic != null && mnemonic.trim().isNotEmpty) {
      return mnemonic.trim();
    }
    return bip39.generateMnemonic(strength: 256);
  }
}
