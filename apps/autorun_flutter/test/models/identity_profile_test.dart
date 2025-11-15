import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/identity_profile.dart';

void main() {
  group('IdentityProfile', () {
    test('computes completion state based on optional fields', () {
      final IdentityProfile incomplete = IdentityProfile(
        id: 'profile-1',
        principal: 'aaaaa-aa',
        displayName: 'Anon',
        createdAt: DateTime.utc(2024, 1, 1),
        updatedAt: DateTime.utc(2024, 1, 1),
      );
      expect(incomplete.isComplete, isFalse);

      final IdentityProfile complete = incomplete.copyWith(
        username: 'builder',
        bio: 'Building ICP apps',
      );
      expect(complete.isComplete, isTrue);
    });

    test('parses API payloads with nested profile key', () {
      final IdentityProfile profile = IdentityProfile.fromJson({
        'profile': {
          'id': 'profile-1',
          'principal': 'aaaaa-aa',
          'displayName': 'ICP Builder',
          'username': 'builder',
          'contactEmail': 'team@example.com',
          'contactTelegram': '@icp',
          'websiteUrl': 'https://internetcomputer.org',
          'bio': 'Building unstoppable tools',
          'metadata': {'team': 'core'},
          'createdAt': '2024-01-01T00:00:00Z',
          'updatedAt': '2024-01-02T00:00:00Z',
        },
      });

      expect(profile.displayName, equals('ICP Builder'));
      expect(profile.username, equals('builder'));
      expect(profile.contactEmail, equals('team@example.com'));
      expect(profile.metadata['team'], equals('core'));
      expect(profile.createdAt.year, equals(2024));
      expect(profile.isComplete, isTrue);
    });
  });
}
