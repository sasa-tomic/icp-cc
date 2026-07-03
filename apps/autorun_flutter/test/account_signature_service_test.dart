import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/services/account_signature_service.dart';
import 'package:icp_autorun/utils/base64_utils.dart';

import 'shared/test_keypair_factory.dart';

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

  test('createAddPublicKeyRequest signs and embeds the new keypair', () async {
    final signingKeypair = await TestKeypairFactory.getEd25519Keypair();
    final newKeypair = await TestKeypairFactory.fromSeed(5);

    final request = await AccountSignatureService.createAddPublicKeyRequest(
      signingKeypair: signingKeypair,
      username: 'alice',
      newKeypair: newKeypair,
    );

    // The new key's public key flows to the wire format unchanged.
    expect(request.newPublicKeyB64, newKeypair.publicKey);
    expect(request.newKeypair, same(newKeypair));
    expect(request.signingPublicKeyB64, signingKeypair.publicKey);
    expect(request.signature, isNotEmpty);
    expect(request.toCanonicalPayload()['newPublicKeyB64'], newKeypair.publicKey);
  });

  // Defense-in-depth: even though a real ProfileKeypair.publicKey is always
  // valid base64, the factory must still fail fast if handed a malformed
  // keypair (e.g. constructed by hand). This guards the wire boundary.
  test('createAddPublicKeyRequest fails fast for malformed keypair publicKey',
      () async {
    final signingKeypair = await TestKeypairFactory.getEd25519Keypair();
    final malformedKeypair = ProfileKeypair(
      id: 'malformed',
      label: 'malformed',
      algorithm: KeyAlgorithm.ed25519,
      publicKey: 'not-base64!',
      privateKey: 'dGhpcy1pcy1hLXByaXZhdGUta2V5', // valid base64, unused here
      mnemonic: 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
      createdAt: DateTime.utc(2024),
    );

    await expectLater(
      AccountSignatureService.createAddPublicKeyRequest(
        signingKeypair: signingKeypair,
        username: 'alice',
        newKeypair: malformedKeypair,
      ),
      throwsFormatException,
    );
  });
}
