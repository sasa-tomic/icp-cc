import '../models/profile.dart';
import '../models/profile_keypair.dart';

/// Thrown when a keypair is found to belong to more than one profile.
///
/// Architecture invariant: "A keypair belongs to exactly ONE profile."
/// The backend enforces this via a `public_key UNIQUE` constraint; this
/// exception is the client-side mirror of that invariant, guarding the
/// [ProfileRepository] boundary so corrupt state can never be persisted or
/// silently loaded. Flat secure-storage keys (`keypair_private_key_<id>`) are
/// NOT scoped by profile, so a duplicate id across profiles would mean
/// deleting the keypair in one profile silently wipes the other profile's
/// secret — permanent key loss. We fail LOUD instead.
class KeypairOwnershipViolation implements Exception {
  KeypairOwnershipViolation({
    required this.field,
    required this.value,
    required this.profileIds,
  });

  /// The keypair field that collided: `'id'` or `'publicKey'`.
  final String field;

  /// The colliding value (the keypair id, or the base64 publicKey).
  final String value;

  /// The ids of the profiles that both claim this keypair field.
  final List<String> profileIds;

  @override
  String toString() =>
      'KeypairOwnershipViolation: keypair $field "$value" is claimed by more '
      'than one profile (${profileIds.join(', ')}). Invariant violated: a '
      'keypair must belong to exactly ONE profile.';
}

/// Asserts the keypair-ownership invariant across [profiles]: every keypair
/// `id` AND every `publicKey` must be globally unique.
///
/// This is the client-side mirror of the backend `public_key UNIQUE`
/// constraint. It defends against a keypair being attached to two profiles,
/// which (because secure storage is keyed only by `<id>`, not by profile)
/// would cause deleting it in one profile to silently destroy the other
/// profile's secret. On violation we throw [KeypairOwnershipViolation] — we
/// never silently dedupe or delete data.
///
/// Throws [KeypairOwnershipViolation] on the first collision. O(n) over the
/// total number of keypairs.
void assertUniqueKeypairOwnership(List<Profile> profiles) {
  // keypairId  -> profileId that first claimed it
  final Map<String, String> idOwner = <String, String>{};
  // publicKey  -> profileId that first claimed it
  final Map<String, String> publicKeyOwner = <String, String>{};

  for (final Profile profile in profiles) {
    for (final ProfileKeypair keypair in profile.keypairs) {
      final String? existingIdOwner = idOwner[keypair.id];
      if (existingIdOwner != null) {
        throw KeypairOwnershipViolation(
          field: 'id',
          value: keypair.id,
          profileIds: <String>[existingIdOwner, profile.id],
        );
      }
      idOwner[keypair.id] = profile.id;

      final String? existingPubOwner = publicKeyOwner[keypair.publicKey];
      if (existingPubOwner != null) {
        throw KeypairOwnershipViolation(
          field: 'publicKey',
          value: keypair.publicKey,
          profileIds: <String>[existingPubOwner, profile.id],
        );
      }
      publicKeyOwner[keypair.publicKey] = profile.id;
    }
  }
}
