import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/canister_client_screen.dart';
import 'package:icp_autorun/rust/native_bridge.dart';

class _FakeRustBridgeLoader extends RustBridgeLoader {
  @override
  Future<String?> fetchCandid(
      {required String canisterId, String? host}) async {
    if (canisterId == 'ryjl3-tyaaa-aaaaa-aaaba-cai') {
      return '''
service: {
  account_balance_dfx: (record {}) -> (record {});
  transfer: (record {}) -> (record {});
}
''';
    }
    return null;
  }

  @override
  String? parseCandid({required String candidText}) {
    if (candidText.contains('service:')) {
      return '{"methods":[{"name":"account_balance_dfx","kind":"query","args":[],"rets":[]},{"name":"transfer","kind":"update","args":[],"rets":[]}]}';
    }
    return null;
  }

  @override
  String? callAnonymous({
    required String canisterId,
    required String method,
    required int kind,
    String args = '()',
    String? host,
  }) {
    return '{"result":"ok"}';
  }
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    String? initialCanisterId,
    String? initialMethodName,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CanisterClientScreen(
          bridge: _FakeRustBridgeLoader(),
          initialCanisterId: initialCanisterId,
          initialMethodName: initialMethodName,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CanisterClientScreen Full Screen', () {
    testWidgets('opens as full screen with Scaffold and AppBar',
        (tester) async {
      await pumpScreen(tester);

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('AppBar shows step indicator', (tester) async {
      await pumpScreen(tester);

      expect(find.textContaining('Step 1'), findsOneWidget);
      expect(find.textContaining('Canister'), findsWidgets);
    });

    testWidgets('step 1 shows canister input field', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('canisterField')), findsOneWidget);
    });

    testWidgets('step 1 shows Next button disabled initially', (tester) async {
      await pumpScreen(tester);

      final nextButton = find.byKey(const Key('nextButton'));
      expect(nextButton, findsOneWidget);

      final elevatedButton = tester.widget<ElevatedButton>(nextButton);
      expect(elevatedButton.onPressed, isNull);
    });

    testWidgets('step 1 to step 2 transition works after connecting',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final nextButton = find.byKey(const Key('nextButton'));
      expect(nextButton, findsOneWidget);

      final elevatedButton = tester.widget<ElevatedButton>(nextButton);
      expect(elevatedButton.onPressed, isNotNull);

      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Step 2'), findsOneWidget);
      expect(find.textContaining('Function'), findsWidgets);
    });

    testWidgets('step 2 shows method selector after connecting',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('methodChip_account_balance_dfx')),
          findsOneWidget);
      expect(find.byKey(const Key('methodChip_transfer')), findsOneWidget);
    });

    testWidgets('Back button returns to previous step', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Step 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('backButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Step 1'), findsOneWidget);
    });

    testWidgets('step 2 to step 3 transition after selecting method',
        (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('methodChip_account_balance_dfx')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Step 3'), findsOneWidget);
      expect(find.textContaining('Call'), findsWidgets);
    });

    testWidgets('Call button only enabled on step 3', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('callButton')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('callButton')), findsNothing);

      await tester.tap(find.byKey(const Key('methodChip_account_balance_dfx')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextButton')));
      await tester.pumpAndSettle();

      final callButton = find.byKey(const Key('callButton'));
      expect(callButton, findsOneWidget);

      final filledButton = tester.widget<FilledButton>(callButton);
      expect(filledButton.onPressed, isNotNull);
    });

    testWidgets('shows result after calling method on step 3', (tester) async {
      await pumpScreen(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('methodChip_account_balance_dfx')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nextButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('callButton')));
      await tester.pump();

      expect(find.text('Result'), findsOneWidget);
    });

    testWidgets('close button pops the screen', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(CanisterClientScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('closeButton')));
      await tester.pumpAndSettle();

      expect(find.byType(CanisterClientScreen), findsNothing);
    });
  });
}
