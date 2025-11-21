import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/utils/identity_generator.dart';
import 'test_vectors.dart';

void main() {
  const String mnemonic = kTestMnemonic;

  test('generates Ed25519 identity matching known vector', () async {
    final ProfileKeypair record = await KeypairGenerator.generate(
      algorithm: KeyAlgorithm.ed25519,
      mnemonic: mnemonic,
      label: 'Test',
      keypairCount: 0,
    );

    expect(record.privateKey, kEd25519PrivateKeyB64);
    expect(record.publicKey, kEd25519PublicKeyB64);
  });

  test('generates secp256k1 identity matching DFX reference', () async {
    final ProfileKeypair record = await KeypairGenerator.generate(
      algorithm: KeyAlgorithm.secp256k1,
      mnemonic: mnemonic,
      label: 'Test',
      keypairCount: 0,
    );

    expect(record.privateKey, kSecp256k1PrivateKeyB64);
    expect(record.publicKey, kSecp256k1PublicKeyB64);
  });
}
