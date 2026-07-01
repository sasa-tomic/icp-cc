import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'test_keypair_factory.dart';

void main() {
  group('TestKeypairFactory', () {
    test('generates consistent keypair from same seed', () async {
      final keypair1 = await TestKeypairFactory.fromSeed(42);
      final keypair2 = await TestKeypairFactory.fromSeed(42);

      expect(keypair1.publicKey, equals(keypair2.publicKey));
      expect(keypair1.privateKey, equals(keypair2.privateKey));
      expect(keypair1.mnemonic, equals(keypair2.mnemonic));
    });

    test('generates different keypairs from different seeds', () async {
      final keypair1 = await TestKeypairFactory.fromSeed(42);
      final keypair2 = await TestKeypairFactory.fromSeed(123);

      expect(keypair1.publicKey, isNot(equals(keypair2.publicKey)));
      expect(keypair1.privateKey, isNot(equals(keypair2.privateKey)));
      expect(keypair1.mnemonic, isNot(equals(keypair2.mnemonic)));
    });

    test('caches keypairs for performance', () async {
      final keypair1 = await TestKeypairFactory.fromSeed(42);
      final keypair2 = await TestKeypairFactory.fromSeed(42);

      // Should return the exact same instance (cached)
      expect(identical(keypair1, keypair2), isTrue);
    });

    test('supports different algorithms', () async {
      final ed25519Keypair = await TestKeypairFactory.fromSeed(42,
          algorithm: KeyAlgorithm.ed25519);
      final secp256k1Keypair = await TestKeypairFactory.fromSeed(42,
          algorithm: KeyAlgorithm.secp256k1);

      expect(ed25519Keypair.algorithm, equals(KeyAlgorithm.ed25519));
      expect(secp256k1Keypair.algorithm, equals(KeyAlgorithm.secp256k1));
      expect(
          ed25519Keypair.publicKey, isNot(equals(secp256k1Keypair.publicKey)));
    });

    test('generates valid BIP39 mnemonics', () async {
      final keypair = await TestKeypairFactory.fromSeed(999);

      // Mnemonic should be 24 words
      final words = keypair.mnemonic.split(' ');
      expect(words.length, equals(24));

      // Each word should be non-empty
      for (final word in words) {
        expect(word.isNotEmpty, isTrue);
      }
    });

    test('default getEd25519Keypair returns consistent keypair', () async {
      final keypair1 = await TestKeypairFactory.getEd25519Keypair();
      final keypair2 = await TestKeypairFactory.getEd25519Keypair();

      expect(identical(keypair1, keypair2), isTrue);
      expect(keypair1.algorithm, equals(KeyAlgorithm.ed25519));
    });

    test('clearCache removes all cached keypairs', () async {
      // Create some keypairs
      await TestKeypairFactory.fromSeed(1);
      await TestKeypairFactory.fromSeed(2);
      await TestKeypairFactory.getEd25519Keypair();

      // Clear cache
      TestKeypairFactory.clearCache();

      // Next calls should create new instances
      final keypair1a = await TestKeypairFactory.fromSeed(1);
      final keypair1b = await TestKeypairFactory.fromSeed(1);

      // These should be the same after clearing and re-caching
      expect(identical(keypair1a, keypair1b), isTrue);
    });
  });
}
