import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/utils/identity_generator.dart';
import 'package:bip39/bip39.dart' as bip39;

/// Factory for creating test identities with deterministic keys
/// Supports both fixed mnemonics and seed-based generation for tests
class TestIdentityFactory {
  // Fixed test mnemonics for reproducible test identities (valid BIP39 24-word phrases)
  static const String _ed25519TestMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';

  static const String _secp256k1TestMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  static ProfileKeypair? _cachedEd25519Identity;
  static ProfileKeypair? _cachedSecp256k1Identity;
  static final Map<int, ProfileKeypair> _seedBasedIdentityCache = {};

  /// Get or create a test Ed25519 identity (cached for performance)
  static Future<ProfileKeypair> getEd25519Identity() async {
    _cachedEd25519Identity ??= await IdentityGenerator.generate(
      algorithm: KeyAlgorithm.ed25519,
      label: 'Test Ed25519 Identity',
      mnemonic: _ed25519TestMnemonic,
    );
    return _cachedEd25519Identity!;
  }

  /// Get or create a test secp256k1 identity (cached for performance)
  static Future<ProfileKeypair> getSecp256k1Identity() async {
    _cachedSecp256k1Identity ??= await IdentityGenerator.generate(
      algorithm: KeyAlgorithm.secp256k1,
      label: 'Test secp256k1 Identity',
      mnemonic: _secp256k1TestMnemonic,
    );
    return _cachedSecp256k1Identity!;
  }

  /// Get identity by algorithm
  static Future<ProfileKeypair> getIdentity(KeyAlgorithm algorithm) async {
    switch (algorithm) {
      case KeyAlgorithm.ed25519:
        return getEd25519Identity();
      case KeyAlgorithm.secp256k1:
        return getSecp256k1Identity();
    }
  }

  /// Generate a deterministic test identity from a seed
  /// The seed is used to create a reproducible BIP39 mnemonic
  /// Cached for performance with the same seed
  static Future<ProfileKeypair> fromSeed(
    int seed, {
    KeyAlgorithm algorithm = KeyAlgorithm.ed25519,
  }) async {
    final cacheKey = seed * 10 + (algorithm == KeyAlgorithm.ed25519 ? 0 : 1);

    if (_seedBasedIdentityCache.containsKey(cacheKey)) {
      return _seedBasedIdentityCache[cacheKey]!;
    }

    final mnemonic = _generateDeterministicMnemonic(seed);
    final identity = await IdentityGenerator.generate(
      algorithm: algorithm,
      label: 'Test Identity (seed: $seed)',
      mnemonic: mnemonic,
    );

    _seedBasedIdentityCache[cacheKey] = identity;
    return identity;
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

  /// Clear cached identities (for testing)
  static void clearCache() {
    _cachedEd25519Identity = null;
    _cachedSecp256k1Identity = null;
    _seedBasedIdentityCache.clear();
  }
}
