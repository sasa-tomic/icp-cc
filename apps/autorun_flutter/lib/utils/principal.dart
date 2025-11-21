import '../models/profile_keypair.dart';

/// Utilities for working with Internet Computer principals.
class PrincipalUtils {
  const PrincipalUtils._();

  /// Get textual principal from an [ProfileKeypair].
  /// Requires stored principal (computed by Rust FFI during generation).
  static String textFromRecord(ProfileKeypair record) {
    if (record.principal == null || record.principal!.isEmpty) {
      throw StateError(
        'Keypair ${record.id} missing principal. '
        'Re-generate keypair to fix. Legacy keypairs without stored principal are not supported.',
      );
    }
    return record.principal!;
  }
}
