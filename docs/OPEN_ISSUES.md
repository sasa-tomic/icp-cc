# Open Issues — icp-cc

> **Living backlog of every known issue.** Anything surfaced by a sweep,
> UX review, e2e red, security audit, or human report lives here until it's
> resolved. Source of truth for "what's broken / pending / blocked" — replaces
> the scattered per-spec seed lists.
>
> Linked from `AGENTS.md`. **Update on close.**
>
> Statuses: 🔴 OPEN • 🟡 IN-PROGRESS • 🟢 RESOLVED • ⚪ DEFERRED (with reason)

---

## Critical / Blockers

*(none currently)*

---

## High severity

### WEB-1 — Flutter Web e2e via Playwright blocked on semantics enablement

- **Status**: 🔴 OPEN
- **Surfaced**: 2026-07-17 (`docs/specs/2026-07-17-e2e-completion-and-ux-sweep.md` Phase C)
- **Severity**: HIGH (blocks real-app web e2e coverage)
- **Owner**: future Flutter upgrade / harness rework

**Problem.** The Playwright-against-built-web approach (build the bundle,
serve via `python -m http.server`, drive with Chromium) works for *booting*
the app — `flt-glass-pane` mounts, `flt-scene-host` has a canvas child,
`flutterCanvasKit` is loaded. But the Flutter Web engine's a11y semantics
tree (`flt-semantics` element) is **never enabled**, so Playwright has no
DOM to assert against — every assertion can only see a generic canvas.

**What I tried (all failed on Flutter 3.38.3 / canvaskit):**
1. `SystemChannels.accessibility.send(['enableSemantics', null])` — Dart-side
   flag set, no DOM effect.
2. `SemanticsService.announce(...)` — public Flutter API that the docs imply
   forces semantics on; no DOM effect.
3. Playwright `page.keyboard.press('Tab')` — the SemanticsEnabler listens for
   Tab keydown at the window level; no DOM effect (likely because the
   canvaskit `flt-glass-pane` shadow-DOM intercepts/absorbs the key).
4. Dispatching a synthetic `KeyboardEvent('keydown', {key:'Tab'})` on
   `window` directly — same: no effect.
5. `--web-renderer html` — flag was removed in Flutter 3.38 (canvaskit only).
6. `--wasm` — flutter_secure_storage_web blocks Wasm (`dart:js_util` +
   `package:js/js.dart` forbidden in Wasm).

**Working theory.** Flutter Web's `SemanticsEnabler` only honours its own
internal screen-reader detection (via `navigator.userAgent` matching known
AT tools). Headless Chromium's UA doesn't match. There is no public JS API
to override this; the engine internals are not exposed on `window._flutter`.

**Hook in place.** `lib/main.dart` keeps a `FLUTTER_WEB_FORCE_SEMANTICS`
dart-define that calls `SemanticsService.announce()` post-frame. It's a
no-op today but becomes effective the moment Flutter Web ships working
programmatic semantics enablement — no further app change needed.

**Workarounds for now.**
- **Web Tier 1 (widget tests via `flutter test -d chrome`)** is the only
  real-app web coverage today. Extends cleanly to ~30 Surface.web flows
  (browse, search, filter, settings, vault crypto, profile via localStorage,
  onboarding wizard). HTTP works (real backend), plugins need substrate
  fakes (`SharedPreferences.setMockInitialValues`, etc.). The current
  `suite_web_smoke_test.dart` only asserts the contract compiles; needs
  extending.
- **Chrome DevTools Protocol** `Accessibility.getFullAXTree` returns ~11
  generic nodes (just the RootWebArea + canvas wrappers) — too sparse to
  assert on.
- **Manual web UX review** still works — a human opens the URL and looks.

**Revisit when:** Flutter ships an upgrade that exposes a working
`enableSemantics()` JS API, OR `flutter drive` web is unblocked (currently
broken by `<invalid>` exhaustiveness in `cupertino/colors.dart:1024` +
`material/tooltip.dart:827`).

---

### E2E-1 — `just e2e-one <flow-id>` cannot target individual flows inside the marketplace suite

- **Status**: 🟡 IN-PROGRESS (Phase B of the 2026-07-17 plan will fold the
  marketplace suite into keyring-less, after which `e2e-one` works for all
  flows).
- **Severity**: MEDIUM (dev-loop friction)
- **Surfaced**: 2026-07-17 (`justfile` audit)

`just e2e-one <flow> [suite]` only accepts `keyring-less | marketplace |
mock-keyring` as the suite arg. After Phase B folds marketplace into
keyring-less, this becomes a non-issue.

---

## Medium severity

*(none currently)*

---

## Low severity / Polish

### UX-N1 — Visual UX review pending (vision MCP unavailable in this environment)

- **Status**: 🔴 OPEN
- **Severity**: LOW (process issue, not product issue)
- **Surfaced**: 2026-07-17

The `zai-vision_analyze_image` MCP timed out for every screenshot during
this session, blocking the planned per-screen visual UX review. Code-level
review was done instead (no AI slop / dead routes / placeholder text found
in `lib/`). To close this: re-run the UX review once vision is available,
and screenshot every screen in `docs/specs/ux_screenshots/e2e/`.

---

## Resolved (kept for the historical record)

### F1–F8 — Seed defect list from the predecessor plan (Phase 3)

- **Status**: 🟢 RESOLVED (2026-07-15, commit `9b37bb46` + `aae008ae`)
- **Source**: `docs/specs/2026-07-15-e2e-harness-and-ux.md` §3 (Phase 3)
- F1 `/recovery` dead route → wired
- F2 Vault screens not reachable → wired via profile menu Vault tile
- F3 `_duplicateScript` View SnackBar action no-op → implemented
- F4 Passkey device name hardcoded "This Device" → derived
- F5 Profile rename/delete promised but missing in UI → wired
- F6 dapp vote flow HTTP 530 → environmental (canned-bridge test)
- F7 Dual profile-creation paths → DRY'd to UnifiedSetupWizard
- F8 Stale doc secp256k1 stubbed on web → reconciled

### E2E-RED-MARKETPLACE + E2E-RED-MOCK-KEYRING — 2 of 3 desktop suites silently RED

- **Status**: 🟢 RESOLVED (2026-07-17, commit `eb9cbdfa`)
- **Source**: `docs/specs/2026-07-17-e2e-completion-and-ux-sweep.md` Phase A
- Root causes + fixes documented in commit message.

---

## Maintenance

This file is updated:
- On every issue discovery (add a row in the right severity bucket).
- On every issue close (move from open bucket to "Resolved" with commit ref).
- At session end (re-prioritize, surface blockers, link to plans).

**Do not** let this file grow stale — open issues live here, closed ones go
to git history.
