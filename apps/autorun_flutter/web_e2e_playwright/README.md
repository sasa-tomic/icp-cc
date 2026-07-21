# Phase C Tier B — Playwright Web e2e harness

Real-browser web e2e for the built Flutter Web bundle. Complements the
widget-test harness (`test/e2e_web/suite_web_flows_test.dart`, Tier A) by
exercising the REAL canvaskit + Web platform code paths (Web pure-Dart crypto
in `lib/rust/native_bridge_web.dart`, IndexedDB secure storage, real
`path_provider_web`, etc.).

## Two harnesses in this directory

### Boot smoke (`specs/web_smoke.spec.ts`) — Tier B

Tier A (`flutter test -d chrome` + substrate fakes) is fast and DRY-shares
flow bodies with the desktop suite. But its test code compiles for the Dart
VM (chrome is just the renderer), so the conditional-export branches pick
the IO impls (`file_json_store.dart`, `connectivity_service_io.dart`) instead
of the Web ones. Real Web platform code is never exercised.

Tier B closes the gap by driving the REAL built bundle (canvaskit + all Web
platform code) via Playwright. The catch: Flutter Web's a11y tree is NOT
auto-enabled in headless Chromium (see `docs/OPEN_ISSUES.md` #WEB-1 historical
investigation), so DOM assertions are unavailable. Workaround: visual
assertions via the `zai-vision` MCP — each spec navigates + screenshots, then
a verifier role sends the screenshot to `zai-vision_analyze_image` for
layout/visibility checks.

### Passkey round-trip (`specs/passkey.spec.ts`) — WEB-1 RESOLUTION

The WEB-1 resolution harness. Sidesteps the Flutter a11y tree entirely by
using a Dart probe entrypoint
(`tool/web_probe_passkey_main.dart` — mirrors the existing R-3 / R-3b probe
pattern) that drives the REAL production passkey code paths and publishes
its result to `document.title`. The probe + Playwright 1.61+'s modern
`browserContext.credentials` virtual authenticator together exercise the
full register/start → WebAuthn → register/finish → list round-trip against
the REAL backend.

Run via `just e2e-web-passkey` (brings up a dedicated backend with the right
WebAuthn RP origin, builds the probe bundle, serves it, runs Playwright).

## Setup (one-time)

```bash
cd apps/autorun_flutter/web_e2e_playwright
npm install
npm run install-browsers   # Playwright Chromium
```

## Run

### Boot smoke (Tier B)

```bash
# 1. Start the dev backend (assumed by every e2e recipe).
just api-dev-up

# 2. Build + serve the Flutter Web bundle (bakes the live backend endpoint in).
npm run build     # produces ../build/web
npm run serve &   # serves on http://localhost:8099

# 3. Run Playwright (sequential — one Chromium, screenshots are cheap).
npm test

# 4. Inspect screenshots:
ls docs/specs/ux_screenshots/e2e_web_playwright/
```

### Passkey round-trip (WEB-1)

```bash
# One-shot — brings up its own dedicated backend, builds, runs, tears down.
just e2e-web-passkey
```

To run against a different base URL (e.g. a CI-staged bundle):

```bash
BASE_URL=https://staging.example.com/ npm test
```

## Vision assertions (boot smoke only)

The boot smoke specs themselves do not call `zai-vision` directly (the
harness is language-mixed — Playwright/Node here, the vision MCP is invoked
from the orchestrator-verifier role). The contract is:

1. Playwright writes screenshots to
   `docs/specs/ux_screenshots/e2e_web_playwright/NN_*.png`.
2. The verifier sends each screenshot to `zai-vision_analyze_image` with a
   prompt like *"Is this the ICP Autorun first-run wizard? Does it show the
   'Set up profile' CTA?"*
3. Vision returns a yes/no + reasoning; the verifier codifies red/green.

The passkey spec does NOT need vision assertions — the probe publishes a
structured JSON result that the spec asserts on directly.

## Current spec coverage

| Spec | What it proves |
|------|----------------|
| `web_smoke.spec.ts` — `01_boot.png` | The bundle mounts `flt-glass-pane` with non-trivial geometry (canvaskit initialised + first frame painted). |
| `web_smoke.spec.ts` — `02_wizard.png` | After the post-frame ensureLoaded chain, the first-run wizard is visually present. |
| `passkey.spec.ts` — positive | Full passkey registration round-trip against the REAL backend: Ed25519 keypair → signed account registration → WebAuthn `navigator.credentials.create` (via Playwright virtual authenticator) → `register/finish` → `list_passkeys` backend verification. |
| `passkey.spec.ts` — negative | NO virtual authenticator → `navigator.credentials.create` blocks → probe's 20s timeout fires → loud failure with WebAuthn error class. |

Add specs by dropping new `.spec.ts` files in `specs/`. Boot-smoke specs
navigate → wait → screenshot → minimal DOM sanity (geometry only, since
Flutter semantics aren't enabled). Passkey-style specs drive a probe
entrypoint and read the JSON result from `document.title`.
