import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'test_identity_factory.dart';

void main() {
  group('TestIdentityFactory', () {
    test('generates consistent identity from same seed', () async {
      final identity1 = await TestIdentityFactory.fromSeed(42);
      final identity2 = await TestIdentityFactory.fromSeed(42);

      expect(identity1.publicKey, equals(identity2.publicKey));
      expect(identity1.privateKey, equals(identity2.privateKey));
      expect(identity1.mnemonic, equals(identity2.mnemonic));
    });

    test('generates different identities from different seeds', () async {
      final identity1 = await TestIdentityFactory.fromSeed(42);
      final identity2 = await TestIdentityFactory.fromSeed(123);

      expect(identity1.publicKey, isNot(equals(identity2.publicKey)));
      expect(identity1.privateKey, isNot(equals(identity2.privateKey)));
      expect(identity1.mnemonic, isNot(equals(identity2.mnemonic)));
    });

    test('caches identities for performance', () async {
      final identity1 = await TestIdentityFactory.fromSeed(42);
      final identity2 = await TestIdentityFactory.fromSeed(42);

      // Should return the exact same instance (cached)
      expect(identical(identity1, identity2), isTrue);
    });

    test('supports different algorithms', () async {
      final ed25519Identity = await TestIdentityFactory.fromSeed(42,
          algorithm: KeyAlgorithm.ed25519);
      final secp256k1Identity = await TestIdentityFactory.fromSeed(42,
          algorithm: KeyAlgorithm.secp256k1);

      expect(ed25519Identity.algorithm, equals(KeyAlgorithm.ed25519));
      expect(secp256k1Identity.algorithm, equals(KeyAlgorithm.secp256k1));
      expect(ed25519Identity.publicKey,
          isNot(equals(secp256k1Identity.publicKey)));
    });

    test('generates valid BIP39 mnemonics', () async {
      final identity = await TestIdentityFactory.fromSeed(999);

      // Mnemonic should be 24 words
      final words = identity.mnemonic.split(' ');
      expect(words.length, equals(24));

      // Each word should be non-empty
      for (final word in words) {
        expect(word.isNotEmpty, isTrue);
      }
    });

    test('default getEd25519Identity returns consistent identity', () async {
      final identity1 = await TestIdentityFactory.getEd25519Identity();
      final identity2 = await TestIdentityFactory.getEd25519Identity();

      expect(identical(identity1, identity2), isTrue);
      expect(identity1.algorithm, equals(KeyAlgorithm.ed25519));
    });

    test('clearCache removes all cached identities', () async {
      // Create some identities
      await TestIdentityFactory.fromSeed(1);
      await TestIdentityFactory.fromSeed(2);
      await TestIdentityFactory.getEd25519Identity();

      // Clear cache
      TestIdentityFactory.clearCache();

      // Next calls should create new instances
      final identity1a = await TestIdentityFactory.fromSeed(1);
      final identity1b = await TestIdentityFactory.fromSeed(1);

      // These should be the same after clearing and re-caching
      expect(identical(identity1a, identity1b), isTrue);
    });
  });
}
