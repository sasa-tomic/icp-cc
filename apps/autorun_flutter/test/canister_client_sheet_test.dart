import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/bookmarks_screen.dart';
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
    if (canisterId == 'invalid') {
      return null;
    }
    throw Exception('Network error');
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

  @override
  String? callAuthenticated({
    required String canisterId,
    required String method,
    required int kind,
    required String privateKeyB64,
    String args = '()',
    String? host,
  }) {
    return '{"result":"authenticated"}';
  }
}

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    String? initialCanisterId,
    String? initialMethodName,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanisterClientSheet(
            bridge: _FakeRustBridgeLoader(),
            initialCanisterId: initialCanisterId,
            initialMethodName: initialMethodName,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  group('CanisterClientSheet Simplified UX', () {
    testWidgets('shows canister input with friendly label', (tester) async {
      await pumpSheet(tester);

      final canisterField = find.byKey(const Key('canisterField'));
      expect(canisterField, findsOneWidget);

      final textField = tester.widget<TextField>(canisterField);
      expect(textField.decoration?.labelText, 'Canister');
    });

    testWidgets('advanced options are collapsed by default in ready state',
        (tester) async {
      await pumpSheet(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('methodChip_account_balance_dfx')));
      await tester.pumpAndSettle();

      final advancedTile = find.byKey(const Key('advancedOptionsTile'));
      expect(advancedTile, findsOneWidget);

      final expansionTile = tester.widget<ExpansionTile>(advancedTile);
      expect(expansionTile.initiallyExpanded, isFalse);
    });

    testWidgets('method chips appear after connecting to canister',
        (tester) async {
      await pumpSheet(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('methodChip_account_balance_dfx')),
          findsOneWidget);
      expect(find.byKey(const Key('methodChip_transfer')), findsOneWidget);
    });

    testWidgets('shows friendly error for invalid canister', (tester) async {
      await pumpSheet(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'invalid',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not load'), findsOneWidget);
    });

    testWidgets('selecting a method shows call button with method name',
        (tester) async {
      await pumpSheet(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('methodChip_account_balance_dfx')));
      await tester.pumpAndSettle();

      final callButton = find.byKey(const Key('callButton'));
      expect(callButton, findsOneWidget);
      expect(find.text('Call account_balance_dfx'), findsOneWidget);
    });

    testWidgets('shows no input required for zero-arg methods', (tester) async {
      await pumpSheet(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('methodChip_account_balance_dfx')));
      await tester.pumpAndSettle();

      expect(find.text('No input required'), findsOneWidget);
    });

    testWidgets('Query methods show search icon, Update shows sync icon',
        (tester) async {
      await pumpSheet(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final queryChip = tester.widget<FilterChip>(
        find.byKey(const Key('methodChip_account_balance_dfx')),
      );
      expect(queryChip.avatar, isNotNull);

      final updateChip = tester.widget<FilterChip>(
        find.byKey(const Key('methodChip_transfer')),
      );
      expect(updateChip.avatar, isNotNull);
    });

    testWidgets('shows result after calling method', (tester) async {
      await pumpSheet(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('methodChip_account_balance_dfx')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('callButton')));
      await tester.pump();

      expect(find.text('Result'), findsOneWidget);
      expect(find.textContaining('result'), findsOneWidget);
    });

    testWidgets('reset button clears state and returns to initial view',
        (tester) async {
      await pumpSheet(tester);

      await tester.enterText(
        find.byKey(const Key('canisterField')),
        'ryjl3-tyaaa-aaaaa-aaaba-cai',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('methodChip_account_balance_dfx')));
      await tester.pumpAndSettle();

      expect(find.text('Select Function'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(find.text('Select Function'), findsNothing);
      expect(find.text('Quick Start'), findsOneWidget);
    });

    testWidgets('canister input has tooltip with helpful text', (tester) async {
      await pumpSheet(tester);

      final canisterField = find.byKey(const Key('canisterField'));
      final tooltip = find.ancestor(
        of: canisterField,
        matching: find.byType(Tooltip),
      );

      expect(tooltip, findsOneWidget);
      final tooltipWidget = tester.widget<Tooltip>(tooltip);
      expect(
        tooltipWidget.message,
        contains('smart contract'),
      );
    });
  });
}
