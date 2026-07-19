import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/theme/app_design_system.dart';
import 'package:icp_autorun/widgets/account_key_details_sheet.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/widgets/script_details_dialog.dart';

/// UX-H3 regression guard: the previously hard-coded `Colors.white` call sites
/// (sheet backgrounds, avatar text on gradients, icons on primary containers)
/// must use theme tokens so they render correctly in BOTH light and dark
/// themes.
///
/// Before the fix every listed surface rendered as pure white — sheet
/// backgrounds, sheet-internal container tints, and (worse) text/icons placed
/// ON coloured gradients used `Colors.white` literally, breaking in Dark theme.
void main() {
  final script = MarketplaceScript(
    id: 's1',
    title: 'Sample Script',
    description: 'desc',
    category: 'Tools',
    tags: const ['tag'],
    price: 0,
    bundle: 'print(1)',
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );

  final accountKey = AccountPublicKey(
    id: 'k1',
    publicKey: '0xabc',
    icPrincipal: 'aaaaa-aa',
    isActive: true,
    addedAt: DateTime(2024, 1, 1),
  );

  Widget hostFor(Widget child, {required ThemeMode mode}) {
    return MaterialApp(
      theme: AppDesignSystem.lightTheme,
      darkTheme: AppDesignSystem.darkTheme,
      themeMode: mode,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Padding(
                padding: const EdgeInsets.all(24),
                child: child,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  group('UX-H3 — sheet backgrounds are theme-driven (not Colors.white)', () {
    testWidgets('AccountKeyDetailsSheet uses colorScheme.surface in dark mode',
        (tester) async {
      await tester.pumpWidget(hostFor(
        AccountKeyDetailsSheet(accountKey: accountKey, canRemove: false),
        mode: ThemeMode.dark,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The sheet's outer Container paints the sheet background — must match
      // the dark theme surface (dark grey), NOT Colors.white (the bug).
      final sheetContainer = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color != null,
        ),
      );
      expect(sheetContainer, isNotEmpty);
      final bg = (sheetContainer.first.decoration as BoxDecoration).color;
      expect(bg, equals(AppDesignSystem.darkTheme.colorScheme.surface));
      expect(bg, isNot(equals(Colors.white)));
    });
  });

  group('UX-H3 — surfaces render without exceptions in both themes', () {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('ProfileAvatarButton renders ($mode)', (tester) async {
        await tester.pumpWidget(hostFor(
          ProfileAvatarButton(
            displayName: 'Alice',
            hasAccount: true,
            showLabel: true,
            onTap: () {},
          ),
          mode: mode,
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('ScriptDetailsDialog renders ($mode)', (tester) async {
        await tester.pumpWidget(hostFor(
          ScriptDetailsDialog(script: script),
          mode: mode,
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.text('Sample Script'), findsOneWidget);
      });
    }
  });
}
