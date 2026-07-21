# 2026-07-21 — E2E Harness Overhaul + Visual/Functional Sweep + UX Optimization

> **Status:** 🟡 IN PROGRESS (2026-07-21)
> **Owner:** orchestrator (glm-5.2 main; subagents for parallel chunks)
> **Confidence:** 9/10 (approach); 8/10 (per-chunk, verified at boundary)
>
> **Linked from:** `docs/OPEN_ISSUES.md` (new entries filed as discovered).
> **Replaces / extends:** `docs/specs/2026-07-15-e2e-harness-and-ux.md`,
> `docs/specs/2026-07-17-e2e-completion-and-ux-sweep.md`,
> `docs/specs/2026-07-19-e2e-and-ux-continuation.md`.

## 1. Problem statement

The user request boils down to four hard requirements:

1. **Radically improve the e2e harness** for desktop (Flutter Linux) and Web UIs.
   Harness should **run in seconds** for the dev cycle (single-flow), cover
   **ALL** supported user flows, and migrate UI/UX verification to use it.
2. **Find and fix all functional and visual issues** — start with documented
   pre-existing issues, then sweep for new ones.
3. **Optimize UX**: reduce clicks / keystrokes for the common flows; reflect
   changes in tests.
4. **Persist everything**: all open issues in `docs/OPEN_ISSUES.md`; agent
   instructions updated.

The current harness is functionally rich (98 flows registered, 100% catalog
coverage on desktop) but **fragile and slow**. Specifically:

- **3 min for ONE of 4 suites** (`suite_keyring_less_test.dart`); ~12 min for
  `just e2e-desktop` end-to-end. Single-flow iteration ~2 min (most of that
  is boot + state reset, not the flow under test).
- **Cache-manager race in `resetAppState`** (NEW-1, see §3): wipes the
  `~/.cache/data/com.example.icp_autorun/` dir while `flutter_cache_manager`
  holds an open handle to `libCachedImageData.json` → `PathNotFoundException`
  → `_pendingFrame == null` assertion in `LiveTestWidgetsFlutterBinding.postTest`
  → suite crashes at PHASE 1.
- **Backend DB contamination** (NEW-2): there is no per-suite DB reset. Stale
  scripts from prior runs (`Bulk Seed Script N`, `Pub_NNN`, …) accumulate
  (1110 scripts observed in `marketplace-dev.db` after one session). Tests
  that assume a sparse 3-script marketplace (`PHASE 18`'s `find.textContaining
  ('Hello IC Starter')`) silently break.
- **Single-testWidgets stability threshold**: known "Cannot close sink while
  adding stream" crash past ~30 phases (`OPEN_ISSUES.md` E2E-PHASE56+57).
  Split into 4 mini-suites as a workaround; the root cause (resource
  accumulation in long single-`testWidgets` body) is not fixed.

## 2. Design goals

### G1 — Dev cycle in seconds
- `just e2e-one <flow-id>` boots once, runs ONE flow, exits.
  Target wall-clock: **< 20 s** on a warm build.
- `just e2e-tag smoke` runs the smoke subset. Target: **< 60 s**.
- `just e2e-desktop` full suite: target **< 5 min** (down from ~12 min).

### G2 — Per-flow isolation by default
- Each flow runs in its own `testWidgets` body. No more 55-phase
  monolith; no more "phase 30 crash takes 29 phases of evidence with it".
- Shared `setUp` boots the binding once; cheap `pumpWidget` remounts between
  flows. App boot is ~3 s; remount is ~1 s.

### G3 — Real-app verification (no mocks in the harness)
- Backend: REAL (`just api-dev-up`).
- FFI: REAL (`libicp_core.so`).
- File system / SharedPreferences / secure storage: REAL (wiped between
  flows, with the cache manager properly stopped first).
- Network to mainnet: best-effort (assertions accept graceful failure).
- The harness may use **testing seams** the production code already exposes
  (`PasskeyPlatform.isSupportedOverrideForTesting`,
  `NativePasskeyAuthenticator.{register,authenticate}OverrideForTesting`,
  `IcpayService.overrideHttpClient`-style) — these are not mocks of the SUT,
  they are bounded overrides at the I/O boundary.

### G4 — Coverage contract preserved
- `flow_catalog.dart` stays the source of truth. Each flow has a stable id,
  surface, keyring mode, tags. `coverageReport(registry)` reports gaps.
- Per-flow tests are tagged (`'smoke'`, `'marketplace'`, `'onboarding'`,
  `'desktop-only'`, …) so `--exclude-tags` / `--tags` filter subsets.

### G5 — UX optimization, not just verification
- Each common flow is examined for click/keystroke reduction opportunities.
- Findings filed in `docs/specs/ux/2026-07-21-ux-optimizations.md` and
  applied as code changes; tests updated to assert the shorter flow.

## 3. Newly discovered issues (filed in `docs/OPEN_ISSUES.md`)

- **NEW-1 (HIGH):** `resetAppState` deletes the cache dir out from under
  `flutter_cache_manager`. Surfaces as `PathNotFoundException` on
  `libCachedImageData.json` → binding crash. Root cause: `JsonCacheInfoRepository`
  caches the file handle and writes lazily; deleting the dir from a second
  party is unsafe. Fix: stop the cache manager explicitly before deleting,
  OR scope the app's cache to a per-run temp dir.
- **NEW-2 (HIGH):** No per-suite DB reset. Stale scripts accumulate in
  `marketplace-dev.db`; tests assuming a sparse marketplace silently break.
  Fix: a `just _e2e-reset-db` helper that wipes + reseeds, called from
  `e2e-desktop` / `e2e-web` `setUpAll`.
- **NEW-3 (MEDIUM):** The keyring-less suite ran **3 min** and only
  completed PHASE 0 before crashing (NEW-1). The "PHASE 18 failure"
  I saw on the first run was NEW-2 (DB had 1110 scripts; tiles were buried).
  Both are environmental, not app bugs — but they make the harness
  non-functional on a contaminated box.
- **NEW-4 (MEDIUM):** `LiveTestWidgetsFlutterBinding.postTest` assertion
  (`_pendingFrame == null`) is fired by NEW-1's leaked Future. This is a
  symptom, not a root cause; fixing NEW-1 eliminates it.
- **NEW-5 (MEDIUM):** 2532-line `suite_keyring_less_test.dart` is a single
  `testWidgets` with 55 phases. Hard to maintain, hard to iterate on, hard
  to parallelise. (Already documented but never fixed — previous sessions
  worked around by splitting into 4 mini-suites; the monolith remains.)

## 4. Work breakdown

Each chunk is independent and dispatchable to a subagent. Order reflects
dependency: P0 fixes unblock P1; P1 unblocks P2; P3 is parallel.

### P0 — Unblock the harness (CRITICAL, do first)

**P0-A.** Fix NEW-1: `resetAppState` cache-manager race.
- Approach: wrap the deletion in `tester.runAsync` and stop the cache
  manager first (`DefaultCacheManager().emptyCache` + `disposeFile` for
  known entries; or hold a static reference and call `.dispose()`).
- File: `apps/autorun_flutter/integration_test/e2e/suite_helpers.dart`.
- RED test: a tiny `testWidgets` that calls `resetAppState` after the
  cache has been written, asserts no exception, asserts the dir is gone.

**P0-B.** Fix NEW-2: per-suite DB reset.
- Approach: add `just _e2e-reset-db` that runs
  `backend/scripts/add-sample-data.sh` against the live dev DB (or, better,
  issues a `/api/v1/admin/reset` endpoint that the backend exposes in
  `debug` mode — TBD which is cleaner; KISS says the shell call first).
- Called from `e2e-desktop` / `e2e-web` recipes BEFORE the suites run.
- File: `justfile`, `scripts/e2e-reset-db.sh`.

**P0-C.** Verify end-to-end: `just e2e-desktop` green from a clean box.
- Acceptance: 4 PASSes green; full run < 8 min on this dev box.

### P1 — Architectural redesign (parallelizable after P0)

**P1-A.** Split `suite_keyring_less_test.dart` into per-feature groups.
- Marketplace, profile, scripts, canisters, dapps, settings, shortcuts,
  download_history → 8 focused files under
  `integration_test/e2e/keyring_less/`.
- Each file uses `group('feature', () { testWidgets('flow-id', ...) ; ... })`.
- Shared driver / helpers stay in `e2e_driver.dart` / `suite_helpers.dart`.
- Acceptance: each file < 600 lines; coverage unchanged; total runtime
  unchanged or better (parallelisable across files).

**P1-B.** Same treatment for `suite_mock_keyring_test.dart` (1080 lines),
  `suite_mock_keyring_dapps_test.dart` (484), `suite_mock_keyring_identity_test.dart` (499).

**P1-C.** Add `--tags` and `--exclude-tags` support to `just e2e-desktop`,
  `e2e-one`, `e2e-tag`. Flow specs already declare tags; surface them.
- Justfile recipe: `e2e-tag tag='smoke'` → runs `flutter test ... --tags="smoke"`.

**P1-D.** Single-flow fast path: `just e2e-one <flow-id>` boots only the
  needed group, skips everything else. Target < 20 s.

### P2 — Web e2e parallel overhaul (after P1)

**P2-A.** Apply the same per-flow / per-group pattern to
  `test/e2e_web/suite_web_*.dart`.
- The substrate (HTTP / secure-storage / app_links fakes) stays — it's the
  thinnest I/O boundary, allowed by the rules.
- Each flow runs in its own `testWidgets`.

**P2-B.** Cover the 6 web-only passkey/deeplink flows in the new shape
  (currently in `suite_web_phase_l_test.dart`).

**P2-C.** Web Tier B (Playwright against real Chrome) — keep the existing
  harness; add tags so it's filterable.

### P3 — UX optimization sweep (parallel, after P1)

**P3-A.** Audit each common flow for click reduction. Common flows:
1. First-run → browse marketplace → download free script → run.
2. First-run → create local profile → first script.
3. Create account → publish script.
4. Open profile menu → switch profile.
5. Open script details → write a review.
6. Dapps → open canister → call method.

For each, document the current step count and the optimized step count.
File findings as code changes + updated tests.

**P3-B.** Keyboard shortcuts: ensure the common paths are fully drivable
  from the keyboard, with shortcuts shown in the help sheet (`?`).

### P4 — Functional / visual sweep (parallel, after P0)

**P4-A.** Boot the app in tmux/chrome-cli as a regular user. Walk every
  screen. File visual issues (alignment, contrast, dark-mode regressions,
  AI slop, dead widgets, stale text).

**P4-B.** Walk every user flow. File functional issues (errors, dead-ends,
  misleading copy, silent failures, broken navigation).

**P4-C.** For each finding: write a RED test → fix → GREEN. File the issue
  in `docs/OPEN_ISSUES.md` with severity + location + evidence.

### P5 — Documentation & maintenance (continuous)

**P5-A.** Update `docs/OPEN_ISSUES.md` with new findings as they surface.
  Close items as they are fixed.

**P5-B.** Update `AGENTS.md` to link to the new plan + the new open issues.

**P5-C.** Update `TODO.md` to reflect actual state.

**P5-D.** Update `docs/HUMAN_EXPECTATIONS.md` if the user provides any
  guidance through prompts.

## 5. Execution plan

1. **P0** done by main orchestrator (small, critical, unblocks everything).
2. **P1 + P2** dispatched as parallel subagents (one per suite/file).
3. **P3 + P4** dispatched as parallel subagents (UX reviewer + functional
   sweeper; both spin up the real app, walk flows, file findings).
4. **P5** maintained continuously by main orchestrator.
5. Each subagent reports back with: changes made, files touched, tests
   added, confidence 1-10, anything blocking.
6. Main orchestrator reviews, commits per chunk, runs `just test` between
   chunks to catch regressions.

## 6. Verification

- `just e2e-desktop` GREEN, < 8 min.
- `just e2e-web` GREEN.
- `just test-feature marketplace` / `scripts` / `profile` GREEN.
- `flutter analyze` clean.
- `just test` (full suite) GREEN.
- `docs/OPEN_ISSUES.md` up to date.

## 7. Out of scope (deferred)

- Full Playwright Web Tier B migration (the existing Playwright harness
  works; deep overhaul is a separate effort).
- The local-replica poll-flow suite (`just e2e-local-replica`) — already
  isolated and working.
- Backend performance optimisation.
- Mobile (Android/iOS) — out of dev-box scope.

## 8. Change log

- 2026-07-21: plan created. P0 issues identified during baseline run.
