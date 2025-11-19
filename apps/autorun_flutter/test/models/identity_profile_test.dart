import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/identity_profile.dart';

void main() {
  group('IdentityProfile', () {
    test('creates profile with display name', () {
      final IdentityProfile profile = IdentityProfile(
        id: 'profile-1',
        principal: 'aaaaa-aa',
        displayName: 'ICP Builder',
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
      );
      expect(profile.displayName, equals('ICP Builder'));
      expect(profile.principal, equals('aaaaa-aa'));
    });

    test('parses API payloads with nested profile key', () {
      final IdentityProfile profile = IdentityProfile.fromJson({
        'profile': {
          'id': 'profile-1',
          'principal': 'aaaaa-aa',
          'displayName': 'ICP Builder',
          'metadata': {'team': 'core'},
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-02T00:00:00Z',
        },
      });

      expect(profile.displayName, equals('ICP Builder'));
      expect(profile.metadata['team'], equals('core'));
      expect(profile.createdAt.year, equals(2024));
    });

    test('copyWith updates display name', () {
      final original = IdentityProfile(
        id: 'profile-1',
        principal: 'aaaaa-aa',
        displayName: 'Original Name',
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
      );

      final updated = original.copyWith(displayName: 'New Name');
      expect(updated.displayName, equals('New Name'));
      expect(updated.id, equals(original.id));
      expect(updated.principal, equals(original.principal));
    });
  });
}
