import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/utils/identity_generator.dart';

/// Factory for creating test identities with deterministic keys
/// Uses fixed mnemonics for reproducibility in tests
class TestIdentityFactory {
  // Fixed test mnemonics for reproducible test identities (valid BIP39 24-word phrases)
  static const String _ed25519TestMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';

  static const String _secp256k1TestMnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  static IdentityRecord? _cachedEd25519Identity;
  static IdentityRecord? _cachedSecp256k1Identity;

  /// Get or create a test Ed25519 identity (cached for performance)
  static Future<IdentityRecord> getEd25519Identity() async {
    _cachedEd25519Identity ??= await IdentityGenerator.generate(
      algorithm: KeyAlgorithm.ed25519,
      label: 'Test Ed25519 Identity',
      mnemonic: _ed25519TestMnemonic,
    );
    return _cachedEd25519Identity!;
  }

  /// Get or create a test secp256k1 identity (cached for performance)
  static Future<IdentityRecord> getSecp256k1Identity() async {
    _cachedSecp256k1Identity ??= await IdentityGenerator.generate(
      algorithm: KeyAlgorithm.secp256k1,
      label: 'Test secp256k1 Identity',
      mnemonic: _secp256k1TestMnemonic,
    );
    return _cachedSecp256k1Identity!;
  }

  /// Get identity by algorithm
  static Future<IdentityRecord> getIdentity(KeyAlgorithm algorithm) async {
    switch (algorithm) {
      case KeyAlgorithm.ed25519:
        return getEd25519Identity();
      case KeyAlgorithm.secp256k1:
        return getSecp256k1Identity();
    }
  }

  /// Clear cached identities (for testing)
  static void clearCache() {
    _cachedEd25519Identity = null;
    _cachedSecp256k1Identity = null;
  }
}
