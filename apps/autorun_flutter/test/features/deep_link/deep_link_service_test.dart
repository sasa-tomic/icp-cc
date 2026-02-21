import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/deep_link_service.dart';

void main() {
  late DeepLinkService service;

  setUp(() {
    DeepLinkService.resetForTesting();
    service = DeepLinkService();
  });

  tearDown(() {
    DeepLinkService.resetForTesting();
  });

  group('URL scheme parsing', () {
    test('parses valid script URL', () {
      final result = service.parseUrl('icpautorun://script/abc123');

      expect(result, isNotNull);
      expect(result!.type, equals(DeepLinkType.script));
      expect(result.scriptId, equals('abc123'));
    });

    test('parses script URL with special characters in ID', () {
      final result = service.parseUrl('icpautorun://script/script-abc_123');

      expect(result, isNotNull);
      expect(result!.type, equals(DeepLinkType.script));
      expect(result.scriptId, equals('script-abc_123'));
    });

    test('returns null for invalid scheme', () {
      final result = service.parseUrl('https://script/abc123');

      expect(result, isNull);
    });

    test('returns null for empty URL', () {
      final result = service.parseUrl('');

      expect(result, isNull);
    });

    test('returns null for malformed URL', () {
      final result = service.parseUrl('not a url at all');

      expect(result, isNull);
    });
  });

  group('script path validation', () {
    test('returns null for missing script ID', () {
      final result = service.parseUrl('icpautorun://script/');

      expect(result, isNull);
    });

    test('returns null for script path without ID', () {
      final result = service.parseUrl('icpautorun://script');

      expect(result, isNull);
    });

    test('returns null for unknown path', () {
      final result = service.parseUrl('icpautorun://unknown/abc123');

      expect(result, isNull);
    });
  });

  group('URI parsing', () {
    test('parses Uri object correctly', () {
      final uri = Uri.parse('icpautorun://script/xyz789');
      final result = service.parseUri(uri);

      expect(result, isNotNull);
      expect(result!.type, equals(DeepLinkType.script));
      expect(result.scriptId, equals('xyz789'));
    });
  });

  group('link stream', () {
    test('emits parsed link data for valid URL', () async {
      final linkFuture = service.linkStream.first;

      service.handleUrl('icpautorun://script/test123');

      final result = await linkFuture;
      expect(result.type, equals(DeepLinkType.script));
      expect(result.scriptId, equals('test123'));
    });

    test('does not emit for invalid URL', () async {
      var emitted = false;
      final subscription = service.linkStream.listen((_) {
        emitted = true;
      });

      service.handleUrl('https://invalid.com');

      await Future.delayed(const Duration(milliseconds: 100));

      expect(emitted, isFalse);
      await subscription.cancel();
    });
  });
}
