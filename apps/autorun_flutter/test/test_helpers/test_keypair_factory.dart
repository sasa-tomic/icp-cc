import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/utils/keypair_generator.dart';
import 'package:bip39/bip39.dart' as bip39;

/// Factory for creating test keypairs with deterministic keys
/// Supports both fixed mnemonics and seed-based generation for tests
class TestKeypairFactory {
  // Fixed test mnemonics for reproducible test keypairs (valid BIP39 24-word phrases)
  static const String _ed25519TestMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';

  static const String _secp256k1TestMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  static ProfileKeypair? _cachedEd25519Keypair;
  static ProfileKeypair? _cachedSecp256k1Keypair;
  static final Map<int, ProfileKeypair> _seedBasedKeypairCache = {};

  /// Get or create a test Ed25519 keypair (cached for performance)
  static Future<ProfileKeypair> getEd25519Keypair() async {
    _cachedEd25519Keypair ??= await KeypairGenerator.generate(
      algorithm: KeyAlgorithm.ed25519,
      label: 'Test Ed25519 Keypair',
      mnemonic: _ed25519TestMnemonic,
    );
    return _cachedEd25519Keypair!;
  }

  /// Get or create a test secp256k1 keypair (cached for performance)
  static Future<ProfileKeypair> getSecp256k1Keypair() async {
    _cachedSecp256k1Keypair ??= await KeypairGenerator.generate(
      algorithm: KeyAlgorithm.secp256k1,
      label: 'Test secp256k1 Keypair',
      mnemonic: _secp256k1TestMnemonic,
    );
    return _cachedSecp256k1Keypair!;
  }

  /// Get keypair by algorithm
  static Future<ProfileKeypair> getKeypair(KeyAlgorithm algorithm) async {
    switch (algorithm) {
      case KeyAlgorithm.ed25519:
        return getEd25519Keypair();
      case KeyAlgorithm.secp256k1:
        return getSecp256k1Keypair();
    }
  }

  /// Generate a deterministic test keypair from a seed
  /// The seed is used to create a reproducible BIP39 mnemonic
  /// Cached for performance with the same seed
  static Future<ProfileKeypair> fromSeed(
    int seed, {
    KeyAlgorithm algorithm = KeyAlgorithm.ed25519,
  }) async {
    final cacheKey = seed * 10 + (algorithm == KeyAlgorithm.ed25519 ? 0 : 1);

    if (_seedBasedKeypairCache.containsKey(cacheKey)) {
      return _seedBasedKeypairCache[cacheKey]!;
    }

    final mnemonic = _generateDeterministicMnemonic(seed);
    final keypair = await KeypairGenerator.generate(
      algorithm: algorithm,
      label: 'Test Keypair (seed: $seed)',
      mnemonic: mnemonic,
    );

    _seedBasedKeypairCache[cacheKey] = keypair;
    return keypair;
  }

  /// Generate a deterministic BIP39 mnemonic from a seed
  /// Uses a Linear Congruential Generator to create deterministic entropy
  static String _generateDeterministicMnemonic(int seed) {
    int currentSeed = seed.abs();

    // Generate 32 bytes of deterministic entropy using LCG
    // This ensures we always get a valid BIP39 mnemonic with proper checksum
    final entropyBytes = List<int>.generate(32, (i) {
      // Linear Congruential Generator: X(n+1) = (a * X(n) + c) mod m
      currentSeed = ((currentSeed * 1103515245) + 12345) & 0x7fffffff;
      return currentSeed % 256;
    });

    // Convert entropy bytes to hex string for entropyToMnemonic
    final entropyHex =
        entropyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return bip39.entropyToMnemonic(entropyHex);
  }

  /// Clear cached keypairs (for testing)
  static void clearCache() {
    _cachedEd25519Keypair = null;
    _cachedSecp256k1Keypair = null;
    _seedBasedKeypairCache.clear();
  }
}
