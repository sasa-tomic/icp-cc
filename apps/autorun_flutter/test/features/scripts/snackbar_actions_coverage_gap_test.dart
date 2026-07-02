import 'package:flutter_test/flutter_test.dart';

// WU-2 / WU-3 — coverage gap for the "Run" and "Publish" SnackBarActions.
//
// The download-success snackbar offers a "Run" action (scripts_screen.dart
// ~L436) and the create-success snackbar offers a "Publish" action (~L576).
// Neither has a dedicated widget test because ScriptsScreen has no dependency-
// injection seam for the collaborators the snackbar paths depend on:
//
//   - `ScriptController _controller` is constructed internally from the
//     `ScriptRepository.instance` singleton (scripts_screen.dart L97).
//   - `MarketplaceOpenApiService _marketplaceService` is `final` and constructed
//     in-place (L59), issuing real HTTP in `_downloadScript`.
//   - The snackbars live inside private methods (`_downloadScript`,
//     `_showCreateSheet`, `_publishToMarketplace`) that also touch
//     `DownloadHistoryService`, `OnboardingProgressService`, and
//     `ProfileScope.of`.
//
// Driving these paths end-to-end would require either (a) a production-code
// refactor that injects these collaborators (out of scope for the test swarm)
// or (b) a mock-heavy harness around singletons that gives false confidence
// and fights the project's "real services, fail-fast" testing rules
// (test/shared/AGENTS.md). Per the test-swarm brief, we therefore document the
// gap instead of shipping a brittle test.
//
// When ScriptsScreen gains injectable services, replace this file with real
// tests asserting: tapping "Run" opens the execution sheet for the downloaded
// script; tapping "Publish" opens QuickUploadDialog (or the registration
// wizard when no account exists).

void main() {
  test('WU-2/WU-3 snackbar actions: no DI seam in ScriptsScreen (tracked gap)',
      skip: 'Awaiting ScriptsScreen dependency-injection refactor — see comment '
          'at top of this file.',
      () {});
}
