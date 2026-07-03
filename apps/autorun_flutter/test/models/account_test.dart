import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/account.dart';

import '../shared/test_keypair_factory.dart';

void main() {
  group('AccountPublicKey', () {
    group('fromJson', () {
      test('parses label when provided', () {
        final json = {
          'id': 'key-123',
          'publicKey': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890ABCD',
          'icPrincipal': 'abcde-abcde-abcde-abcde-cai',
          'isActive': true,
          'addedAt': '2024-01-15T10:30:00.000Z',
          'label': 'Laptop',
        };

        final key = AccountPublicKey.fromJson(json);

        expect(key.id, 'key-123');
        expect(key.publicKey, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890ABCD');
        expect(key.label, 'Laptop');
        expect(key.isActive, isTrue);
      });

      test('parses label from snake_case field', () {
        final json = {
          'id': 'key-123',
          'public_key': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890ABCD',
          'ic_principal': 'abcde-abcde-abcde-abcde-cai',
          'is_active': true,
          'added_at': '2024-01-15T10:30:00.000Z',
        };

        final key = AccountPublicKey.fromJson(json);

        expect(key.id, 'key-123');
        expect(key.publicKey, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890ABCD');
        expect(key.label, isNull);
      });

      test('handles null label for backward compatibility', () {
        final json = {
          'id': 'key-456',
          'publicKey': 'XYZ789',
          'icPrincipal': 'principal-123',
          'isActive': false,
          'addedAt': '2024-02-20T14:00:00.000Z',
          'disabledAt': '2024-03-01T09:00:00.000Z',
          'disabledByKeyId': 'key-789',
        };

        final key = AccountPublicKey.fromJson(json);

        expect(key.label, isNull);
        expect(key.isActive, isFalse);
        expect(key.disabledByKeyId, 'key-789');
      });
    });

    group('toJson', () {
      test('includes label when present', () {
        final key = AccountPublicKey(
          id: 'key-1',
          publicKey: 'ABCD1234',
          icPrincipal: 'principal-1',
          isActive: true,
          addedAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
          label: 'Phone',
        );

        final json = key.toJson();

        expect(json['label'], 'Phone');
        expect(json['id'], 'key-1');
        expect(json['publicKey'], 'ABCD1234');
        expect(json['isActive'], isTrue);
      });

      test('omits label when null', () {
        final key = AccountPublicKey(
          id: 'key-2',
          publicKey: 'WXYZ5678',
          icPrincipal: 'principal-2',
          isActive: true,
          addedAt: DateTime.parse('2024-02-20T14:00:00.000Z'),
        );

        final json = key.toJson();

        expect(json.containsKey('label'), isFalse);
      });
    });

    group('displayLabel', () {
      test('returns label when set', () {
        final key = AccountPublicKey(
          id: 'key-1',
          publicKey: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890ABCD',
          icPrincipal: 'principal-1',
          isActive: true,
          addedAt: DateTime.now(),
          label: 'Hardware Wallet',
        );

        expect(key.displayLabel, 'Hardware Wallet');
      });

      test('returns displayKey when label is null', () {
        final key = AccountPublicKey(
          id: 'key-1',
          publicKey: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890ABCD',
          icPrincipal: 'principal-1',
          isActive: true,
          addedAt: DateTime.now(),
        );

        expect(key.displayLabel, key.displayKey);
        expect(key.displayLabel, 'ABCDEF...ABCD');
      });
    });

    group('displayKey', () {
      test('truncates long public keys', () {
        final key = AccountPublicKey(
          id: 'key-1',
          publicKey: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890ABCD',
          icPrincipal: 'principal-1',
          isActive: true,
          addedAt: DateTime.now(),
        );

        expect(key.displayKey, 'ABCDEF...ABCD');
      });

      test('returns short public keys as-is', () {
        final key = AccountPublicKey(
          id: 'key-1',
          publicKey: 'SHORT123',
          icPrincipal: 'principal-1',
          isActive: true,
          addedAt: DateTime.now(),
        );

        expect(key.displayKey, 'SHORT123');
      });
    });

    group('copyWith', () {
      test('copies all fields including label', () {
        final key = AccountPublicKey(
          id: 'key-1',
          publicKey: 'ABCD1234',
          icPrincipal: 'principal-1',
          isActive: true,
          addedAt: DateTime.parse('2024-01-15T10:30:00.000Z'),
          label: 'Original Label',
        );

        final copied = key.copyWith(
          label: 'Updated Label',
          isActive: false,
        );

        expect(copied.id, 'key-1');
        expect(copied.publicKey, 'ABCD1234');
        expect(copied.label, 'Updated Label');
        expect(copied.isActive, isFalse);
      });

      test('preserves original values when not specified', () {
        final key = AccountPublicKey(
          id: 'key-1',
          publicKey: 'ABCD1234',
          icPrincipal: 'principal-1',
          isActive: true,
          addedAt: DateTime.now(),
          label: 'Original',
        );

        final copied = key.copyWith();

        expect(copied.label, 'Original');
        expect(copied.isActive, isTrue);
      });
    });

    group('round-trip serialization', () {
      test('fromJson/toJson preserves all fields with label', () {
        final json = {
          'id': 'key-789',
          'publicKey': 'ABCD12345678WXYZ',
          'icPrincipal': 'abcde-fghij-klmno-cai',
          'isActive': true,
          'addedAt': '2024-06-15T08:30:00.000Z',
          'label': 'YubiKey',
        };

        final key = AccountPublicKey.fromJson(json);
        final roundTrip = key.toJson();

        expect(roundTrip['id'], 'key-789');
        expect(roundTrip['publicKey'], 'ABCD12345678WXYZ');
        expect(roundTrip['icPrincipal'], 'abcde-fghij-klmno-cai');
        expect(roundTrip['isActive'], isTrue);
        expect(roundTrip['addedAt'], '2024-06-15T08:30:00.000Z');
        expect(roundTrip['label'], 'YubiKey');
      });

      test('fromJson/toJson preserves fields without label', () {
        final json = {
          'id': 'key-999',
          'publicKey': 'NOLABELKEY123',
          'icPrincipal': 'no-label-principal',
          'isActive': false,
          'addedAt': '2024-07-01T12:00:00.000Z',
          'disabledAt': '2024-08-01T12:00:00.000Z',
          'disabledByKeyId': 'key-001',
        };

        final key = AccountPublicKey.fromJson(json);
        final roundTrip = key.toJson();

        expect(roundTrip['id'], 'key-999');
        expect(roundTrip.containsKey('label'), isFalse);
        expect(roundTrip['disabledAt'], '2024-08-01T12:00:00.000Z');
        expect(roundTrip['disabledByKeyId'], 'key-001');
      });
    });
  });

  group('AddPublicKeyRequest', () {
    // The new key arrives as a real ProfileKeypair; the wire-format
    // newPublicKeyB64 is derived from newKeypair.publicKey (never raw input).
    group('toJson', () {
      test('includes label when provided and derives newPublicKeyB64', () async {
        final newKeypair = await TestKeypairFactory.fromSeed(101);
        final request = AddPublicKeyRequest(
          username: 'alice',
          newKeypair: newKeypair,
          signingPublicKeyB64: 'signingKey456',
          timestamp: 1700000100,
          nonce: 'uuid-1234',
          signature: 'sig789',
          label: 'Phone',
        );

        final json = request.toJson();

        expect(json['label'], 'Phone');
        expect(json['newPublicKeyB64'], newKeypair.publicKey);
        expect(json['nonce'], 'uuid-1234');
      });

      test('omits label when null', () async {
        final newKeypair = await TestKeypairFactory.fromSeed(102);
        final request = AddPublicKeyRequest(
          username: 'bob',
          newKeypair: newKeypair,
          signingPublicKeyB64: 'signingKey888',
          timestamp: 1700000200,
          nonce: 'uuid-5678',
          signature: 'sig000',
        );

        final json = request.toJson();

        expect(json.containsKey('label'), isFalse);
      });
    });

    group('toCanonicalPayload', () {
      test('includes label in canonical payload when provided', () async {
        final newKeypair = await TestKeypairFactory.fromSeed(103);
        final request = AddPublicKeyRequest(
          username: 'alice',
          newKeypair: newKeypair,
          signingPublicKeyB64: 'signingKey456',
          timestamp: 1700000100,
          nonce: 'uuid-1234',
          signature: 'sig789',
          label: 'Hardware Wallet',
        );

        final payload = request.toCanonicalPayload();

        expect(payload['label'], 'Hardware Wallet');
        expect(payload['action'], 'add_key');
        expect(payload['username'], 'alice');
        expect(payload['newPublicKeyB64'], newKeypair.publicKey);
      });

      test('omits label from canonical payload when null', () async {
        final newKeypair = await TestKeypairFactory.fromSeed(104);
        final request = AddPublicKeyRequest(
          username: 'bob',
          newKeypair: newKeypair,
          signingPublicKeyB64: 'signingKey888',
          timestamp: 1700000200,
          nonce: 'uuid-5678',
          signature: 'sig000',
        );

        final payload = request.toCanonicalPayload();

        expect(payload.containsKey('label'), isFalse);
        expect(payload['action'], 'add_key');
      });
    });
  });

  group('Account', () {
    test('parses public keys with labels', () {
      final json = {
        'id': 'account-1',
        'username': 'alice',
        'displayName': 'Alice Smith',
        'publicKeys': [
          {
            'id': 'key-1',
            'publicKey': 'ABCD1234',
            'icPrincipal': 'principal-1',
            'isActive': true,
            'addedAt': '2024-01-01T00:00:00.000Z',
            'label': 'Laptop',
          },
          {
            'id': 'key-2',
            'publicKey': 'WXYZ5678',
            'icPrincipal': 'principal-2',
            'isActive': true,
            'addedAt': '2024-02-01T00:00:00.000Z',
          },
        ],
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-02-01T00:00:00.000Z',
      };

      final account = Account.fromJson(json);

      expect(account.publicKeys, hasLength(2));
      expect(account.publicKeys[0].label, 'Laptop');
      expect(account.publicKeys[1].label, isNull);
    });
  });
}
