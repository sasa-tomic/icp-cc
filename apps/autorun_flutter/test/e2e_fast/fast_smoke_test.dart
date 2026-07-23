// ignore_for_file: lines_longer_than_80_chars

/// Fast e2e PoC — proves the widget-test harness works on the Dart VM with
/// substrate fakes + real FFI. Runs in seconds, not minutes.
///
/// Run:
///   `flutter test test/e2e_fast/fast_smoke_test.dart`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/e2e/flow_catalog.dart';
import '../../integration_test/e2e/flow_implementations.dart';
import 'fast_harness.dart';

void main() {
  final harness = FastHarness();
  final registry = FlowRegistry()
    ..register('scripts.browse_marketplace', scriptsBrowseMarketplace)
    ..register('scripts.search', scriptsSearch)
    ..register('scripts.view_details', scriptsViewDetails)
    ..register('settings.open', settingsOpen)
    ..register('profile.open_menu', profileOpenMenu)
    ..register('first_run.reopen_wizard_chip', firstRunReopenWizardChip);

  setUpAll(() async {
    await harness.setUp();
  });

  tearDownAll(() async {
    await harness.tearDown();
  });

  testWidgets('boot: wizard or profile chip appears', (tester) async {
    harness.resetState();
    await harness.boot(tester);
    // After boot, EITHER the wizard (first-run) OR the "Set up profile" chip
    // (returning user) must be visible — proves the async boot chain ran.
    final wizardOrChip = find.byWidgetPredicate((w) =>
        '$w'.contains('UnifiedSetupWizard') ||
        (w is Text && (w.data?.contains('Set up profile') ?? false)));
    expect(harness.driver.present(wizardOrChip, tester), isTrue,
        reason: 'Boot must produce either the wizard or the profile chip.');
    // Drain flutter_cache_manager cleanup timer.
    await tester.pump(const Duration(seconds: 11));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('scripts.browse_marketplace', (tester) async {
    harness.resetState();
    await harness.boot(tester);
    await harness.dismissWizard(tester);
    await registry.runFor('scripts.browse_marketplace')!(tester, harness.driver);
    await tester.pump(const Duration(seconds: 11));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('scripts.search', (tester) async {
    harness.resetState();
    await harness.boot(tester);
    await harness.dismissWizard(tester);
    await registry.runFor('scripts.search')!(tester, harness.driver);
    await tester.pump(const Duration(seconds: 11));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('scripts.view_details', (tester) async {
    harness.resetState();
    await harness.boot(tester);
    await harness.dismissWizard(tester);
    await registry.runFor('scripts.view_details')!(tester, harness.driver);
    await tester.pump(const Duration(seconds: 11));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('profile.open_menu', (tester) async {
    harness.resetState();
    await harness.boot(tester);
    await harness.dismissWizard(tester);
    await registry.runFor('profile.open_menu')!(tester, harness.driver);
    await tester.pump(const Duration(seconds: 11));
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('coverage report', (tester) async {
    final cov = FlowCatalog.coverageReport(registry);
    // ignore: avoid_print
    print('FAST_SMOKE: ${cov.implemented}/${cov.total} flows registered.');
  }, timeout: const Timeout(Duration(seconds: 10)));
}
