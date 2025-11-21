import '../models/profile_keypair.dart';
import '../rust/native_bridge.dart';

/// Utilities for working with Internet Computer principals.
class PrincipalUtils {
  const PrincipalUtils._();

  /// Get textual principal from a [ProfileKeypair].
  /// If principal is not stored, derives it from the public key via Rust FFI.
  static String textFromRecord(ProfileKeypair record) {
    if (record.principal != null && record.principal!.isNotEmpty) {
      return record.principal!;
    }

    // Derive principal from public key
    final alg = record.algorithm == KeyAlgorithm.ed25519 ? 0 : 1;
    final principal = const RustBridgeLoader().principalFromPublicKey(
      alg: alg,
      publicKeyB64: record.publicKey,
    );
    if (principal == null || principal.isEmpty) {
      throw StateError(
        'Failed to derive principal for keypair ${record.id}. '
        'Rust FFI unavailable or invalid public key.',
      );
    }
    return principal;
  }
}
