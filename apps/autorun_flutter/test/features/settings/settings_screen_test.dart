import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/screens/settings_screen.dart';
import 'package:icp_autorun/services/settings_service.dart';

void main() {
  group('SettingsScreen', () {
    late SettingsService settingsService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      settingsService = SettingsService();
      // UXR7-5: pin the package info so the dynamic version string is
      // deterministic in tests (default platform values vary by host).
      PackageInfo.setMockInitialValues(
        appName: 'icp_autorun',
        packageName: 'icp_autorun',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
        installerStore: null,
      );
    });

    tearDown(() async {
      // Clean up any persisted developer options state
      await settingsService.clearDeveloperOptions();
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

      testWidgets('displays about section with version info',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        expect(find.text('ABOUT'), findsOneWidget);
        expect(find.text('ICP Autorun'), findsOneWidget);
        expect(find.textContaining('Version'), findsOneWidget);
      });

      testWidgets(
          'UXR7-5: version string is read dynamically from package info',
          (WidgetTester tester) async {
        // Reflect a release-style version + build number.
        PackageInfo.setMockInitialValues(
          appName: 'icp_autorun',
          packageName: 'icp_autorun',
          version: '2.3.4',
          buildNumber: '42',
          buildSignature: '',
          installerStore: null,
        );

        await pumpSettingsScreen(tester);

        // Rendered as "Version {version} ({buildNumber})", sourced from the
        // platform rather than a hardcoded literal.
        expect(find.text('Version 2.3.4 (42)'), findsOneWidget);
        expect(find.text('Version 1.0.0 (1)'), findsNothing);
      });

      testWidgets(
          'shows copy button for API endpoint when developer options enabled',
          (WidgetTester tester) async {
        // Enable developer options first
        await settingsService.setDeveloperOptionsEnabled(true);
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

    group('developer options - hidden by default', () {
      testWidgets('developer info section is hidden by default',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        // Developer info section should NOT be visible
        expect(find.text('DEVELOPER INFO'), findsNothing);
        expect(find.text('API Endpoint'), findsNothing);
        expect(find.text('Environment'), findsNothing);
      });

      testWidgets('tapping version once shows remaining taps hint',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        // Find version text and ensure it's visible
        final versionText = find.textContaining('Version');
        expect(versionText, findsOneWidget);
        await tester.ensureVisible(versionText);
        await tester.pumpAndSettle();
        await tester.tap(versionText);
        await tester.pumpAndSettle();

        // Should show snackbar with remaining taps
        expect(find.text('Tap 6 more times to enable developer options'),
            findsOneWidget);
      });

      testWidgets('tapping version shows correct countdown in hints',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        final versionText = find.textContaining('Version');
        await tester.ensureVisible(versionText);
        await tester.pumpAndSettle();

        // Tap 3 times and check the countdown
        for (int i = 0; i < 3; i++) {
          await tester.tap(versionText);
          await tester.pumpAndSettle();
        }

        // Should show "4 more times" (7 - 3 = 4)
        expect(find.text('Tap 4 more times to enable developer options'),
            findsOneWidget);
      });

      testWidgets(
          'tapping version 7 times enables developer options and shows section',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        final versionText = find.textContaining('Version');
        await tester.ensureVisible(versionText);
        await tester.pumpAndSettle();

        // Tap 7 times
        for (int i = 0; i < 7; i++) {
          await tester.tap(versionText);
          await tester.pumpAndSettle();
        }

        // Should show success message
        expect(find.text('Developer options enabled!'), findsOneWidget);

        // Dismiss the snackbar
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        // Developer info section should now be visible
        expect(find.text('DEVELOPER INFO'), findsOneWidget);
        expect(find.text('API Endpoint'), findsOneWidget);
        expect(find.text('Environment'), findsOneWidget);
      });

      testWidgets('developer options state persists across app restarts',
          (WidgetTester tester) async {
        // First, enable developer options
        await settingsService.setDeveloperOptionsEnabled(true);

        // Create a new screen instance (simulating app restart)
        await pumpSettingsScreen(tester);

        // Developer info section should be visible immediately
        expect(find.text('DEVELOPER INFO'), findsOneWidget);
        expect(find.text('API Endpoint'), findsOneWidget);
      });

      testWidgets('clear developer options hides the section',
          (WidgetTester tester) async {
        // First, enable developer options
        await settingsService.setDeveloperOptionsEnabled(true);
        await pumpSettingsScreen(tester);

        // Verify section is visible
        expect(find.text('DEVELOPER INFO'), findsOneWidget);

        // Tap the clear button
        final clearButton = find.text('Clear Developer Options');
        expect(clearButton, findsOneWidget);
        await tester.ensureVisible(clearButton);
        await tester.pumpAndSettle();
        await tester.tap(clearButton);
        await tester.pumpAndSettle();

        // Section should be hidden again
        expect(find.text('DEVELOPER INFO'), findsNothing);
        expect(find.text('API Endpoint'), findsNothing);
      });

      testWidgets('tapping other widgets does not affect tap counter',
          (WidgetTester tester) async {
        await pumpSettingsScreen(tester);

        // Tap somewhere else first
        await tester.tap(find.text('Light'));
        await tester.pumpAndSettle();

        // Then tap version - counter should start fresh
        final versionText = find.textContaining('Version');
        await tester.ensureVisible(versionText);
        await tester.pumpAndSettle();
        await tester.tap(versionText);
        await tester.pumpAndSettle();

        // Should show 6 remaining (not 5)
        expect(find.text('Tap 6 more times to enable developer options'),
            findsOneWidget);
      });
    });
  });
}
