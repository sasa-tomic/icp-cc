import 'package:flutter_test/flutter_test.dart';

import 'package:icp_identity_manager/models/identity_record.dart';
import 'package:icp_identity_manager/utils/identity_generator.dart';

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';

  test('generates Ed25519 identity matching known vector', () async {
    final IdentityRecord record = await IdentityGenerator.generate(
      algorithm: KeyAlgorithm.ed25519,
      mnemonic: mnemonic,
      label: 'Test',
      identityCount: 0,
    );

    expect(record.privateKey, 'QIsoXBI4NgBPS4hCyJMkwfATgkUMDUOa80W6f8Saz3A=');
    expect(record.publicKey, 'HeNS5EzTM2clk/IzSnMOGAqvKQ3omqFtSA3llONOKWE=');
  });

  test('generates secp256k1 identity matching DFX reference', () async {
    final IdentityRecord record = await IdentityGenerator.generate(
      algorithm: KeyAlgorithm.secp256k1,
      mnemonic: mnemonic,
      label: 'Test',
      identityCount: 0,
    );

    expect(record.privateKey, 'Yb+9dY8vXeoLiLMSqhpHbE4MhT2HkGRk0Ai8NkBcD/I=');
    expect(
      record.publicKey,
      'BBz+IZWfHzq8STHpP6u3hU/DOJS6Fy5m3ewbQautk0Vd3u79WEhh0/0gvh886bxxFK9et89Fi2sBc4LDysmVe4g=',
    );
  });
}
