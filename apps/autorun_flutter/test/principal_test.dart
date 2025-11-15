import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/utils/identity_generator.dart';
import 'package:icp_autorun/utils/principal.dart';

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';

  test('derives and formats Ed25519 principal', () async {
    final IdentityRecord record = await IdentityGenerator.generate(
      algorithm: KeyAlgorithm.ed25519,
      mnemonic: mnemonic,
      label: 'Test',
      identityCount: 0,
    );

    final String principal = PrincipalUtils.textFromRecord(record);
    expect(
      principal,
      'yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae',
    );

    final Uint8List publicKeyBytes = base64Decode(record.publicKey);
    final Uint8List principalBytes = PrincipalUtils.principalFromPublicKey(
      record.algorithm,
      publicKeyBytes,
    );
    expect(PrincipalUtils.fromText(principal), principalBytes);
  });

  test('derives and formats secp256k1 principal', () async {
    final IdentityRecord record = await IdentityGenerator.generate(
      algorithm: KeyAlgorithm.secp256k1,
      mnemonic: mnemonic,
      label: 'Test',
      identityCount: 0,
    );

    final String principal = PrincipalUtils.textFromRecord(record);
    expect(
      principal,
      'm7bn6-s5er4-xouui-ymkqf-azncv-qfche-3qghk-2fvpm-atfyh-ozg2w-iqe',
    );

    final Uint8List publicKeyBytes = base64Decode(record.publicKey);
    final Uint8List principalBytes = PrincipalUtils.principalFromPublicKey(
      record.algorithm,
      publicKeyBytes,
    );
    expect(PrincipalUtils.fromText(principal), principalBytes);
  });
}
