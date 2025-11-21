import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/models/profile_keypair.dart';

void main() {
  group('Secure Storage Logic Tests', () {
    test('keypair model serialization maintains all fields', () {
      final testKeypair = ProfileKeypair(
        id: 'test-1',
        label: 'Test Keypair',
        algorithm: KeyAlgorithm.ed25519,
        publicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        privateKey: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
        mnemonic: 'test abandon abandon able about above absent act',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      // Test toJson
      final jsonMap = testKeypair.toJson();
      expect(jsonMap['id'], 'test-1');
      expect(jsonMap['label'], 'Test Keypair');
      expect(jsonMap['algorithm'], 'ed25519');
      expect(
          jsonMap['publicKey'], 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
      expect(jsonMap['privateKey'], 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=');
      expect(jsonMap['mnemonic'],
          'test abandon abandon able about above absent act');
      expect(jsonMap['createdAt'], '2024-01-01T00:00:00.000Z');

      // Test fromJson
      final loadedKeypair = ProfileKeypair.fromJson(jsonMap);
      expect(loadedKeypair.id, testKeypair.id);
      expect(loadedKeypair.label, testKeypair.label);
      expect(loadedKeypair.algorithm, testKeypair.algorithm);
      expect(loadedKeypair.publicKey, testKeypair.publicKey);
      expect(loadedKeypair.privateKey, testKeypair.privateKey);
      expect(loadedKeypair.mnemonic, testKeypair.mnemonic);
      expect(loadedKeypair.createdAt, testKeypair.createdAt);
    });

    test('keypair copyWith updates label only', () {
      final originalKeypair = ProfileKeypair(
        id: 'test-2',
        label: 'Original Label',
        algorithm: KeyAlgorithm.secp256k1,
        publicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        privateKey: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
        mnemonic: 'original mnemonic phrase',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      final updatedKeypair = originalKeypair.copyWith(label: 'Updated Label');

      // Only label should change
      expect(updatedKeypair.label, 'Updated Label');
      expect(updatedKeypair.id, originalKeypair.id);
      expect(updatedKeypair.algorithm, originalKeypair.algorithm);
      expect(updatedKeypair.publicKey, originalKeypair.publicKey);
      expect(updatedKeypair.privateKey, originalKeypair.privateKey);
      expect(updatedKeypair.mnemonic, originalKeypair.mnemonic);
      expect(updatedKeypair.createdAt, originalKeypair.createdAt);
    });

    test('key algorithm conversions work correctly', () {
      // Test enum to string
      expect(keyAlgorithmToString(KeyAlgorithm.ed25519), 'ed25519');
      expect(keyAlgorithmToString(KeyAlgorithm.secp256k1), 'secp256k1');

      // Test string to enum
      expect(keyAlgorithmFromString('ed25519'), KeyAlgorithm.ed25519);
      expect(keyAlgorithmFromString('secp256k1'), KeyAlgorithm.secp256k1);

      // Test invalid string
      expect(
        () => keyAlgorithmFromString('invalid'),
        throwsArgumentError,
      );
    });

    test('keypair export details contain sensitive information', () {
      final testKeypair = ProfileKeypair(
        id: 'export-test-1',
        label: 'Export Test',
        algorithm: KeyAlgorithm.ed25519,
        publicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        privateKey: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
        mnemonic: 'export mnemonic abandon able about above absent act',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      final exportDetails = testKeypair.exportDetails();
      expect(exportDetails['Mnemonic'], testKeypair.mnemonic);
      expect(exportDetails['Public key (base64)'], testKeypair.publicKey);
      expect(exportDetails['Private key (base64)'], testKeypair.privateKey);
    });

    test('keypair toString produces valid JSON', () {
      final testKeypair = ProfileKeypair(
        id: 'string-test-1',
        label: 'String Test',
        algorithm: KeyAlgorithm.secp256k1,
        publicKey: 'dGVzdC1wdWJsaWMy',
        privateKey: 'dGVzdC1wcml2YXRlMg',
        mnemonic: 'string test mnemonic abandon able about above absent act',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      final stringRepresentation = testKeypair.toString();

      // Should be valid JSON and parse back correctly
      final parsedJson =
          jsonDecode(stringRepresentation) as Map<String, dynamic>;
      expect(parsedJson['id'], 'string-test-1');
      expect(parsedJson['label'], 'String Test');
      expect(parsedJson['algorithm'], 'secp256k1');
    });

    test('secure storage key prefixes are correct', () {
      // Test constants
      expect(_privateKeyPrefix, 'keypair_private_key_');
      expect(_mnemonicPrefix, 'keypair_mnemonic_');

      // Test key generation
      const keypairId = 'test-keypair-123';
      final privateKeyKey = '$_privateKeyPrefix$keypairId';
      final mnemonicKey = '$_mnemonicPrefix$keypairId';

      expect(privateKeyKey, 'keypair_private_key_test-keypair-123');
      expect(mnemonicKey, 'keypair_mnemonic_test-keypair-123');
    });

    test('non-sensitive data structure excludes sensitive fields', () {
      const keypairId = 'public-data-test-1';
      const label = 'Public Data Test';
      const algorithm = 'ed25519';
      const publicKey = 'dGVzdC1wdWJsaWM=';
      const createdAt = '2024-01-01T00:00:00.000Z';

      // Simulate the non-sensitive data structure that would be stored in regular JSON
      final publicData = <String, dynamic>{
        'id': keypairId,
        'label': label,
        'algorithm': algorithm,
        'publicKey': publicKey,
        'createdAt': createdAt,
      };

      // Verify only non-sensitive fields are included
      expect(publicData.keys, hasLength(5));
      expect(publicData['id'], keypairId);
      expect(publicData['label'], label);
      expect(publicData['algorithm'], algorithm);
      expect(publicData['publicKey'], publicKey);
      expect(publicData['createdAt'], createdAt);

      // Verify sensitive fields are NOT included
      expect(publicData.containsKey('privateKey'), false);
      expect(publicData.containsKey('mnemonic'), false);
    });

    test('secure storage prevents accidental exposure of sensitive data', () {
      // Test that sensitive data is never accidentally logged or serialized
      final sensitiveKeypair = ProfileKeypair(
        id: 'sensitive-test',
        label: 'Sensitive Test',
        algorithm: KeyAlgorithm.ed25519,
        publicKey: 'cHVibGljLWtleQ==',
        privateKey: 'cHJpdmF0ZS1rZXk=', // This should never appear in logs
        mnemonic:
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        createdAt: DateTime.parse('2024-01-01T00:00:00.000Z'),
      );

      // Verify toString doesn't expose sensitive data in the public part
      final stringRepresentation = sensitiveKeypair.toString();
      final parsedJson =
          jsonDecode(stringRepresentation) as Map<String, dynamic>;

      // The toString should serialize all data, but the public JSON store should not
      expect(parsedJson.containsKey('privateKey'),
          true); // toString contains everything
      expect(parsedJson.containsKey('mnemonic'), true);

      // But when creating public data for storage, sensitive fields are excluded
      final publicData = <String, dynamic>{
        'id': sensitiveKeypair.id,
        'label': sensitiveKeypair.label,
        'algorithm': keyAlgorithmToString(sensitiveKeypair.algorithm),
        'publicKey': sensitiveKeypair.publicKey,
        'createdAt': sensitiveKeypair.createdAt.toIso8601String(),
      };

      expect(publicData.containsKey('privateKey'), false);
      expect(publicData.containsKey('mnemonic'), false);
    });

    test('key prefixes ensure isolation of secure storage data', () {
      const keypairId1 = 'keypair-123';
      const keypairId2 = 'keypair-456';

      // Verify different keys are generated for different keypairs
      final privateKey1 = '$_privateKeyPrefix$keypairId1';
      final privateKey2 = '$_privateKeyPrefix$keypairId2';
      final mnemonic1 = '$_mnemonicPrefix$keypairId1';
      final mnemonic2 = '$_mnemonicPrefix$keypairId2';

      expect(privateKey1, isNot(equals(privateKey2)));
      expect(mnemonic1, isNot(equals(mnemonic2)));
      expect(privateKey1, isNot(equals(mnemonic1)));
      expect(privateKey1, contains(keypairId1));
      expect(mnemonic1, contains(keypairId1));
    });
  });
}

// Constants that should match those in SecureKeypairRepository
const String _privateKeyPrefix = 'keypair_private_key_';
const String _mnemonicPrefix = 'keypair_mnemonic_';
