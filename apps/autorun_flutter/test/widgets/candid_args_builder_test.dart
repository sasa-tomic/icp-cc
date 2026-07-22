import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/canister_method.dart';
import 'package:icp_autorun/widgets/candid_args_builder.dart';

CanisterMethod _methodWithArg(CanisterArg arg) {
  return CanisterMethod(
    name: 'test_method',
    mode: 0,
    args: [arg],
  );
}

Future<void> _pumpAtWidth(
  WidgetTester tester, {
  required CanisterMethod method,
  required double width,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: CandidArgsBuilder(
                method: method,
                args: const {},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('CandidArgsBuilder layout', () {
    testWidgets(
        'a compound candid type does not overflow a narrow row (L1 regression)',
        (tester) async {
      const arg = CanisterArg(
        name: 'arg0',
        type: 'record { id : nat64; topic : int32; tally : record '
            '{ yes : nat64; no : nat64; total : nat64 }; deadline : nat64 }',
      );
      await _pumpAtWidth(
        tester,
        method: _methodWithArg(arg),
        width: 200,
      );
      expect(find.text('arg0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
