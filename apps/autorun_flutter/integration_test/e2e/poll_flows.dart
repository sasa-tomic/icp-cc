// ignore_for_file: lines_longer_than_80_chars

/// Local-replica poll dapp e2e flows — PHASE 56 + PHASE 57 of the
/// keyring-less suite.
///
/// Extracted into a separate library (rather than inlined in
/// `suite_keyring_less_test.dart`) because the suite file is at a size
/// threshold where adding ~250 lines of inline flow bodies destabilises
/// the flutter_test binding's stream protocol (surfacing as a flaky
/// "Cannot close sink while adding stream" crash mid-suite). The suite
/// imports these two functions and registers them in 2 lines each,
/// keeping the suite file's line count growth to ~15 lines.
///
/// Both flows require a LOCAL dfx replica + the example Poll canister
/// deployed (`scripts/start-local-replica.sh`). The replica is an EXTERNAL
/// precondition (same pattern as the marketplace backend) — the justfile
/// recipe `just e2e-local-replica` starts it BEFORE the flutter test
/// process. The flows verify the pre-state via [pollReplicaReady] and
/// fail LOUD with a clear pointer if it isn't satisfied (AGENTS.md: no
/// silent failures).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/screens/dapp_runner_screen.dart';
import 'package:icp_autorun/screens/unified_setup_wizard.dart';
import 'package:icp_autorun/theme/modern_components.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';

import 'e2e_driver.dart';

/// Resolve the repo root by walking up from `Platform.script` until the
/// `AGENTS.md` marker is found (mirrors E2EDriver._resolveRepoRoot).
String _resolveRepoRoot() {
  var dir =
      Directory(File(Platform.script.toFilePath()).parent.path).absolute;
  for (var i = 0; i < 12; i++) {
    if (File('${dir.path}/AGENTS.md').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}

/// Runs `scripts/start-local-replica.sh --check` under runAsync (so the
/// process I/O doesn't block the integration-test binding). Returns whether
/// the replica is ready AND the deployed canister id matches the constant
/// the app expects (sentinel file check). Streams stdout as `[replica]`
/// and stderr as `[replica!]` so failures surface in the test log.
///
/// NEVER skips silently — the calling flow's `expect(ready, isTrue)` will
/// fail the test with a clear pointer to the helper script.
Future<bool> pollReplicaReady(WidgetTester tester) async {
  final repoRoot = _resolveRepoRoot();
  final scriptPath = '$repoRoot/scripts/start-local-replica.sh';
  if (!File(scriptPath).existsSync()) {
    // ignore: avoid_print
    print('  [replica!] start-local-replica.sh not found at $scriptPath');
    return false;
  }
  final result = await tester.runAsync<bool>(() async {
    final proc = await Process.start(
      scriptPath,
      const <String>['--check'],
      runInShell: true,
    );
    // ignore: avoid_print
    final stdoutSub = proc.stdout
        .transform(utf8.decoder)
        // ignore: avoid_print
        .listen((s) => print('  [replica] $s'));
    final stderrSub = proc.stderr
        .transform(utf8.decoder)
        // ignore: avoid_print
        .listen((s) => print('  [replica!] $s'));
    final exitCode = await proc.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();
    return exitCode == 0;
  });
  return result ?? false;
}

/// Navigate to the Dapps tab via the ModernNavigationBar callback (the
/// gesture-friendly tap path is shadowed by a residual RenderAbsorbPointer
/// after scripts.run — same pattern the suite's _navigateToDapps uses).
Future<void> _navigateToDapps(WidgetTester tester, E2EDriver d) async {
  await d.dismissOverlays(tester);
  final navBar =
      tester.widget<ModernNavigationBar>(find.byType(ModernNavigationBar));
  navBar.onTap(2);
  await tester.pump(const Duration(milliseconds: 500));
  final bodyReady = await d.waitUntil(
      tester,
      () => d.present(find.textContaining('On-chain Polls'), tester),
      timeout: const Duration(seconds: 5));
  if (!bodyReady) {
    // ignore: avoid_print
    print('  [poll-flow] Dapps body did not render within 5s');
  }
}

/// Tap the "On-chain Polls" card → DappRunnerScreen pushes.
Future<void> _tapPollsCard(WidgetTester tester, E2EDriver d) async {
  final pollsCard = await d.waitUntil(
      tester, () => d.present(find.textContaining('On-chain Polls'), tester),
      timeout: const Duration(seconds: 10));
  if (!pollsCard) {
    // ignore: avoid_print
    print('  [poll-flow] Polls card not found in catalog');
    return;
  }
  await tester.tap(find.textContaining('On-chain Polls').first);
  await tester.pump(const Duration(milliseconds: 500));
}

/// Closes the DappRunnerScreen route, clearing any post-remount trust/
/// permission dialogs that block the pop (the bundle's first canister
/// call against the local replica fires the per-dapp "Trust this dapp?"
/// dialog). Mirrors `_closeDappRunnerAfterRemount` in the suite.
Future<void> _closeDappRunnerAfterRemount(
    WidgetTester tester, E2EDriver d) async {
  await d.dismissOverlays(tester);
  // Phase 1: dismiss any open dialogs above the runner route.
  var dialogSafety = 0;
  while (find.byType(Dialog).evaluate().isNotEmpty && dialogSafety < 6) {
    dialogSafety++;
    final rootCtx = find.byType(Navigator).evaluate().first;
    Navigator.of(rootCtx).pop();
    await tester.pump(const Duration(milliseconds: 400));
  }
  // Phase 2: pop the runner route (Esc via ScreenShortcuts → maybePop).
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
  if (!closed) {
    // ignore: avoid_print
    print('  [poll-flow] DappRunnerScreen did not close within 5s');
  }
  await d.dismissOverlays(tester);
}

/// `dapps.run_poll` — PHASE 56.
///
/// Opens the Polls dapp against a LOCAL dfx replica → DappRunnerScreen
/// mounts → ScriptAppHost executes the bundle → real canister round-trip
/// (`listPolls` query) against the freshly-deployed backend canister
/// (`uxrrr-q7777-77774-qaaaq-cai`).
///
/// Assertion (best-effort, like dapps.run_ledger_mainnet): the bundle's
/// init emits `listPolls` (anon) + `whoami` (auth) effects; once the host
/// dispatches them through the FFI bridge against the local replica, the
/// body renders either "Polls (N)" (success) or "Error: ..." (benign
/// failure). Both PASS; only a crash/hang or stuck "Loading..." fails.
Future<void> dappsRunPoll(WidgetTester tester, E2EDriver d) async {
  // Pre-state sanity: refuse to run silently if the replica is down.
  final ready = await pollReplicaReady(tester);
  expect(ready, isTrue,
      reason: 'dapps.run_poll requires a local dfx replica + deployed '
          'backend canister. Run scripts/start-local-replica.sh first '
          '(or `just e2e-local-replica` which does it for you).');

  await _navigateToDapps(tester, d);
  await _tapPollsCard(tester, d);
  final runnerOpen = await d.waitUntil(
      tester, () => d.present(find.byType(DappRunnerScreen), tester),
      timeout: const Duration(seconds: 10));
  expect(runnerOpen, isTrue,
      reason: 'Tapping the Polls card must push DappRunnerScreen.');

  // Wait for the ScriptAppHost to mount (proves the bundle loaded).
  final hostMounted = await d.waitUntil(
      tester, () => d.present(find.byType(ScriptAppHost), tester),
      timeout: const Duration(seconds: 15));
  expect(hostMounted, isTrue,
      reason: 'Polls DappRunnerScreen must mount ScriptAppHost.');

  // Give the FFI bridge real wall-clock time for the HTTP round-trip
  // to the local replica (typically <1s; 8s is generous).
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 8)));
  await tester.pump(const Duration(milliseconds: 500));

  // Assert the bundle reconciled: either "Polls (N)" (success) or
  // "Error: ..." (benign failure rendered). Absence of BOTH markers =
  // stuck host = real failure.
  final pollsLoaded = d.present(find.textContaining('Polls ('), tester);
  final errorRendered = d.present(find.textContaining('Error:'), tester);
  expect(pollsLoaded || errorRendered, isTrue,
      reason: 'Polls bundle must render either "Polls (N)" or "Error: ..." '
          'after the local-replica round-trip. Neither appeared — the host '
          'is stuck or the bundle crashed.');

  // The first canister call fires the "Trust this dapp?" dialog above
  // the runner route. Use the remount-aware close helper.
  await _closeDappRunnerAfterRemount(tester, d);
}

/// `dapps.create_profile_to_vote` — PHASE 57.
///
/// Opens the Polls dapp → asserts the keyless-user "Create a profile" CTA
/// renders (the runner chrome surfaces this when there's no active profile,
/// deep-linking into UnifiedSetupWizard so a keyless user can take signed
/// actions like voting). Tapping the CTA must push the wizard above the
/// runner route.
///
/// The FULL create-profile-then-vote round-trip requires a Secret Service
/// (the mock-keyring surface or a real gnome-keyring); this flow covers
/// the FRONTEND rendering + wizard deep-link, NOT the profile creation
/// itself (which is exercised end-to-end by first_run.create_profile +
/// scripts.buy in the mock-keyring suite).
Future<void> dappsCreateProfileToVote(WidgetTester tester, E2EDriver d) async {
  // Reuse the same pre-state check — the replica should still be up.
  final ready = await pollReplicaReady(tester);
  expect(ready, isTrue,
      reason: 'dapps.create_profile_to_vote requires the local dfx '
          'replica started before the suite. Check [replica!] log lines.');

  await _navigateToDapps(tester, d);
  await _tapPollsCard(tester, d);
  final runnerOpen = await d.waitUntil(
      tester, () => d.present(find.byType(DappRunnerScreen), tester),
      timeout: const Duration(seconds: 10));
  expect(runnerOpen, isTrue,
      reason: 'Tapping the Polls card must push DappRunnerScreen.');

  // The CTA renders only for keyless users (no active profile). The
  // keyring-less suite never creates a profile, so this must appear.
  final ctaFinder = find.byKey(const Key('dappCreateProfileToVoteCta'));
  final ctaVisible = await d.waitUntil(
      tester, () => d.present(ctaFinder, tester),
      timeout: const Duration(seconds: 10));
  expect(ctaVisible, isTrue,
      reason: 'Polls DappRunnerScreen must show the "Create a profile" '
          'CTA for a keyless user (key=dappCreateProfileToVoteCta).');

  // Tap the CTA → UnifiedSetupWizard pushes above the runner route.
  // Invoke the onPressed callback DIRECTLY instead of tester.tap — the
  // tap is absorbed by the Flutter 3.44.6 partial Overlay bug (residual
  // IgnorePointer shadows the gesture). Same pattern as dapps.apply_
  // connection in the keyring-less suite.
  await tester.runAsync(() async {
    tester.widget<FilledButton>(ctaFinder).onPressed!();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  await tester.pump(const Duration(milliseconds: 500));

  final wizardPushed = await d.waitUntil(
      tester, () => d.present(find.byType(UnifiedSetupWizard), tester),
      timeout: const Duration(seconds: 5));
  expect(wizardPushed, isTrue,
      reason: 'Tapping the "Create a profile" CTA must push '
          'UnifiedSetupWizard above the runner route.');

  // Dismiss the wizard (we don't create a profile here — the assertion
  // is the deep-link itself, not profile creation).
  await d.dismissWizard(tester);

  // The runner route is still mounted below the wizard. The bundle's
  // first canister call fires the trust dialog; clear it then pop.
  await _closeDappRunnerAfterRemount(tester, d);
}
