import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/utils/keypair_generator.dart';
import 'package:icp_autorun/utils/principal.dart';
import 'test_vectors.dart';

void main() {
  const String mnemonic = kTestMnemonic;

  test('Ed25519 principal from Rust FFI matches expected', () async {
    final ProfileKeypair record = await KeypairGenerator.generate(
      algorithm: KeyAlgorithm.ed25519,
      mnemonic: mnemonic,
      label: 'Test',
      keypairCount: 0,
    );

    // Verify principal is stored (from Rust FFI)
    expect(record.principal, isNotNull);
    expect(record.principal, isNotEmpty);

    // Verify textFromRecord returns stored principal
    final String principal = PrincipalUtils.textFromRecord(record);
    expect(principal, record.principal);

    // Verify it matches expected test vector
    expect(principal, kEd25519PrincipalText);
  });

  test('secp256k1 principal from Rust FFI matches expected', () async {
    final ProfileKeypair record = await KeypairGenerator.generate(
      algorithm: KeyAlgorithm.secp256k1,
      mnemonic: mnemonic,
      label: 'Test',
      keypairCount: 0,
    );

    // Verify principal is stored (from Rust FFI)
    expect(record.principal, isNotNull);
    expect(record.principal, isNotEmpty);

    // Verify textFromRecord returns stored principal
    final String principal = PrincipalUtils.textFromRecord(record);
    expect(principal, record.principal);

    // Verify it matches expected test vector
    expect(principal, kSecp256k1PrincipalText);
  });

  test('textFromRecord throws for keypair without stored principal', () {
    final record = ProfileKeypair(
      id: 'test-id',
      label: 'Test',
      algorithm: KeyAlgorithm.ed25519,
      publicKey: 'dGVzdA==', // dummy
      privateKey: 'dGVzdA==', // dummy
      mnemonic: 'test mnemonic',
      createdAt: DateTime.now(),
      principal: null, // Missing principal
    );

    expect(
      () => PrincipalUtils.textFromRecord(record),
      throwsStateError,
    );
  });
}
