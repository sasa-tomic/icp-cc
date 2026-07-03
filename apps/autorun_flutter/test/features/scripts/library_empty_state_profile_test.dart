import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/scripts_empty_state.dart';

import '_scripts_test_harness.dart';

/// WU-1: Profile-aware Scripts empty-state.
///
/// When the user dismissed the first-run wizard without creating a profile, the
/// `library` variant must offer a "Set Up Profile" CTA instead of the
/// keypair-dependent Create / Browse actions.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool hasProfile,
    VoidCallback? onSetupProfile,
    VoidCallback? onCreateScript,
    VoidCallback? onBrowseMarketplace,
  }) async {
    await pumpInScaffold(
      tester,
      ScriptsEmptyState(
        kind: ScriptsEmptyStateKind.library,
        hasProfile: hasProfile,
        onSetupProfile: onSetupProfile,
        onCreateScript: onCreateScript,
        onBrowseMarketplace: onBrowseMarketplace,
      ),
    );
    // Run the ModernEmptyState entrance animations to completion.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('ScriptsEmptyState library variant (WU-1)', () {
    testWidgets(
        'hasProfile=false shows "Set Up Profile" and hides Create / Browse',
        (tester) async {
      await pump(tester, hasProfile: false, onSetupProfile: () {});

      expect(find.text('Set Up Your Profile'), findsOneWidget);
      expect(find.text('Set Up Profile'), findsOneWidget);
      expect(find.text('Create Script'), findsNothing);
      expect(find.text('Browse Marketplace'), findsNothing);
    });

    testWidgets(
        'hasProfile=true (default) keeps the legacy Create / Browse CTAs',
        (tester) async {
      await pump(
        tester,
        hasProfile: true,
        onCreateScript: () {},
        onBrowseMarketplace: () {},
      );

      expect(find.text('Your Script Library is Empty'), findsOneWidget);
      expect(find.text('Create Script'), findsOneWidget);
      expect(find.text('Browse Marketplace'), findsOneWidget);
      expect(find.text('Set Up Profile'), findsNothing);
    });

    testWidgets('tapping "Set Up Profile" fires onSetupProfile',
        (tester) async {
      var setupCalled = false;
      await pump(
        tester,
        hasProfile: false,
        onSetupProfile: () => setupCalled = true,
      );

      await tester.tap(find.text('Set Up Profile'));
      await tester.pump();

      expect(setupCalled, isTrue);
    });

    testWidgets('omitting hasProfile defaults to legacy CTAs', (tester) async {
      await pumpInScaffold(
        tester,
        ScriptsEmptyState(
          kind: ScriptsEmptyStateKind.library,
          onCreateScript: () {},
          onBrowseMarketplace: () {},
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Create Script'), findsOneWidget);
      expect(find.text('Set Up Profile'), findsNothing);
    });
  });
}
