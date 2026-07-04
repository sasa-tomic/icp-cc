// ignore_for_file: invalid_use_of_visible_for_testing_member

/// Shared test harness for `test/features/marketplace/*`.
///
/// Mirrors `test/features/scripts/_scripts_test_harness.dart`. Owns the two
/// `MaterialApp(...)` wrappers that ~12 marketplace widget tests used to
/// rebuild by hand — a plain `MaterialApp` → `Scaffold` for leaf-widget
/// tests (`MarketplaceStatsBanner`, diff viewer) and a `MaterialApp` →
/// `Builder` → button-tap opener for the `ScriptDetailsDialog` reviews /
/// versions tests — so each test stays focused on behaviour, not
/// boilerplate. Leading-underscore filename keeps the runner from treating
/// this as a test file.
///
/// The wrapper is intentionally a bare `MaterialApp` (no `theme`) to match
/// the scripts harness and to preserve every existing assertion exactly;
/// the app's `AppDesignSystem.lightTheme` is not depended on by any widget
/// under test here, and adding it would risk silently shifting layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside a `MaterialApp` → `Scaffold` (the wrap every
/// marketplace leaf-widget test needs).
///
/// Direct analogue of `pumpInScaffold` from the scripts harness. Pass
/// [scaffold: false] for the rare widget that ships its own `Scaffold` (e.g.
/// a full screen). The caller owns the post-pump settle cadence: tests that
/// need `pumpAndSettle` call it explicitly, matching the prior hand-rolled
/// code (some intentionally don't settle, to inspect mid-frame state).
Future<void> pumpMarketplaceWidget(
  WidgetTester tester,
  Widget child, {
  bool scaffold = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(home: scaffold ? Scaffold(body: child) : child),
  );
}

/// Pumps a host screen containing a single "Open" button, then drives the
/// tap that invokes [dialogBuilder] via the root `showDialog`. Used by the
/// `ScriptDetailsDialog` reviews + versions tests, which both used to
/// rebuild the
/// `MaterialApp(home: Builder(builder: (ctx) => Scaffold(body: Center(
/// child: ElevatedButton(onPressed: () => showDialog(ctx: ctx, ...)))))`
/// boilerplate by hand.
///
/// The caller owns the `MarketplaceOpenApiService` HTTP mock setup (which
/// must happen *before* this call so the dialog's first fetch sees the
/// stubbed client) and any post-dialog interaction / settle cadence.
Future<void> pumpDetailsDialog(
  WidgetTester tester, {
  required WidgetBuilder dialogBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: dialogBuilder),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
