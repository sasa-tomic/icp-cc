import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/screens/settings_screen.dart';
import 'package:icp_autorun/services/settings_service.dart';

void main() {
  group('SettingsScreen', () {
    late SettingsService settingsService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      settingsService = SettingsService();
    });

    Future<void> pumpSettingsScreen(
      WidgetTester tester, {
      VoidCallback? onThemeChanged,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsService: settingsService,
            onThemeChanged: onThemeChanged,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    group('initialization', () {
      testWidgets('shows loading indicator while loading settings',
          (WidgetTester tester) async {
        // Start pumping but don't wait for async operations
        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              settingsService: settingsService,
            ),
          ),
        );

        // Should show loading initially before async completes
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('loads theme mode from service on init',
          (WidgetTester tester) async {
        // Set a dark theme preference
        await settingsService.setThemeMode(ThemeMode.dark);

        await pumpSettingsScreen(tester);
        await tester.pumpAndSettle();

        // Dark theme option should be selected
        final darkOption = find.text('Dark');
        expect(darkOption, findsOneWidget);
      });
    });

    group('theme selection', () {
      testWidgets('displays all three theme options',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        expect(find.text('System'), findsOneWidget);
        expect(find.text('Light'), findsOneWidget);
        expect(find.text('Dark'), findsOneWidget);
      });

      testWidgets('shows System theme as selected by default',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        // Find the System option
        final systemOption = find.ancestor(
          of: find.text('System'),
          matching: find.byType(InkWell),
        );

        // Should have the selected border
        final container = find
            .descendant(
              of: systemOption,
              matching: find.byType(Container),
            )
            .first;

        final containerWidget = tester.widget<Container>(container);
        final decoration = containerWidget.decoration as BoxDecoration;
        expect(decoration.border, isNotNull);
      });

      testWidgets('selecting Light theme updates preference',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        await tester.tap(find.text('Light'));
        await tester.pumpAndSettle();

        // Verify the theme was saved
        final savedTheme = await settingsService.getThemeMode();
        expect(savedTheme, equals(ThemeMode.light));
      });

      testWidgets('selecting Dark theme updates preference',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();

        // Verify the theme was saved
        final savedTheme = await settingsService.getThemeMode();
        expect(savedTheme, equals(ThemeMode.dark));
      });

      testWidgets('calls onThemeChanged when theme changes',
          (WidgetTester tester) async {
        bool themeChangedCalled = false;

        await pumpSettingsScreen(
          tester,
          onThemeChanged: () {
            themeChangedCalled = true;
          },
        );

        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();

        expect(themeChangedCalled, isTrue);
      });
    });

    group('UI elements', () {
      testWidgets('displays appearance section header',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        expect(find.text('APPEARANCE'), findsOneWidget);
      });

      testWidgets('displays links section with all options',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        expect(find.text('LINKS'), findsOneWidget);
        expect(find.text('Documentation'), findsOneWidget);
        expect(find.text('Report Issue'), findsOneWidget);
        expect(find.text('Marketplace Website'), findsOneWidget);
      });

      testWidgets('displays developer info section',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        expect(find.text('DEVELOPER INFO'), findsOneWidget);
        expect(find.text('API Endpoint'), findsOneWidget);
        expect(find.text('Environment'), findsOneWidget);
      });

      testWidgets('displays about section with version info',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        expect(find.text('ABOUT'), findsOneWidget);
        expect(find.text('ICP Autorun'), findsOneWidget);
        expect(find.textContaining('Version'), findsOneWidget);
      });

      testWidgets('shows copy button for API endpoint',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        // Find the API endpoint row and check it has a copy icon
        final apiEndpointTile = find.ancestor(
          of: find.text('API Endpoint'),
          matching: find.byType(Row),
        );

        expect(
          find.descendant(
            of: apiEndpointTile,
            matching: find.byIcon(Icons.copy),
          ),
          findsOneWidget,
        );
      });
    });

    group('theme option descriptions', () {
      testWidgets('shows correct subtitle for System option',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        expect(find.text('Follow system settings'), findsOneWidget);
      });

      testWidgets('shows correct subtitle for Light option',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        expect(find.text('Always use light theme'), findsOneWidget);
      });

      testWidgets('shows correct subtitle for Dark option',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        expect(find.text('Always use dark theme'), findsOneWidget);
      });
    });
  });
}
