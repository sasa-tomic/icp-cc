# Phase C Tier B — Playwright Web e2e harness

Real-browser web e2e for the built Flutter Web bundle. Complements the
widget-test harness (`test/e2e_web/suite_web_flows_test.dart`, Tier A) by
exercising the REAL canvaskit + Web platform code paths (Web pure-Dart crypto
in `lib/rust/native_bridge_web.dart`, IndexedDB secure storage, real
`path_provider_web`, etc.).

## Why two harnesses?

Tier A (`flutter test -d chrome` + substrate fakes) is fast and DRY-shares
flow bodies with the desktop suite. But its test code compiles for the Dart
VM (chrome is just the renderer), so the conditional-export branches pick
the IO impls (`file_json_store.dart`, `connectivity_service_io.dart`) instead
of the Web ones. Real Web platform code is never exercised.

Tier B closes the gap by driving the REAL built bundle (canvaskit + all Web
platform code) via Playwright. The catch: Flutter Web's a11y tree is NOT
auto-enabled in headless Chromium (see `docs/OPEN_ISSUES.md` #WEB-1), so DOM
assertions are unavailable. Workaround: visual assertions via the
`zai-vision` MCP — each spec navigates + screenshots, then a verifier role
sends the screenshot to `zai-vision_analyze_image` for layout/visibility
checks.

## Setup (one-time)

```bash
cd apps/autorun_flutter/web_e2e_playwright
npm install
npm run install-browsers   # Playwright Chromium
```

## Run

```bash
# 1. Start the dev backend (assumed by every e2e recipe).
just api-dev-up

# 2. Build + serve the Flutter Web bundle (bakes the live backend endpoint in).
npm run build     # produces ../build/web
npm run serve &   # serves on http://127.0.0.1:8099

# 3. Run Playwright (sequential — one Chromium, screenshots are cheap).
npm test

# 4. Inspect screenshots:
ls docs/specs/ux_screenshots/e2e_web_playwright/
```

To run against a different base URL (e.g. a CI-staged bundle):

```bash
BASE_URL=https://staging.example.com/ npm test
```

## Vision assertions

The specs themselves do not call `zai-vision` directly (the harness is
language-mixed — Playwright/Node here, the vision MCP is invoked from the
orchestrator-verifier role). The contract is:

1. Playwright writes screenshots to
   `docs/specs/ux_screenshots/e2e_web_playwright/NN_*.png`.
2. The verifier sends each screenshot to `zai-vision_analyze_image` with a
   prompt like *"Is this the ICP Autorun first-run wizard? Does it show the
   'Set up profile' CTA?"*
3. Vision returns a yes/no + reasoning; the verifier codifies red/green.

When Flutter ships working programmatic semantics enablement (`WEB-1`
resolution), the Playwright specs can swap vision-asserts for DOM-asserts
(`page.locator('flt-semantics').getByText(...)`) without further harness
changes.

## Current spec coverage

| Spec | What it proves |
|------|----------------|
| `01_boot.png` | The bundle mounts `flt-glass-pane` with non-trivial geometry (canvaskit initialised + first frame painted). |
| `02_wizard.png` | After the post-frame ensureLoaded chain, the first-run wizard is visually present. |

Add specs by dropping new `.spec.ts` files in `specs/`. Each one should
navigate → wait → screenshot → minimal DOM sanity (geometry only, since
semantics aren't enabled).
