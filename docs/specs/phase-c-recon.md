# Phase C — Web e2e harness (Tier A) Recon

- **Status:** complete
- **Date:** 2026-07-19
- **Author:** orchestrator-implementer (Phase C)

## Goal

Pivot 1 of `2026-07-19-e2e-and-ux-continuation.md` chooses two complementary
web e2e harnesses over chasing Flutter-Web a11y-semantics enablement
(WEB-1). Tier A is `flutter test -d chrome` widget tests with substrate
fakes at the smallest I/O boundary (HTTP + plugins); Tier B is Playwright
against the built bundle with `zai-vision` image assertions. This recon
covers Tier A.

## App boot path (Web surface)

`apps/autorun_flutter/lib/main.dart` — `KeypairApp` is a `StatefulWidget`
whose `initState` wires real controllers (no DI for these):

```
WidgetsFlutterBinding.ensureInitialized()
setupServiceLocator()                  // GetIt: registers IcpayService only
ScriptTemplates.ensureInitialized()    // rootBundle assets (works on Web)
runApp(KeypairApp())
  └─ _KeypairAppState.initState
     ├─ ProfileController(MarketplaceOpenApiService())  // singleton svc
     ├─ AccountController(MarketplaceOpenApiService(), profileController)
     ├─ unawaited(_profileController.ensureLoaded())    // async
     ├─ _loadThemePreference()                          // SharedPreferences
     └─ _initDeepLinks()                                // returns early on Web
```

`MainHomePage._checkAndShowOnboarding` (post-frame callback):
1. `profileController.ensureLoaded()` → reads `ProfileRepository._docStore`
   → on Web = `WebJsonStore` → `SharedPreferences` (localStorage).
2. `scriptController.ensureLoaded()` → `ScriptRepository.instance._docStore`
   → same `WebJsonStore` path.
3. `showFirstRunSetupIfNeeded` → reads pref `first_run_wizard_dismissed`
   → if no profile + not dismissed → present `UnifiedSetupWizard`.

## I/O substrate required

| Boundary | What the app uses | Web test mechanism |
|----------|-------------------|--------------------|
| HTTP / marketplace | `MarketplaceOpenApiService()` singleton, `package:http` | Singleton has `overrideHttpClient(http.Client)` seam → inject `MockClient` from `package:http/testing.dart`. |
| HTTP / vault + passkey | `PasskeyService()` singleton, `package:http` | Same `overrideHttpClient` seam on the singleton. |
| HTTP / ICPay | `IcpayService` (registered in GetIt) | Not needed for Tier-A flows; ICPay is only touched on Buy checkout. |
| HTTP / Candid | `CandidService` (constructed on demand) | Not exercised in the Tier-A flow set; deferred. |
| SharedPreferences | `SharedPreferences.getInstance()` | SDK mock: `SharedPreferences.setMockInitialValues({})`. |
| Secure storage | `FlutterSecureStorage` (Web → IndexedDB + AES) | SDK mock: `FlutterSecureStorage.setMockInitialValues({})`. |
| path_provider | `getApplicationSupportDirectory()` | NOT REACHED on Web. `lib/services/json_store.dart` does `export 'file_json_store.dart' if (dart.library.html) 'web_json_store.dart';` — the file/path_provider branch is swapped out at compile time. |
| package_info | `PackageInfo.fromPlatform()` | `PackageInfo.setMockInitialValues(...)` for `settings.version_display`. |
| WebAuthn / passkeys | `passkeys` plugin | NOT exercised in Tier-A flow set; `PasskeyPlatform.isSupported` is `true` on Web but real WebAuthn needs an authenticator we cannot drive in `flutter test -d chrome`. The passkey list/register flows are deferred to Tier B / real browser. |

**Note on HttpOverrides**: the task brief suggested `HttpOverrides.global`
for the HTTP substrate. That approach is `dart:io`-only and **does not work
on Web**. The app already provides the proper Web-compatible seam
(`overrideHttpClient(client)` on both singletons), so the substrate uses
that — same effect, no `dart:io` dependency.

## Backend contract (captured 2026-07-19)

Backend running at `:35735`. Captured via curl:

- `GET /api/v1/health` → `{"success":true,"message":"ICP Marketplace API is running","environment":"production","timestamp":"..."}`
- `POST /api/v1/scripts/search` body `{sortBy,order,limit,offset}` → envelope `{success:true, data:{scripts:[3 items], total:3, hasMore:false, limit, offset}}`.
- The 3 seeded scripts: `Interactive Counter` (`id=interactive-counter`, price 4.99, paid), `ICP Balance Reader` (`id=icp-balance-reader`, price 1.99, paid), `Hello IC Starter` (`id=hello-ic-starter`, price 0.0, free).
- `GET /api/v1/scripts/categories` → `{"success":true,"data":{"categories":["data-processing","utility"]}}`.
- `GET /api/v1/scripts/{id}` → envelope; paid scripts have `bundle:null`, free scripts include the full bundle.
- `GET /api/v1/marketplace-stats` → `{success:true, data:{totalScripts:3, totalDownloads:426, averageRating:4.5, timestamp}}`.

The substrate mock server will mirror these envelopes exactly.

## Cross-surface sharing approach

The desktop `suite_keyring_less_test.dart` already factors every flow as a
`FlowRun` closure registered in a `FlowRegistry`. The bodies are largely
surface-agnostic: they tap by `find.text`, `find.byType`, `find.byTooltip` —
all of which work on Web canvaskit.

What DOESN'T work on Web (without a real browser):
- `LogicalKeyboardKey` shortcuts (Alt+digit, N, /, R, etc.) — `flutter test
  -d chrome` does deliver `sendKeyEvent`, but the desktop-only `DesktopShortcuts`
  widget gates on `defaultTargetPlatform != mobile`, which on Web canvaskit
  evaluates to whatever the host says (Chromium Linux → `linux`). These are
  testable in principle but deferred from Tier A's 5-flow PoC.
- Real WebAuthn flows (passkey register/authenticate) — need a real
  authenticator; deferred to Tier B.

The cleanest DRY approach: factor the cross-surface flow bodies (those
identical on both surfaces) into a new `integration_test/e2e/flow_implementations.dart`
library exporting `FlowRun` functions. The desktop suite currently
in-lines these as closures in a chained `..register` block; for Phase C
Tier A, we will only ADD the library with the new web flows (not refactor
the desktop suite — that's a separate DRY pass). The web suite imports the
library and registers each `FlowRun` against its own registry. The library
is structured so the desktop suite can later swap its inlined bodies for
the library versions one flow at a time without breaking anything.

## Web boot idiom (substrate-aware)

The existing `E2EDriver(surface: web).boot(tester)` deliberately avoids
`runAsync` because no plugins are registered (Tier 1). With substrate
fakes installed, plugins ARE registered, so the Web boot CAN use
`runAsync` to let real async work (HTTP, prefs, secure-storage round-trip)
complete. We add a substrate-aware boot helper in the substrate library
rather than mutating `E2EDriver` — the Tier 1 smoke still uses the
no-substrate boot, and Tier A is opt-in.

## Confidence

- Architecture: **9/10** (substrate seams already exist in the app).
- 5-8 flows green: **8/10** (Web boot + 5 flows is the PoC bar; marketplace
  HTTP via MockClient is the highest-risk piece).
- Tier B (Playwright): **deferred** — would only start after Tier A is green
  and `just e2e-web` passes.
