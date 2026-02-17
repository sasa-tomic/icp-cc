import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/script_integrity_service.dart';

void main() {
  late ScriptIntegrityService integrityService;

  setUp(() {
    integrityService = ScriptIntegrityService();
  });

  group('ScriptRecord with integrity checksum', () {
    test('preserves sha256_checksum in metadata through copyWith', () {
      final now = DateTime.now().toUtc();
      final original = ScriptRecord(
        id: 'test-1',
        title: 'Test Script',
        luaSource: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {
          'marketplace_id': 'mp-123',
          'sha256_checksum': 'abc123',
        },
      );

      final copied = original.copyWith(title: 'Updated Title');

      expect(copied.metadata['marketplace_id'], equals('mp-123'));
      expect(copied.metadata['sha256_checksum'], equals('abc123'));
    });

    test('allows clearing sha256_checksum when source is modified', () {
      final now = DateTime.now().toUtc();
      final original = ScriptRecord(
        id: 'test-1',
        title: 'Test Script',
        luaSource: 'return 1',
        createdAt: now,
        updatedAt: now,
        metadata: {
          'marketplace_id': 'mp-123',
          'sha256_checksum': 'abc123',
        },
      );

      final updatedMetadata = Map<String, dynamic>.from(original.metadata)
        ..remove('sha256_checksum');

      final updated = original.copyWith(
        luaSource: 'return 2',
        metadata: updatedMetadata,
      );

      expect(updated.metadata['marketplace_id'], equals('mp-123'));
      expect(updated.metadata.containsKey('sha256_checksum'), isFalse);
    });

    test('checksum verification flow for marketplace script', () {
      const luaSource = 'function init() return {}, {} end';
      final checksum = integrityService.computeChecksum(luaSource);

      final now = DateTime.now().toUtc();
      final script = ScriptRecord(
        id: 'mp-script-1',
        title: 'Marketplace Script',
        luaSource: luaSource,
        createdAt: now,
        updatedAt: now,
        metadata: {
          'marketplace_id': 'mp-123',
          'sha256_checksum': checksum,
        },
      );

      final storedChecksum = script.metadata['sha256_checksum'] as String;
      expect(
        () => integrityService.verifyChecksum(script.luaSource, storedChecksum,
            scriptId: script.id),
        returnsNormally,
      );
    });

    test('detects tampered marketplace script', () {
      const originalSource = 'function init() return {}, {} end';
      const tamperedSource = 'function init() return {}, {} ene';

      final checksum = integrityService.computeChecksum(originalSource);

      final now = DateTime.now().toUtc();
      final script = ScriptRecord(
        id: 'mp-script-1',
        title: 'Marketplace Script',
        luaSource: tamperedSource,
        createdAt: now,
        updatedAt: now,
        metadata: {
          'sha256_checksum': checksum,
        },
      );

      final storedChecksum = script.metadata['sha256_checksum'] as String;
      expect(
        () => integrityService.verifyChecksum(script.luaSource, storedChecksum,
            scriptId: script.id),
        throwsA(isA<ScriptIntegrityException>()),
      );
    });

    test('local scripts without checksum run without verification', () {
      const luaSource = 'return 1';

      final now = DateTime.now().toUtc();
      final script = ScriptRecord(
        id: 'local-1',
        title: 'Local Script',
        luaSource: luaSource,
        createdAt: now,
        updatedAt: now,
        metadata: {},
      );

      expect(script.metadata.containsKey('sha256_checksum'), isFalse);
    });

    test('JSON serialization preserves checksum', () {
      final now = DateTime.now().toUtc();
      const checksum =
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

      final original = ScriptRecord(
        id: 'test-1',
        title: 'Test Script',
        luaSource: 'hello',
        createdAt: now,
        updatedAt: now,
        metadata: {
          'marketplace_id': 'mp-123',
          'sha256_checksum': checksum,
        },
      );

      final json = original.toJson();
      final restored = ScriptRecord.fromJson(json);

      expect(restored.metadata['sha256_checksum'], equals(checksum));
      expect(restored.metadata['marketplace_id'], equals('mp-123'));
    });
  });
}
