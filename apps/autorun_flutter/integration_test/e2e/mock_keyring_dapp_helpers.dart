// ignore_for_file: lines_longer_than_80_chars

/// Dapp-navigation helpers shared between the mock-keyring suites.
///
/// Extracted from `suite_mock_keyring_test.dart` so the new
/// `suite_mock_keyring_dapps_test.dart` (the split that runs dapp +
/// shortcut flows against a registered account, separate from the
/// main mock-keyring suite that was approaching the binding's stability
/// threshold) can reuse the same code without duplicating it.
///
/// Mirrors the helpers in `suite_keyring_less_test.dart` and
/// `poll_flows.dart` (same pattern, slightly different dapps).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/dapp_runner_screen.dart';
import 'package:icp_autorun/theme/modern_components.dart';

import 'e2e_driver.dart';

const String _kLedgerTitle = 'ICP Ledger';

/// Switch to the Dapps tab via the ModernNavigationBar callback. Gesture
/// taps are unreliable post-scripts.run (residual RenderAbsorbPointer);
/// invoking the callback directly tests the real nav code path.
///
/// Uses `.first` because in rare cases a route transition leaves a stale
/// ModernNavigationBar in the tree briefly.
Future<void> navigateToDapps(WidgetTester tester, E2EDriver d) async {
  await d.dismissOverlays(tester);
  final navBar = tester.widget<ModernNavigationBar>(
      find.byType(ModernNavigationBar).first);
  navBar.onTap(2);
  await tester.pump(const Duration(milliseconds: 500));
  final bodyReady = await d.waitUntil(
      tester, () => d.present(find.textContaining(_kLedgerTitle), tester),
      timeout: const Duration(seconds: 5));
  expect(bodyReady, isTrue,
      reason: 'Invoking the nav bar onTap(2) must switch to DappsScreen.');
}

/// Tap the ICP Ledger card → DappRunnerScreen pushes.
Future<void> tapLedgerCard(WidgetTester tester, E2EDriver d) async {
  final found = await d.waitUntil(
      tester, () => d.present(find.textContaining(_kLedgerTitle), tester),
      timeout: const Duration(seconds: 5));
  expect(found, isTrue, reason: 'ICP Ledger card must be present.');
  await tester.tap(find.textContaining(_kLedgerTitle).first);
  await tester.pump(const Duration(milliseconds: 500));
}

/// Closes DappRunnerScreen, dismissing any post-mount trust/permission
/// dialogs that may have appeared above the runner route. Mirrors
/// `_closeDappRunnerAfterRemount` in suite_keyring_less_test.dart.
Future<void> closeDappRunner(WidgetTester tester, E2EDriver d) async {
  await d.dismissOverlays(tester);
  // Dismiss any open dialogs above the runner route.
  var dialogSafety = 0;
  while (find.byType(Dialog).evaluate().isNotEmpty && dialogSafety < 6) {
    dialogSafety++;
    final rootCtx = find.byType(Navigator).evaluate().first;
    Navigator.of(rootCtx).pop();
    await tester.pump(const Duration(milliseconds: 400));
  }
  // Pop the runner route (Esc via ScreenShortcuts → maybePop).
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 500));
  if (d.present(find.byType(DappRunnerScreen), tester)) {
    final runnerEl = find.byType(DappRunnerScreen).evaluate().first;
    Navigator.of(runnerEl).pop();
    await tester.pump(const Duration(milliseconds: 500));
  }
  final closed = await d.waitUntil(
      tester, () => !d.present(find.byType(DappRunnerScreen), tester),
      timeout: const Duration(seconds: 5));
  expect(closed, isTrue,
      reason: 'DappRunnerScreen must close after dismissing dialogs.');
  await d.dismissOverlays(tester);
}
