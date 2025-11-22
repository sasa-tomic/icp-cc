import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/account_signature_service.dart';
import 'package:icp_autorun/utils/base64_utils.dart';

import 'test_helpers/test_keypair_factory.dart';

void main() {
  test('createRegisterAccountRequest uses base64 keys and signature', () async {
    final keypair = await TestKeypairFactory.getEd25519Keypair();

    final request = await AccountSignatureService.createRegisterAccountRequest(
      keypair: keypair,
      username: 'alice',
      displayName: 'Alice',
    );

    expect(request.publicKeyB64, keypair.publicKey);
    expect(request.signature, isNotEmpty);

    final signatureBytes =
        Base64Utils.requireBytes(request.signature, fieldName: 'signature');
    expect(signatureBytes, isNotEmpty);

    final payload = request.toCanonicalPayload();
    expect(payload['publicKeyB64'], keypair.publicKey);
    expect(payload['username'], 'alice');
  });

  test('createAddPublicKeyRequest fails fast for invalid base64', () async {
    final signingKeypair = await TestKeypairFactory.getEd25519Keypair();

    await expectLater(
      AccountSignatureService.createAddPublicKeyRequest(
        signingKeypair: signingKeypair,
        username: 'alice',
        newPublicKeyB64: 'not-base64',
      ),
      throwsFormatException,
    );
  });
}
