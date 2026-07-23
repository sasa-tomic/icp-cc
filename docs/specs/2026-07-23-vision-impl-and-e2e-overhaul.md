# 2026-07-23 — Canister Frontend Vision Implementation + E2E Harness Radical Improvement

**Status:** IN PROGRESS · **Date:** 2026-07-23 · **Author:** orchestrator
**Source plan:** `docs/specs/2026-07-23-canister-frontend-vision.md` (feasibility spike + roadmap, decisions LOCKED)

---

## Context

The previous session produced `2026-07-23-canister-frontend-vision.md` — a completed
feasibility spike + 4-phase roadmap for canister web frontends. Decisions are LOCKED
(D-first phase order, impersonate Plug, per-script trust, R-3 folded into Phase 1).
**Zero implementation has started.** This plan picks up exactly where that session left off.

Simultaneously, the human requested:
1. **Complete unfinished work FIRST** → Vision Phase 1 (D: Candid scaffold) + R-3 fix.
2. **Fix ALL documented issues** → OPEN_ISSUES.md is nearly all RESOLVED; R-3 is the main open latent bug.
3. **Radically improve e2e harness** → run in seconds, cover ALL flows, verify REAL app (not mocks).
4. **UX review** → start the real app, find issues, optimize flows (fewer clicks, keyboard-first).

---

## Work Streams

### WS-1: Vision Phase 1 (D) — Candid Scaffold + R-3 Fix *(HIGHEST PRIORITY — unfinished work)*

**What:** "Scaffold a frontend from any canister" → fetch Candid (robust read_state path) →
generate a starter `ui_v1_renderer` bundle → open in ScriptAppHost / editor.

**Side-fix R-3:** rewire `CandidService` from the defunct `icp-api.io` registry GET
(404s for ALL canisters) to the FFI `icp_fetch_candid` read_state `candid:service` path.

**Acceptance:**
1. Paste ANY canister id → Candid loads (incl. ICP Ledger `ryjl3-…` which has no `__get_candid_interface_tmp` — proves R-3 fix).
2. A runnable `ui_v1_renderer` bundle is generated and opens rendering query method outputs.
3. `just test-feature scripts` green + new scaffold tests.
4. The `icp-api.io` dead-registry fallback is REMOVED (greenfield — no backward compat).

**Files:**
- **New:** `lib/services/frontend_scaffold_generator.dart` (the generator ~200-300 LOC).
- **New:** `lib/screens/canister_scaffold_screen.dart` (entry point UI — paste canister → discover methods → scaffold → open in editor).
- **Touch:** `lib/services/candid_service.dart` (rewire to FFI `icp_fetch_candid`; DELETE the `_fetchCandidFromRegistry` + `kCandidRegistryHost` dead path).
- **Touch:** `lib/screens/bookmarks_screen.dart` or `lib/screens/canisters_screen.dart` (add "Scaffold frontend" entry point in the Canisters tab).
- **Reuse:** `CanisterCallBuilderDialog.generateBundle` pattern; `ScriptAppHost`; `ui_v1_renderer`.

**Effort:** S (≈1 session). **Risk:** Low. **Confidence:** 9/10.

---

### WS-2: E2E Harness Radical Improvement

**Current state:**
- Desktop: 4 suites, ~9m total, 91+ flows, per-flow 9-25s. The 4 boots dominate.
- Web: 32/79 web-eligible flows ported. ~30s for the 32.
- Flow catalog: 98 total flows.
- Per-flow files (`flows_*_test.dart`) give fast single-flow iteration (9-25s).

**Improvement targets:**
1. **Desktop full-suite < 4m** (from 9m): parallelize the 4 suite boots (they use different state dirs + can share one backend). Each suite already runs in ~2m independently.
2. **Complete web e2e coverage**: port remaining ~47 web-eligible flows (currently 32/79).
3. **Migrate ALL UI/UX visual verification tests** to the harness (consolidate the scattered `*_visual_test.dart` / `*_sweep_test.dart` files into the flow-catalog-driven harness).
4. **`just e2e-smoke` < 30s**: a fast smoke gate (4-6 critical flows) for the quickest dev signal.

**Approach:**
- Parallelize desktop suites via background Xvfb sessions (each suite gets its own `:NN` display).
- Port web flows by category, dispatched to parallel subagents (onboarding, marketplace, canisters, dapps, vault, settings, shortcuts).
- Consolidate visual tests: the `screenshot_capture_test.dart` / `app_visual_sweep_test.dart` / `voting_dapps_visual_test.dart` patterns fold into tagged flows in the catalog.

**Effort:** M (2-3 subagent dispatches). **Risk:** Medium (parallel Xvfb coordination).

---

### WS-3: Issue Sweep + UX Review (real-app, no mocks)

**Method:** Start the REAL app (tmux / Xvfb), drive it as a real user, find functional +
visual issues. Fix them. Optimize flows (fewer clicks, keyboard-first).

**Scope:**
- Full UX review of every screen (new user + returning user perspective).
- Screenshot analysis via `zai-vision` for layout consistency, AI slop, broken elements.
- Click-count audit on the most common flows.
- Keyboard accessibility audit (can every common action be done from keyboard?).

**Deliverable:** issues filed into `docs/OPEN_ISSUES.md`; fixes committed per-unit; UX flows codified as e2e tests.

---

## Execution Order

```
WS-1 (Phase 1 + R-3)  ──►  WS-3 (issue sweep, real app)  ──►  WS-2 (harness improvement)
         │                           │
         ▼                           ▼
   subagent: implementer      subagent: UX reviewer
   subagent: verifier         subagent: fixer (per-issue)
                              (findings feed back into WS-2 test coverage)
```

**Rationale:** WS-1 first (it's the unfinished work + fixes a real bug). WS-3 second
(needs the app running with the new scaffold feature). WS-2 last (informed by what
WS-3 surfaces — new flows to codify).

---

## Subagent Orchestration

| Dispatch | Type | Task | Timeout |
|----------|------|------|---------|
| D1 | orchestrator-planner | Deep-dive R-3 + Phase 1 architecture (read FFI, candid_service, script_app_host, ui_v1_renderer) → detailed implementation plan | 5m |
| D2 | orchestrator-implementer | Implement R-3 rewire + FrontendScaffoldGenerator + UI entry (TDD) | 15m |
| D3 | orchestrator-verifier | Verify Phase 1 against real mainnet canisters (ICP Ledger, II, governance) | 10m |
| D4 | orchestrator-planner | E2e harness improvement plan (parallelization, web porting, visual test consolidation) | 5m |
| D5+ | orchestrator-implementer | Port web e2e flows by category (parallel dispatches) | 10m each |
| D6 | orchestrator-verifier | UX review: start real app, screenshot every screen, analyze, file issues | 15m |

**Serialization:** top-level implementers are serialized (shared working tree + .git).
Planners/verifiers can run in parallel with implementers.

---

## Confidence

| Stream | Confidence | Rationale |
|--------|-----------|-----------|
| WS-1 (Phase 1 + R-3) | 9/10 | Every component exists; generator is ~200-300 LOC string-building; R-3 path already proven in `ic_agent_engine.dart` |
| WS-2 (harness) | 7/10 | Parallel Xvfb coordination is the risk; web porting is mechanical |
| WS-3 (UX) | 8/10 | Standard review process; `zai-vision` available for screenshot analysis |
