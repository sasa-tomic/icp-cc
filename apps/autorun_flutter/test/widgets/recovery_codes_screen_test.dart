import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/screens/recovery_codes_screen.dart';

class _LoggingNavigatorObserver extends NavigatorObserver {
  bool recoveryRoutePopped = false;

  @override
  void didPop(Route<dynamic>? route, Route<dynamic>? previousRoute) {
    if (route?.settings.name == 'RecoveryCodes') {
      recoveryRoutePopped = true;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const List<String> codes = <String>[
    'aaaa-bbbb',
    'cccc-dddd',
    'eeee-ffff',
    '1111-2222',
  ];

  Widget buildHarness({NavigatorObserver? observer}) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: 'RecoveryCodes'),
                    builder: (_) => const RecoveryCodesScreen(
                      codes: codes,
                      accountId: 'acct-test-1',
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
      navigatorObservers:
          observer == null ? const <NavigatorObserver>[] : [observer],
    );
  }

  group('RecoveryCodesScreen escape hatch (UX-CRIT-1)', () {
    testWidgets('AppBar exposes a back arrow', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('tapping back opens a warning dialog; Cancel keeps user on screen',
        (tester) async {
      final observer = _LoggingNavigatorObserver();
      await tester.pumpWidget(buildHarness(observer: observer));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Leave without saving?'), findsOneWidget);
      expect(observer.recoveryRoutePopped, isFalse,
          reason: 'Cancel must not pop the screen');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Leave without saving?'), findsNothing);
      expect(find.byType(RecoveryCodesScreen), findsOneWidget);
      expect(observer.recoveryRoutePopped, isFalse);
    });

    testWidgets('confirming Leave pops the screen', (tester) async {
      final observer = _LoggingNavigatorObserver();
      await tester.pumpWidget(buildHarness(observer: observer));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.byType(RecoveryCodesScreen), findsNothing);
      expect(observer.recoveryRoutePopped, isTrue,
          reason: 'Leave must dismiss the screen via Navigator.pop');
    });
  });

  group('RecoveryCodesScreen Download .txt (UX-CRIT-1)', () {
    testWidgets('a Download button is rendered next to Copy', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Copy'), findsWidgets);
      expect(find.byIcon(Icons.download), findsOneWidget);
      expect(find.textContaining('Download'), findsWidgets);
    });
  });

  // Smoke check the txt-builder directly so we cover the format without
  // standing up path_provider in the widget test environment.
  test('buildRecoveryCodesFileText contains header, account and every code',
      () {
    final text = buildRecoveryCodesFileText(
      codes: codes,
      accountId: 'acct-test-1',
      generatedAt: DateTime.utc(2026, 7, 19, 13, 0, 0),
    );
    expect(text, contains('Recovery Codes'));
    expect(text, contains('acct-test-1'));
    expect(text, contains('2026-07-19'));
    for (final c in codes) {
      expect(text, contains(c));
    }
  });
}
