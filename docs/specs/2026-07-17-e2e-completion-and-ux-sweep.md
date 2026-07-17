# 2026-07-17 — E2E Completion + Functional/Visual Sweep + Harness Re-architecture

- **Status:** IN PROGRESS
- **Predecessor:** `2026-07-15-e2e-harness-and-ux.md` (claimed 58/98 but **2 of 3 desktop suites are actually RED** as of 2026-07-17 — this plan supersedes the "58/98" claim with empirical ground truth).
- **Goal:** complete the unfinished predecessor work AND address the human's
  broader ask: find+fix all functional/visual issues, radically improve the e2e
  harness so it covers **ALL** flows on **BOTH** surfaces in **seconds**, and
  migrate every UI/UX verification test to the new harness. Persist open issues
  in `docs/OPEN_ISSUES.md` (the durable backlog), linked from `AGENTS.md`.

## §0. Empirical baseline (measured 2026-07-17)
| Check | Verdict | Evidence |
|-------|---------|----------|
| Backend API | ✅ UP | `:35735/api/v1/health` → 200; `marketplace-stats` → 3 scripts, 426 downloads |
| `libicp_core.so` (FFI) | ✅ built | `target/release/libicp_core.so` (13 MB) |
| `just e2e-desktop` PASS 1 (keyring-less) | ✅ 25 flows green | `flutter test -d linux` ~86s |
| `just e2e-desktop` PASS 2 (mock-keyring) | ❌ **RED** at PHASE 13 | `tester.pageBack()` finds no back button after `account.register_from_local` (`AccountProfileScreen=false`) |
| `just e2e-desktop` PASS 3 (marketplace) | ❌ **RED** at PHASE 12 | `E2EDriver.dismissOverlays()` fatal `hitTestWarning` tapping an off-stage `SnackBarAction` descendant |
| `just e2e-web` (Tier 1) | ⚠️ structure-only | one smoke test (`MaterialApp` mounted); **0 real flows** |
| Web Tier 2 (`flutter drive`) | ❌ BLOCKED on Flutter 3.38.3 framework bug | `<invalid>` exhaustiveness in `cupertino/colors.dart` |
| Total e2e wall-time (if all green) | ~5 min for 3 desktop boots | **not "seconds"** |
| Documented flow coverage claim | 58/98 | **actual: 25/98 green-passing** (PASS 1 only) |

**Honest restatement:** the predecessor's "58/98 flows covered" was the
*registration* count, not the *green-passing* count. As of 2026-07-17 the
real number is **25/98 green**. The two broken suites were silently red.

## §1. Problem statement (what the human asked, distilled)
1. **Find every functional + visual issue; fix them all.** Pre-existing issues
   first.
2. **Radically improve the e2e harness** so it:
   - runs in **seconds** (not 5 minutes),
   - covers **ALL supported user flows** (today: 25/98 green),
   - drives the **REAL app** on both surfaces (desktop + web),
   - becomes the home for **all UI/UX verification tests**.
3. **Reduce clicks**: optimize multi-step actions; keyboard-first.
4. **Cross-cutting**: quick dev cycle (seconds), loud/debuggable errors, tech
   debt reduction (DRY/KISS/YAGNI, single-source constants, timeouts, no silent
   errors), test-swarm quality review, alignment vs `HUMAN_EXPECTATIONS.md`,
   **no-mocks UX review** against the real running app.
5. **Persist** all open issues in `docs/OPEN_ISSUES.md`; update `AGENTS.md` to
   link to it. Plan for future runs.

## §2. Architecture — what changes from the predecessor

### 2.1 Web e2e via **Playwright-against-built-web** (NEW — bypasses `flutter drive`)
The predecessor hit a hard wall: Flutter 3.38.3 can't compile its own framework
to dartdevc for `integration_test`-on-web. **Solution: stop fighting `flutter
drive`.** Instead:

1. `flutter build web --profile` (with `--dart-define=PUBLIC_API_ENDPOINT`) → a
   real built bundle served by `python -m http.server` (or dhttpd).
2. **Playwright (Node.js) drives Chromium against `http://localhost:8080`.** It
   sees the real Canvas/WebGL-rendered Flutter app, sends real mouse/keyboard
   events, and reads the semantics tree (Flutter's a11y tree → ARIA DOM) for
   assertions.
3. Enable Flutter Web a11y semantics: `SemanticEnforcer` / `MediaQuery.accessibleNavigation` + the
   `--web-renderer html` flag if needed (autohtml is on by default in 3.x for
   better a11y). The semantics tree is **the testable DOM**.
4. The flow catalog (the same one used on desktop) is implemented as **TS/JS**
   Playwright scripts that drive the SAME UI the desktop `WidgetTester` flows
   drive. Each flow = one Playwright `test()` block.

**Why this is correct:**
- It's what real-world Flutter Web e2e looks like (the Flutter team's own
  presubmit uses a similar pattern).
- Bypasses the dartdevc bug entirely (we use the production dart2js/html renderer).
- Reuses the catalog as the contract: `flow_catalog.dart` is the SSOT for the
  flows; Playwright tests reference the same flow ids.
- Seconds-scale: Chromium cold-boot ~3s + per-test ~1s. **No `flutter drive`
  web cold-boot (~60s+).**

**Trade-off:** the Playwright tests are not Dart. We accept this — the catalog
is the contract, the language is an implementation detail. The desktop
`WidgetTester` flows stay Dart (because Flutter integration_test works on
desktop); the web flows are TS/Playwright (because Flutter's web integration_test
is broken). Both assert the same flow ids; the coverage matrix is unified.

### 2.2 Desktop consolidation (3 boots → **2 boots**)
Today PASS 1 (keyring-less) and PASS 3 (marketplace) are both keyring-less —
they differ only in which flows they run. **Merge them into one boot**. Result:
- **PASS 1 (keyring-less + marketplace)** — one boot, ~40 flows.
- **PASS 2 (mock-keyring)** — one boot, ~25 flows.

Total wall-time target: **< 3 min for full desktop**, **< 30 s for any single
flow** via `just e2e-one`.

### 2.3 Single-source flow catalog
`flow_catalog.dart` is already the SSOT. The Playwright web harness reads the
flow ids from a generated `flow_catalog.json` (one new codegen step) so the TS
tests can assert they cover the same set. Drift = CI failure.

### 2.4 Test-isolation discipline
The predecessor's flakes (PHASE 12 fatal hitTestWarning; PHASE 13 missing back
button) are **symptoms of state-bleed between flows**. Two hard rules:
- **Every flow closes what it opens.** No "the next flow will clean up" —
  because if the prior flow fails, the next inherits a broken stage.
- **`dismissOverlays` is a code smell**, not a helper. Each flow must know what
  it opened and close *that specific thing*. Remove the blanket helper; replace
  with explicit `tap(find.byTooltip('Close'))` / `sendKeyEvent(Escape)` /
  `pageBack()` at the precise point.

### 2.5 Quick dev cycle (the human's HARD requirement)
- `just e2e-one <flow-id>` → ONE flow, ONE boot, **< 30s** end-to-end.
- `just e2e-desktop-fast` → ONE boot, ALL keyring-less + marketplace flows,
  **< 90s**.
- `just e2e-web-fast` → ONE Playwright boot, **< 30s** for any tagged subset.
- `just e2e-coverage` → print the coverage matrix (gaps, surfaces, broken).

## §3. Phases & work units

### Phase A — FIX broken suites (RED → GREEN; TDD)
Each fix = RED test that reproduces → fix → GREEN.

- **A-1**: `dismissOverlays` fatal hitTestWarning. **Remove the helper**;
  replace all call sites with explicit close gestures. Each call site must say
  *what* it's closing (a `SnackBarAction`, a `Dialog`, a `PopupMenu`, …).
- **A-2**: mock-keyring PHASE 13 missing back button after
  `account.register_from_local`. Root-cause: the controller-direct call to
  `registerAccount` triggers a profile-menu listener that pops
  `AccountProfileScreen`. Fix: don't `pageBack()` if the screen already popped;
  or assert the screen is present before `pageBack()`; or restructure the flow
  so the UI itself drives registration (more honest e2e).
- **A-3**: Re-run all 3 suites green before moving on. Commit each fix.

### Phase B — Consolidate desktop suites (3 boots → 2)
- Merge `suite_marketplace_test.dart` into `suite_keyring_less_test.dart`. The
  marketplace flows run after the current keyring-less flows, sharing the same
  boot + state reset.
- Delete `suite_marketplace_test.dart` (KISS/YAGNI).
- Update `justfile`: `e2e-desktop` = 2 PASSes (keyring-less-with-marketplace,
  mock-keyring). `e2e-marketplace` alias kept.

### Phase C — NEW web e2e harness (Playwright-against-built-web)
- **C-1**: PoC. `just web-build-e2e` builds the web bundle with the local
  backend endpoint baked in. Serve via `dhttpd` or `python -m http.server` on
  :8080. Playwright script opens the page, waits for `MaterialApp` semantics,
  screenshots. Proves the substrate works.
- **C-2**: Codegen `flow_catalog.json` from `flow_catalog.dart` (one Dart
  script, run in CI). The Playwright tests import it and assert coverage.
- **C-3**: Implement web flows as Playwright TS tests under
  `test/e2e_web_playwright/`. Start with the Surface.web + Surface.both flows
  that don't need WebAuthn (browse, search, filter, details, settings, vault
  crypto, profile create via localStorage). Target: **30+ flows green**.
- **C-4**: `just e2e-web` runs the new harness. Deprecate `flutter test -d chrome`
  smoke (keep as a compile-check only).

### Phase D — Complete remaining desktop flows (target 90+/98)
The catalog lists 98 flows. After Phase A+B, ~25 are green. Add the missing
desktop-reachable flows (dapps runner, deeplink, canister inline client,
remaining settings/shortcuts). WebAuthn-only flows stay Surface.web.

### Phase E — UX review (REAL app, no mocks, both surfaces)
**Desktop**: boot the real Linux app under Xvfb, screenshot every screen +
every dialog/sheet. Reviewer subagent analyzes screenshots + DOM semantics.
**Web**: boot the built bundle under Playwright, screenshot + dump the a11y
tree. Reviewer subagent analyzes.

Both reviewers look for: AI slop, dead-end links, spinners that don't resolve,
inconsistent terminology, click-count for common paths, broken layouts,
missing keyboard affordances. **Each issue → row in `docs/OPEN_ISSUES.md`**.

### Phase F — Fix UX issues (TDD)
For each P0/P1 issue from Phase E: RED test (Playwright or widget) that
reproduces → fix → GREEN. Commit one per issue.

### Phase G — Click-reduction + keyboard-first UX
Audit each common path (create profile, browse → download → run a script, set
up vault). Reduce clicks. Encode the optimized path in the matching e2e flow.

### Phase H — Tech debt
- **TD-5**: `account_service.rs` is 2007 lines — split into logical units.
- **TD-9 (new)**: DRY duplicated harness helpers across the 3 desktop suites
  (now 2 after Phase B).
- **TD-10 (new)**: any silent error / `.ok()` / `if let Ok(..) {}` surfaced by
  the parallel code review (Phase E).

### Phase I — Persist open issues
- `docs/OPEN_ISSUES.md` becomes the durable backlog (replaces scattered
  per-spec seed lists). Every open issue lives here with severity, owner
  placeholder, and repro.
- `AGENTS.md` links to it. `TODO.md` references it.

### Phase J — Final verify + report
- `flutter analyze` clean.
- `just test` (full unit/widget suite) green.
- `just e2e` (desktop + web) green.
- Coverage matrix printed; gaps justified.
- TODO.md + plan updated; final report.

## §4. Confidence
- Architecture (Playwright-web + 2-boot desktop + flow catalog as SSOT):
  **9/10** correct, **9/10** safe.
- "Seconds": desktop single-flow target **< 30s** (proven); web single-flow
  target **< 5s** after Chromium warm. Full e2e in **< 4 min**.

## §5. Progress log

### 2026-07-17 — Session start
- Empirical baseline established (§0). Two of three desktop suites RED.
- Plan written.
- Subagents dispatched for parallel recon (Web PoC, deep code review,
  real-app UX desktop, real-app UX web).
