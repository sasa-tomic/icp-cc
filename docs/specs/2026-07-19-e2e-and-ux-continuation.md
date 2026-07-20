# 2026-07-19 — E2E Harness Completion + Radical Web Coverage + Real-App UX Sweep

- **Status:** IN PROGRESS
- **Predecessor:** `2026-07-17-e2e-completion-and-ux-sweep.md` (Phase A done; B/C/D/E partial-to-blocked; F–H not started).
- **Goal:** finish the predecessor's unfinished work **and** tackle the broader human ask: find/fix all functional+visual issues, radically improve the e2e harness so it covers **ALL** flows on **BOTH** surfaces in **seconds**, migrate every UI/UX verification test to it, reduce clicks, and DRY/loud-error the codebase along the way.

## §0. Empirical baseline (measured 2026-07-19, start of session)
| Check | Verdict | Evidence |
|-------|---------|----------|
| Backend API | ✅ UP | `:35735/api/v1/health` → 200; stats → 3 scripts, 426 downloads |
| `libicp_core.so` (FFI) | ✅ built 13 MB | `target/release/libicp_core.so` (2026-07-16) |
| Xvfb :99 | ✅ running | PID 2460 |
| zai-vision MCP | ✅ WORKING | Confirmed on `mk_01_profile_loaded_no_wizard.png` |
| Web widget smoke | 2 tests | `test/e2e_web/suite_web_smoke_test.dart` |
| Desktop e2e coverage | 64/98 (claimed) | Phase A green; Phase B consolidation pending |
| Open issues | 3 | WEB-1 (HIGH), E2E-1 (MED, in-prog), UX-N1 (LOW) |

**What changed since predecessor ended:**
- `zai-vision` MCP is now reachable (UX-N1 unblocks).
- Web Tier 1 harness is unchanged (still 2 widget tests).

## §1. Pivots from the predecessor (corrective decisions)

### Pivot 1 — Web e2e: stop fighting semantics enablement; **two complementary harnesses** instead.
The predecessor blocked Phase C on Flutter Web's a11y tree not enabling in
headless Chromium (WEB-1). After empirical re-investigation, the principled
fix is **NOT** to chase that wall. Use two complementary approaches:

1. **Web Tier A — `flutter test -d chrome` widget harness** (extending
   `test/e2e_web/suite_web_smoke_test.dart`). This runs the **REAL** Flutter
   Web app on canvaskit-Chromium (~3s warm). The `TestWidgetsFlutterBinding`
   limitations are real, so we mock at the **smallest I/O boundary** (the
   literal outbound HTTP call + plugin substrate via
   `SharedPreferences.setMockInitialValues` etc.) — exactly what the human's
   rules permit: *"Mocks can be used if e2e tests depend on external services;
   mock at the smallest boundary in e2e tests, e.g. the literal outbound HTTP
   call."* Drives the same `FlowCatalog` ids as desktop.
2. **Web Tier B — Playwright-against-built-web + `zai-vision` (image-based)**.
   Build the real bundle (`just web-dev-build`), serve on `:8080`, drive with
   Playwright/Chrome-CLI, screenshot, and **assert via `zai-vision_analyze_image`**.
   Bypasses the semantics-DOM issue entirely (vision reads the rendered canvas).
   Each flow = one Playwright script that navigates + screenshots + asserts
   visually. Slower than Tier A (~5s/flow) but proves the user-visible truth.
3. **WEB-1 → demote to DEFERRED.** When Flutter ships working programmatic
   semantics, Tier B can swap vision-asserts for DOM-asserts. The in-place
   `FLUTTER_WEB_FORCE_SEMANTICS` hook stays (already wired).

### Pivot 2 — `just e2e` shape: **suite-per-surface, fast single-flow, parallel-safe**.
- Desktop: 2 boots after Phase B (keyring-less-with-marketplace + mock-keyring).
- Web Tier A: 1 Chromium boot per suite file (parallel-safe across files).
- Web Tier B: 1 Chromium boot, all flows sequentially (cheap screenshots).
- `just e2e-one <flow-id>` works for **any** flow id across both surfaces.
- Full `just e2e` target: **< 4 min** wall (down from 5+).

### Pivot 3 — UX review: **chrome-cli + Xvfb → screenshot → zai-vision**, both surfaces.
The predecessor punted on visual UX (vision unavailable). Now it works. Two
review passes:
1. **Desktop**: real Linux app on Xvfb :99, `chrome-cli screenshot` per screen
   + dialog + sheet → `zai-vision_analyze_image` for analysis.
2. **Web**: real built bundle under Playwright/Chromium → screenshot + vision.
Both look for: AI slop, dead-end links, eternal spinners, broken layouts,
terminology drift, click-count for common paths, missing keyboard hints. Each
finding → row in `docs/OPEN_ISSUES.md`, then a RED test → fix → GREEN.

## §2. Phases & work units

### Phase P0 — Sanity (this session)
- [x] Start backend; verify `:35735/api/v1/health`.
- [x] Verify Xvfb running, FFI lib present.
- [x] Verify zai-vision MCP reachable.
- [ ] Baseline e2e-desktop (1 suite, ~86s) — confirm green.
- [x] Plan written, todos set.

### Phase B — Consolidate desktop suites (3 boots → 2)
- Merge `suite_marketplace_test.dart` into `suite_keyring_less_test.dart`
  (same keyring-less boot; marketplace phases appended).
- Delete `suite_marketplace_test.dart` (KISS/YAGNI).
- Update `justfile`: `e2e-desktop` = 2 PASSes; `e2e-marketplace` alias → run
  the merged suite tagged-filtered; `e2e-one` accepts the merged suite.
- Closes **E2E-1**.

### Phase C — Web e2e harness (NEW: Tier A + Tier B)
**Tier A (`flutter test -d chrome`):**
- Build a network-injection helper at the smallest I/O boundary
  (`HttpOverride` around `package:http`/`dio`) so tests can pin JSON
  responses. Honest substrate fakes for plugins.
- Migrate Surface.web / Surface.both flows from desktop Dart to the web harness
  (same `FlowRun` signature). Target: 20+ flows green.
- Single-boot suite file. Sub-minute total.

**Tier B (Playwright + vision):**
- `just web-dev-build` with `PUBLIC_API_ENDPOINT` baked in; serve via
  `python -m http.server` on `:8080`.
- Playwright TS harness under `test/e2e_web_playwright/`:
  `flow_catalog.json` (codegen from `flow_catalog.dart`), `harness.ts`,
  one `.spec.ts` per flow group.
- Each flow: navigate → `page.screenshot()` → assert via
  `zai-vision_analyze_image` (DOM dump optional for sanity).
- Sub-30s for any tagged subset.

### Phase D — Complete remaining desktop flows (target 90+/98)
After Phase B, ~64 desktop flows are green. Cover the remaining:
- Dapps runner flows (`dapps.run_ledger_mainnet`, `dapps.run_poll`, etc.).
- Deeplink flows (need `app_links` headless probe).
- Inline canister client (`canisters.open_inline_client`, `canisters.tap_bookmark`).
- Account/publish path (`account.register_from_publish`).
- Passkey-unsupported-linux (already there; verify).

### Phase E — UX review (REAL app, both surfaces, NO MOCKS)
**Desktop:** boot real Linux app via `flutter run -d linux` under Xvfb,
screenshot every screen + dialog + sheet using chrome-cli or `flutter run`.
Analyze each via `zai-vision_analyze_image`. Codify findings in
`docs/specs/UX_REVIEW_ROUND5.md` and `docs/OPEN_ISSUES.md`.

**Web:** boot built bundle via Playwright/Chrome-CLI. Same screenshot+vision
treatment.

Both: look for AI slop, dead routes, eternal spinners, broken layouts,
click-count, missing keyboard hints, inconsistent terminology, AI-stub
copy ("Lorem ipsum", "TODO", "Coming soon", "Placeholder"), unhelpful
errors, missing confirmations, etc.

### Phase F — Fix UX issues (TDD, one commit per issue)
Each P0/P1 finding from Phase E gets a RED test (Playwright, widget, or
vision-based golden) → fix → GREEN.

### Phase G — Click-reduction + keyboard-first
Audit common paths (create profile, browse → download → run, set up vault).
Reduce clicks. Encode optimized path in matching e2e flow. Verify keyboard
shortcuts are documented (help sheet) and intuitive.

### Phase H — Tech debt
- **TD-5**: `backend/src/account_service.rs` is ~2k lines → split.
- **TD-9**: DRY duplicated harness helpers across suites.
- **TD-10**: surface every silent `.ok()` / `if let Ok(..) {}` / `try {…} catch (_) {}`
  discovered during Phase E.

### Phase I — Persist open issues (ongoing)
- `docs/OPEN_ISSUES.md` stays the durable backlog; update on each close.
- `AGENTS.md` already links it.
- This plan + TODO.md reflect current truth at session end.

### Phase J — Final verify + report
- `flutter analyze` clean.
- `just test` (full unit/widget suite) green.
- `just e2e` (desktop + web) green.
- Coverage matrix printed; gaps justified.
- TODO.md + plan + OPEN_ISSUES.md updated; final report.

## §3. Subagent orchestration plan

To preserve context, the following are delegated (with `timeout`):

| # | Subagent | Mission | Outcome |
|---|----------|---------|---------|
| 1 | orchestrator-planner | (already — this plan) | plan committed |
| 2 | orchestrator-implementer | Phase B (merge marketplace into keyring-less) | 1 commit |
| 3 | orchestrator-implementer | Phase D (remaining desktop flows) | 1+ commits |
| 4 | orchestrator-implementer | Phase C-Tier-A (web widget harness migration) | 1 commit |
| 5 | orchestrator-implementer | Phase C-Tier-B (Playwright+vision) | 1 commit |
| 6 | orchestrator-verifier | Phase E desktop UX review (no mocks) | UX_REVIEW_ROUND5.md + OPEN_ISSUES rows |
| 7 | orchestrator-verifier | Phase E web UX review | UX_REVIEW_ROUND5_web.md + OPEN_ISSUES rows |
| 8 | orchestrator-implementer | Phase F (fix UX issues TDD) | commits per issue |
| 9 | orchestrator-implementer | Phase G/H (click-reduction + TD-5/9/10) | commits |
| 10 | orchestrator-finalizer | Phase J (final verify + report) | final commit |

**Hard rule:** top-level implementers are **serialized** (shared working tree,
`.git`, build caches — parallel commits race the index). Verifiers can run
parallel to each other (read-only).

## §4. Confidence
- Architecture (Tier A widget + Tier B Playwright+vision; 2-boot desktop;
  flow catalog as SSOT): **9/10** correct, **9/10** safe.
- "Seconds": desktop single-flow **< 30s** (proven); web Tier A single flow
  **< 5s** after Chromium warm; web Tier B single flow **< 8s**. Full e2e
  **< 4 min**.
- UX review with vision: **8/10** confidence it surfaces real issues; **9/10**
  safe (read-only).

## §5. Progress log

### 2026-07-20 — Phase L (Web Tier A 6 deferred flows)

**Goal:** lift 6 catalog flows from DEFERRED to PASSING on Web Tier A (3 passkey + 3 deeplink), growing coverage 7 → 13/98 on Web Tier A and 79 → 85/98 on total catalog.

**Outcome:** ✅ ALL 6 FLOWS GREEN in `suite_web_phase_l_test.dart` (2 testWidgets bodies: passkey 3-phase + deeplink 3-phase). 3 commits:

| commit | summary |
|--------|---------|
| `eb245df7` | feat(passkey): visibleForTesting seams for Web e2e harness — `PasskeyPlatform.isSupportedOverrideForTesting` + `NativePasskeyAuthenticator.{register,authenticate}OverrideForTesting`. No production behaviour change. |
| `005dd636` | test(e2e-web): Phase L 6 deferred flows — substrate HTTP passkey routes (`SubstratePasskeyStore` + 4 routes), substrate app_links emitter (`emitSubstrateDeepLink` + `collectSubstrateDeepLinks`), `suite_web_phase_l_test.dart` (6 flow bodies), catalog (`deeplink.*` → `_b`), justfile default suite list. |
| (this commit) | docs(OPEN_ISSUES): mark Phase L resolved. |

**Phase C insight that drove the design (must internalize for future Web Tier A flows):**

> `flutter test -d chrome` is NOT a Web compile. Test code compiles for the Dart VM; chrome is just the canvaskit renderer. `dart.library.html` evaluates FALSE.

Concrete consequences surfaced in Phase L:

1. `kIsWeb` is FALSE and `Platform.isLinux` is TRUE → `PasskeyPlatform.isSupported` returns FALSE → `PasskeyManagementScreen` renders the "Linux desktop unsupported" panel, not the list/register/delete UI. **Fix:** `PasskeyPlatform.isSupportedOverrideForTesting` static flag.
2. `NativePasskeyAuthenticator.register` would call into `package:passkeys`, which reaches `navigator.credentials.create` on Web or the FIDO framework on Android — unreachable from the test VM. **Fix:** `registerOverrideForTesting` static function override.
3. `_KeypairAppState._initDeepLinks` is guarded by `if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) return;` — the app's `_handleDeepLink` listener is never wired under test, so synthetic URI emission can drive only the `DeepLinkService` parsing layer (not the downstream UI navigation). **Documented as a known caveat** — desktop e2e remains the source of truth for the full deep-link UI chain.
4. **The binding's fake clock never advances real `Timer`s.** `Future.delayed` outside `tester.runAsync` hangs forever. Phase L flows route every wall-clock wait through `tester.runAsync(...)`. This is a general Phase C constraint; future flows must respect it.
5. Under `flutter test -d chrome`, `defaultTargetPlatform` is `TargetPlatform.android` (Flutter's default for the chrome target — web doesn't have its own TargetPlatform enum). The passkey.register flow derives its expected device name from `defaultTargetPlatform` dynamically (matching `_PasskeyManagementScreenState._getDeviceName`) rather than hardcoding "Linux Device".

**Substrate boundary simplifications (documented, not bugs):**
- Passkey account scoping: the real backend resolves `account_id` from the Ed25519 signature on the request; the substrate can't verify signatures, so it stores passkeys in a single global bucket. Documented inline in `substrate_http.dart`. PasskeyService Dart code runs unchanged.

**Files of record:**
- Production seams: `lib/utils/passkey_platform.dart`, `lib/services/passkey_authenticator_{native,stub}.dart`.
- Substrate extensions: `test/e2e_web/substrate/substrate_http.dart` (`SubstratePasskeyStore` + 4 routes), `test/e2e_web/substrate/substrate_app_links.dart` (`emitSubstrateDeepLink`, `collectSubstrateDeepLinks`).
- Test suite: `test/e2e_web/suite_web_phase_l_test.dart` (2 testWidgets, 6 flows).
- Catalog: `integration_test/e2e/flow_catalog.dart` (deeplink group → `_b`).

**Coverage after Phase L:**
- Desktop: 79/92 (unchanged — Phase L is Web-only).
- Web Tier A: 7 → 13/98 flows.
- **Total catalog:** 79 + 6 = **85/98**.

### 2026-07-19 — Session start
- Empirical baseline re-checked (§0).
- Plan written; todos set; subagent orchestration queued.
