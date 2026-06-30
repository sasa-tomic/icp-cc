import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_integrity_service.dart';

void main() {
  late ScriptIntegrityService service;

  setUp(() {
    service = ScriptIntegrityService();
  });

  group('computeChecksum', () {
    test('produces consistent SHA256 hash for identical input', () {
      const source = 'globalThis.init=()=>({state:{},effects:[]});';
      final checksum1 = service.computeChecksum(source);
      final checksum2 = service.computeChecksum(source);

      expect(checksum1, equals(checksum2));
      expect(checksum1.length, equals(64));
    });

    test('produces different hashes for different input', () {
      const source1 = 'return 1';
      const source2 = 'return 2';

      final checksum1 = service.computeChecksum(source1);
      final checksum2 = service.computeChecksum(source2);

      expect(checksum1, isNot(equals(checksum2)));
    });

    test('handles empty string', () {
      final checksum = service.computeChecksum('');

      expect(checksum.length, equals(64));
      expect(
          checksum,
          equals(
              'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'));
    });

    test('produces correct SHA256 hash for known input', () {
      final checksum = service.computeChecksum('hello');

      expect(
          checksum,
          equals(
              '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'));
    });
  });

  group('verifyChecksum', () {
    test('passes when checksum matches', () {
      const source = 'globalThis.init=()=>({state:{},effects:[]});';
      final expectedChecksum = service.computeChecksum(source);

      expect(
        () => service.verifyChecksum(source, expectedChecksum),
        returnsNormally,
      );
    });

    test('throws ScriptIntegrityException on mismatch', () {
      const source = 'return 1';
      const wrongChecksum =
          '0000000000000000000000000000000000000000000000000000000000000000';

      expect(
        () => service.verifyChecksum(source, wrongChecksum),
        throwsA(isA<ScriptIntegrityException>()),
      );
    });

    test('includes script ID in error message when provided', () {
      const source = 'return 1';
      const wrongChecksum =
          '0000000000000000000000000000000000000000000000000000000000000000';

      expect(
        () => service.verifyChecksum(source, wrongChecksum,
            scriptId: 'script-123'),
        throwsA(allOf(
          isA<ScriptIntegrityException>(),
          predicate<ScriptIntegrityException>(
            (e) => e.message.contains('script-123'),
            'contains script ID',
          ),
        )),
      );
    });

    test('detects tampering (single character change)', () {
      const original = 'globalThis.init=()=>({state:{},effects:[]});';
      const tampered = 'function init() return {}, {} ene'; // last char changed

      final originalChecksum = service.computeChecksum(original);

      expect(
        () => service.verifyChecksum(tampered, originalChecksum),
        throwsA(isA<ScriptIntegrityException>()),
      );
    });
  });

  group('hasValidChecksum', () {
    test('returns true when checksum matches', () {
      const source = 'globalThis.init=()=>({state:{},effects:[]});';
      final checksum = service.computeChecksum(source);

      expect(service.hasValidChecksum(source, checksum), isTrue);
    });

    test('returns false when checksum does not match', () {
      const source = 'globalThis.init=()=>({state:{},effects:[]});';
      const wrongChecksum =
          '0000000000000000000000000000000000000000000000000000000000000000';

      expect(service.hasValidChecksum(source, wrongChecksum), isFalse);
    });
  });
}
