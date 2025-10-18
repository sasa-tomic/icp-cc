import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';
import 'package:icp_autorun/services/script_runner.dart';

class _FakeRuntime implements IScriptAppRuntime {
  @override
  Future<Map<String, dynamic>> init({required String script, Map<String, dynamic>? initialArg, int budgetMs = 50}) async {
    // Return initial state and an effect that will require permission
    return <String, dynamic>{
      'ok': true,
      'state': <String, dynamic>{},
      // Simulate runtime returning an object instead of list for empty effects (should be tolerated)
      'effects': <String, dynamic>{},
    };
  }

  @override
  Future<Map<String, dynamic>> update({required String script, required Map<String, dynamic> msg, required Map<String, dynamic> state, int budgetMs = 50}) async {
    // After first frame, return a list-based effect to trigger permission
    return <String, dynamic>{
      'ok': true,
      'state': <String, dynamic>{},
      'effects': <dynamic>[
        <String, dynamic>{
          'kind': 'icp_call',
          'id': 'e1',
          'canister_id': 'aaaaa-aa',
          'method': 'greet',
          'mode': 0,
          'args': '("World")',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> view({required String script, required Map<String, dynamic> state, int budgetMs = 50}) async {
    return <String, dynamic>{
      'ok': true,
      'ui': <String, dynamic>{
        'type': 'column',
        'children': <dynamic>[
          <String, dynamic>{
            'type': 'button',
            'props': <String, dynamic>{ 'label': 'Trigger', 'on_press': <String, dynamic>{ 'type': 'go' } },
          },
        ],
      },
    };
  }
}

void main() {
  testWidgets('ScriptAppHost shows permission dialog and proceeds on allow', (tester) async {
    final fake = _FakeRuntime();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScriptAppHost(runtime: fake, script: '-- lua --'),
      ),
    ));

    // Initial frame and async startup
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    // No dialog yet since effects were an object (treated as empty)
    expect(find.textContaining('Allow canister call?'), findsNothing);

    // Tap the Trigger button to cause update() which returns a call effect
    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();

    // Expect a dialog asking for permission
    expect(find.textContaining('Allow canister call?'), findsOneWidget);
    // Click Allow once
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();

    // After allowing, no error label should be present
    expect(find.textContaining('permission denied'), findsNothing);
  });
}
