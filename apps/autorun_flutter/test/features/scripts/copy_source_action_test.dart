import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Copy Source action (UX-B4)', () {
    Future<void> pumpWithClipboardHarness(
      WidgetTester tester, {
      required String? Function() readClipboard,
      required void Function(String?) writeClipboard,
    }) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform,
          (MethodCall call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            writeClipboard((call.arguments as Map?)?['text'] as String? ?? '');
            return null;
          case 'Clipboard.getData':
            final text = readClipboard();
            return text == null
                ? <String, Object?>{}
                : <String, Object?>{'text': text};
        }
        return null;
      });
    }

    testWidgets(
        '"Copy Source" places the script bundle on the clipboard verbatim '
        '(label and behavior agree)', (tester) async {
      String? mockClipboard;
      await pumpWithClipboardHarness(
        tester,
        readClipboard: () => mockClipboard,
        writeClipboard: (v) => mockClipboard = v,
      );

      const String bundle = '// my unique bundle payload\nreturn 42;';
      final script = ScriptRecord(
        id: 'copy-source-1',
        title: 'Copy Source Fixture',
        bundle: bundle,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      // "Copy Source" is a clipboard action (not a file export). The bundle
      // the author wrote must reach the clipboard verbatim.
      await tester.runAsync(() => copyScriptSourceToClipboard(script));

      expect(mockClipboard, equals(bundle),
          reason: 'Copy Source must copy the script bundle verbatim');

      final ClipboardData? data = await tester
          .runAsync<ClipboardData?>(
              () async => Clipboard.getData('text/plain'));
      expect(data?.text, equals(bundle),
          reason: 'Clipboard.getData must return the copied bundle');
    });

    testWidgets('Copy Source reflects the latest bundle, not a stale value',
        (tester) async {
      String? mockClipboard;
      await pumpWithClipboardHarness(
        tester,
        readClipboard: () => mockClipboard,
        writeClipboard: (v) => mockClipboard = v,
      );

      final first = ScriptRecord(
        id: 'copy-source-2',
        title: 'First',
        bundle: 'first-bundle',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final second = ScriptRecord(
        id: 'copy-source-3',
        title: 'Second',
        bundle: 'second-bundle',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      await tester.runAsync(() => copyScriptSourceToClipboard(first));
      await tester.runAsync(() => copyScriptSourceToClipboard(second));

      expect(mockClipboard, equals('second-bundle'),
          reason: 'Clipboard must hold the most recently copied bundle');
    });
  });
}
