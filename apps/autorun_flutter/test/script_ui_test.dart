import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/integrations_help.dart';

void main() {
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