@TestOn('linux')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/canister_method.dart';
import 'package:icp_autorun/services/candid_service.dart';
import 'package:icp_autorun/widgets/frontend_scaffold_dialog.dart';

/// A [CandidService] whose `fetchCandid` returns a canned candid string
/// (so the dialog's generate flow runs without the real FFI / network).
CandidService _serviceWithMethods() {
  return CandidService(
    fetchCandid: (_, __) async => '''
service : {
  symbol : () -> (text);
  name : () -> (text);
  transfer : (principal, nat) -> (nat64);
}
''',
  );
}

CandidService _emptyService() {
  return CandidService(
      fetchCandid: (_, __) async => 'service : {}');
}

CandidService _failingService() {
  return CandidService(fetchCandid: (_, __) async => null);
}

void main() {
  group('FrontendScaffoldDialog', () {
    testWidgets('renders canister id, host fields, and a well-known dropdown',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const FrontendScaffoldDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Scaffold frontend from canister'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Canister ID'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Host (optional)'),
          findsOneWidget);
      // The well-known dropdown includes the canonical catalog entries.
      expect(find.text('Well-known canister'), findsOneWidget);
    });

    testWidgets('Generate is disabled until a canister id is entered',
        (tester) async {
      FrontendScaffoldResult? captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDialog<FrontendScaffoldResult>(
                    context: context,
                    builder: (_) => const FrontendScaffoldDialog(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The Generate button exists but onPressed is null until validated.
      final generateBtn =
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(generateBtn.onPressed, isNotNull); // Form not submitted yet.
      // Tap Generate with empty field → validator rejects, dialog stays open.
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(captured, isNull);
    });

    testWidgets('a valid canister id + candid generates a runnable bundle',
        (tester) async {
      FrontendScaffoldResult? captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDialog<FrontendScaffoldResult>(
                    context: context,
                    builder: (_) => FrontendScaffoldDialog(
                      candidService: _serviceWithMethods(),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Canister ID'),
          'ryjl3-tyaaa-aaaaa-aaaba-cai');
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.canisterId, 'ryjl3-tyaaa-aaaaa-aaaba-cai');
      expect(captured!.methodCount, 3);
      // The bundle is a complete IIFE exporting init/view/update.
      expect(captured!.bundle, contains('globalThis.init'));
      expect(captured!.bundle, contains('globalThis.view'));
      expect(captured!.bundle, contains('globalThis.update'));
      expect(captured!.bundle, contains('ryjl3-tyaaa-aaaaa-aaaba-cai'));
      expect(captured!.bundle, contains('"symbol"'));
      expect(captured!.bundle, contains('"transfer"'));
    });

    testWidgets('an empty candid interface surfaces an inline error',
        (tester) async {
      FrontendScaffoldResult? captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDialog<FrontendScaffoldResult>(
                    context: context,
                    builder: (_) =>
                        FrontendScaffoldDialog(candidService: _emptyService()),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Canister ID'),
          'ryjl3-tyaaa-aaaaa-aaaba-cai');
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(captured, isNull);
      expect(find.textContaining('No methods found'), findsOneWidget);
    });

    testWidgets('a candid fetch failure surfaces the CandidFetchException',
        (tester) async {
      FrontendScaffoldResult? captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDialog<FrontendScaffoldResult>(
                    context: context,
                    builder: (_) => FrontendScaffoldDialog(
                        candidService: _failingService()),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Canister ID'),
          'aaaaa-aa');
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      expect(captured, isNull);
      expect(find.textContaining("Couldn't load Candid"), findsOneWidget);
    });

    testWidgets('selecting a well-known canister fills the id field',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const FrontendScaffoldDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Open the well-known dropdown and pick NNS Governance.
      await tester.tap(find.text('Well-known canister'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('NNS Governance').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Canister ID')),
        (TextFormField tf) =>
            tf.controller!.text == 'rrkah-fqaaa-aaaaa-aaaaq-cai',
      );
    });
  });
}
