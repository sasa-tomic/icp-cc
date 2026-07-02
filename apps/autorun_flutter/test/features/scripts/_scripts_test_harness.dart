// ignore_for_file: invalid_use_of_visible_for_testing_member

/// Shared test harness for `test/features/scripts/*`.
///
/// Owns the three `MaterialApp(...)` wrappers that ~30 scripts tests used to
/// rebuild by hand, so widget tests stay focused on behaviour instead of
/// boilerplate. Leading-underscore filename keeps the runner from treating this
/// as a test file.
///
/// The TQ-1 DI seam on [ScriptsScreen] (`marketplaceService` / `controller`)
/// is wired in here: [pumpScriptsScreen] defaults the marketplace to
/// [FakeMarketplaceOpenApi] so tests never hit the network.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';

import '../../shared/fake_connectivity_service.dart';
import 'fake_marketplace_open_api.dart';

export 'fake_marketplace_open_api.dart';
export '../../shared/fake_connectivity_service.dart';

/// Pumps a full [ScriptsScreen] inside the [MaterialApp] + [ConnectivityScope]
/// (+ optional [ProfileScope]) wrapper every scripts screen test needs.
///
/// Marketplace defaults to [FakeMarketplaceOpenApi] (no scripts, instant) so
/// tests are deterministic and offline. Pass [marketplaceService] to seed
/// scripts or to assert on download/search calls. [settle] defaults to the
/// 2s the old hand-rolled pumps used; drop it for sub-frame timing checks.
///
/// When [profileController] is supplied it wraps the *whole* [MaterialApp] —
/// not `home` — so that dialogs opened via the root Navigator (e.g.
/// [QuickUploadDialog], [AccountRegistrationPromptDialog]) inherit the scope.
Future<void> pumpScriptsScreen(
  WidgetTester tester, {
  ScriptController? controller,
  MarketplaceOpenApi? marketplaceService,
  ProfileController? profileController,
  Duration settle = const Duration(seconds: 2),
}) async {
  final scoped = ConnectivityScope(
    service: FakeConnectivityService(),
    child: ScriptsScreen(
      controller: controller,
      marketplaceService: marketplaceService ?? FakeMarketplaceOpenApi(),
    ),
  );
  final app = MaterialApp(home: scoped);
  await tester.pumpWidget(
    profileController == null
        ? app
        : ProfileScope(controller: profileController, child: app),
  );
  await tester.pump(settle);
}

/// Pumps [body] inside a bare [MaterialApp] → [Scaffold]. For widget / row /
/// dialog-trigger tests that don't need the full [ScriptsScreen] tree.
Future<void> pumpInScaffold(WidgetTester tester, Widget body) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
}

/// Pumps a [ScriptAppHost] for script-execution integration tests.
///
/// The caller supplies the [runtime] (e.g.
/// `ScriptAppRuntime(MockCanisterBridge())`); this helper only owns the host +
/// settle sequence so the only `MaterialApp` lives in the harness.
Future<void> pumpScriptApp(
  WidgetTester tester, {
  required ScriptAppRuntime runtime,
  required String bundle,
}) async {
  await tester.pumpWidget(
    MaterialApp(home: ScriptAppHost(runtime: runtime, script: bundle)),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Default model fixtures. Deterministic timestamps so tests don't depend on
// `DateTime.now()` and fail spuriously at day boundaries.
// ---------------------------------------------------------------------------

/// A local (non-marketplace) [ScriptRecord] with sensible defaults.
ScriptRecord aLocalScript({
  String id = 'local-1',
  String title = 'My Local Script',
  String emoji = '📜',
  String bundle = 'return 1',
  Map<String, Object?> metadata = const {},
}) {
  return ScriptRecord(
    id: id,
    title: title,
    emoji: emoji,
    bundle: bundle,
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 1),
    metadata: metadata,
  );
}

/// A local [ScriptRecord] that originated from the marketplace (has
/// `marketplace_id` metadata → `isFromMarketplace == true`).
ScriptRecord aDownloadedMarketplaceScript({
  String id = 'mp-local-1',
  String title = 'Downloaded Script',
  String bundle = 'return 2',
  String marketplaceId = 'mp-123',
}) {
  return ScriptRecord(
    id: id,
    title: title,
    bundle: bundle,
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 1),
    metadata: {'marketplace_id': marketplaceId},
  );
}

/// A marketplace listing, free by default (downloadable without payment).
MarketplaceScript aMarketplaceScript({
  String id = 'mp-1',
  String title = 'Marketplace Script',
  String category = 'Utilities',
  String authorName = 'Author',
  String bundle = 'return 3',
  double price = 0.0,
  String version = '1.0.0',
}) {
  return MarketplaceScript(
    id: id,
    title: title,
    description: 'A test marketplace script',
    category: category,
    authorName: authorName,
    price: price,
    bundle: bundle,
    version: version,
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 1),
  );
}
