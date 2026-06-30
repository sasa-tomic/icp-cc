import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_template.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    ScriptTemplates.resetForTest();
    await ScriptTemplates.ensureInitialized();
  });

  group('ScriptTemplates catalog (TS-only)', () {
    test('exposes exactly the 4 built-in TS templates', () {
      expect(ScriptTemplates.templates.length, 4);
      final ids = ScriptTemplates.templates.map((t) => t.id).toSet();
      expect(ids, {'hello_world', 'icp_demo', 'advanced_ui', 'typescript_counter'});
    });

    test('getById returns the template and null for unknown ids', () {
      final hello = ScriptTemplates.getById('hello_world');
      expect(hello, isNotNull);
      expect(hello!.title, 'Hello World');
      expect(hello.emoji, '👋');
      expect(hello.level, 'beginner');
      expect(hello.isRecommended, isTrue);

      expect(ScriptTemplates.getById('does-not-exist'), isNull);
    });

    test('getByLevel partitions templates correctly', () {
      expect(ScriptTemplates.getByLevel('beginner').length, 2);
      expect(ScriptTemplates.getByLevel('intermediate').length, 1);
      expect(ScriptTemplates.getByLevel('advanced').length, 1);
      expect(ScriptTemplates.getByLevel('expert'), isEmpty);
    });

    test('getRecommended returns only the recommended templates', () {
      final recommended = ScriptTemplates.getRecommended();
      expect(recommended.length, 2);
      expect(recommended.every((t) => t.isRecommended), isTrue);
      expect(recommended.map((t) => t.id).toSet(), {'hello_world', 'typescript_counter'});
    });

    test('search matches title, description, and tags (case-insensitive)', () {
      expect(ScriptTemplates.search('hello').single.id, 'hello_world');
      // 'counter' appears in the typescript_counter title/tags AND hello_world's
      // description ("a counter, and a text field"), so both match.
      expect(ScriptTemplates.search('counter').map((t) => t.id).toSet(),
          {'hello_world', 'typescript_counter'});
      // 'canister' uniquely matches the icp_demo description/tags.
      expect(ScriptTemplates.search('canister').single.id, 'icp_demo');
      // Empty query returns every template.
      expect(ScriptTemplates.search('').length, ScriptTemplates.templates.length);
      // No matches.
      expect(ScriptTemplates.search('nonexistent-zzz'), isEmpty);
    });
  });

  group('ScriptTemplate bundle contents', () {
    test('every template has a non-empty loaded bundle', () {
      for (final t in ScriptTemplates.templates) {
        expect(t.bundle, isNotEmpty, reason: '${t.id} bundle must be loaded');
      }
    });

    test('every bundle is a self-contained TypeScript/QuickJS module', () {
      // Bundles are pre-bundled IIFEs that expose init/view/update on
      // globalThis; they must NOT rely on host-injected helpers.
      for (final t in ScriptTemplates.templates) {
        final source = t.bundle;
        expect(source, contains('globalThis.init'),
            reason: '${t.id} bundle must expose globalThis.init');
        expect(source, contains('globalThis.view'),
            reason: '${t.id} bundle must expose globalThis.view');
        expect(source, contains('globalThis.update'),
            reason: '${t.id} bundle must expose globalThis.update');
      }
    });
  });
}
