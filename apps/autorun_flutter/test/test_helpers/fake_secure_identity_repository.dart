import 'package:icp_autorun/models/identity_record.dart';
import 'package:icp_autorun/services/secure_identity_repository.dart';

/// Fake implementation of SecureIdentityRepository for testing
/// Stores identities in memory and provides full control for test scenarios
class FakeSecureIdentityRepository implements SecureIdentityRepository {
  FakeSecureIdentityRepository(List<IdentityRecord> initialIdentities)
      : _identities = List.of(initialIdentities);

  List<IdentityRecord> _identities;

  /// Public getter for testing purposes to verify persistence
  List<IdentityRecord> get identities => List<IdentityRecord>.from(_identities);

  @override
  Future<List<IdentityRecord>> loadIdentities() async {
    return List<IdentityRecord>.from(_identities);
  }

  @override
  Future<void> persistIdentities(List<IdentityRecord> identities) async {
    _identities = List<IdentityRecord>.from(identities);
  }

  @override
  Future<void> deleteIdentitySecureData(String identityId) async {
    _identities.removeWhere((identity) => identity.id == identityId);
  }

  @override
  Future<void> deleteAllSecureData() async {
    _identities = <IdentityRecord>[];
  }

  @override
  Future<String?> getPrivateKey(String identityId) async {
    final identity = _identities.firstWhere(
      (identity) => identity.id == identityId,
      orElse: () => throw StateError('Identity not found: $identityId'),
    );
    return identity.privateKey;
  }
}
