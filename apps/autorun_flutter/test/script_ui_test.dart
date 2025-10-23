import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/integrations_help.dart';

class _FakeBridge implements ScriptBridge {
  @override
  String? callAnonymous({required String canisterId, required String method, required int kind, String args = '()', String? host}) {
    return json.encode({'ok': true, 'echo': {'cid': canisterId, 'm': method, 'args': args}});
  }

  @override
  String? callAuthenticated({required String canisterId, required String method, required int kind, required String privateKeyB64, String args = '()', String? host}) {
    return json.encode({'ok': true, 'auth': true});
  }

  @override
  String? luaExec({required String script, String? jsonArg}) {
    // Return a basic UI description
    return json.encode({
      'ok': true,
      'result': {
        'action': 'ui',
        'ui': {
          'type': 'list',
          'items': [ {'title': 'A'}, {'title': 'B'} ],
          'buttons': [
            {
              'label': 'Ping',
              'on_press': { 'action': 'call', 'canister_id': 'abc', 'method': 'go', 'kind': 0, 'args': '()' }
            }
          ]
        }
      }
    });
  }

  @override
  String? luaLint({required String script}) {
    return json.encode({'ok': true, 'errors': []});
  }

  @override
  String? luaAppInit({required String script, String? jsonArg, int budgetMs = 50}) => null;

  @override
  String? luaAppUpdate({required String script, required String msgJson, required String stateJson, int budgetMs = 50}) => null;

  @override
  String? luaAppView({required String script, required String stateJson, int budgetMs = 50}) => null;
}

void main() {
  test('performAction executes call and decodes JSON', () async {
    final runner = ScriptRunner(_FakeBridge());
    final res = await runner.performAction({
      'action': 'call',
      'canister_id': 'abc',
      'method': 'go',
      'kind': 0,
      'args': '()'
    });
    expect(res.ok, true);
    expect((res.result as Map<String, dynamic>)['ok'], true);
  });

  test('Lua UI result is passed through by runner', () async {
    final runner = ScriptRunner(_FakeBridge());
    final plan = ScriptRunPlan(luaSource: 'return icp_ui_list({ items = { { title = "A" } } })');
    final res = await runner.run(plan);
    expect(res.ok, true);
    final obj = res.result as Map<String, dynamic>;
    expect(obj['action'], 'ui');
    final ui = obj['ui'] as Map<String, dynamic>;
    expect(ui['type'], 'list');
  });

  testWidgets('Integrations help dialog lists known integrations', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => const IntegrationsHelpDialog(),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Check that the dialog opens
    expect(find.text('Available integrations'), findsOneWidget);

    // Check that the new Canister Call Builder is present
    expect(find.text('Canister Call Builder'), findsOneWidget);
    expect(find.text('Build canister method calls with a visual interface'), findsOneWidget);
    expect(find.text('Lua Helper Functions'), findsOneWidget);

    // Count total integration items (should be 4 original + 1 new button = 5 total visible items)
    final integrationItems = find.byType(ListTile);
    expect(integrationItems.evaluate().length, greaterThanOrEqualTo(5));
  });
}
