# 2026-07-22 — SNS Voting Scripts Verification + E2E/UX Sweep Continuation

> **Status:** 🟡 IN PROGRESS (2026-07-22)
> **Owner:** orchestrator (glm-5.2 main; subagent swarms for parallel chunks)
> **Confidence:** 9/10 (approach), 8/10 (per-chunk, verified at boundary)
>
> **Extends:** `docs/specs/2026-07-21-e2e-harness-overhaul.md` (P0/P1 done,
> P2 first increment done, P3 QW-1..5 done, P4 not started).
> **Supersedes for this session's scope:** the unfinished P2-P4 of the
> 2026-07-21 plan, plus the user's SNS-scripts-verification ask.

## 1. User request (intent of record)

The user opened this session with two top-level asks, in priority order:

1. **(HIGHEST PRIO)** "Add/write SNS voting scripts with configurable
   background, theme, etc. Clone these repos to `third_party/` and
   reimplement in our stack relevant (useful) scripts from `CO.DELTA` +
   `ALPHA-Vote`. Focus on making the scripts highly readable and clean.
   Verify independently for these dimensions. Critical: these scripts must
   work and must be visually demoable and testable locally."
2. **(NEXT)** "If there is unfinished work from the previous session
   (check docs and other notes) — complete this FIRST. If no unfinished
   work: find + fix ALL functional and visual issues, radically improve
   the e2e test harness, optimize UX, persist all open issues."

## 2. State at session open (verified empirically 2026-07-22)

### 2.1 SNS voting scripts — ALREADY SHIPPED (prior session)

Per `docs/specs/2026-07-21-sns-voting-scripts.md` (STATUS: COMPLETE) +
`docs/specs/2026-07-21-alpha-vote-dapp.md` (STATUS: COMPLETE):

| Bundle | File | Tests | Live-verified | Theme |
|---|---|---|---|---|
| `08_nns_proposals.js` | 486 LOC | 7/7 PASS | NNS gov `rrkah-fqaaa-…` via dfx | app default |
| `09_sns_proposals.js` | 499 LOC | 7/7 PASS | OpenChat SNS `2jvtu-yqaaa-…` via dfx | per-DAO hex (`background`, `card_background`, `accent`, `text`, `text_muted`) |
| `10_alpha_vote.js` | 804 LOC | 25/25 PASS | `manage_neuron` auth-roundtrip vs dfx | app default |

**Re-verified this session (2026-07-22):** ran
`flutter test test/features/scripts/{nns,sns, alpha_vote}_bundle_test.dart`
→ **32/32 PASS in <1s**. The repos are cloned at `third_party/{CO.DELTA,ALPHA-Vote}/`.
The platform capability (`view()` root `theme` map → `ScriptAppHost`
`ColoredBox` + `Theme()` override) is in place.

**Independent verification still owed** (the user explicitly asked):
- ✅ Tests pass against the real pure-Dart JS runtime.
- ⏳ **Readability/cleanliness audit** vs the source Rust repos (dispatch
  to a verifier subagent — §4.1).
- ⏳ **Visual demoability** — boot the app, open each dapp, capture
  screenshots, confirm live mainnet round-trip renders (dispatch to a
  UX-review subagent — §4.4).

### 2.2 Known noise (filed as TD-SNS-1, low severity)

`sns_proposals_bundle_test.dart` prints `native_bridge: Linux libicp_core.so
open failed` on boot — **misleading**: the test uses the pure-Dart runtime
and passes; the warning fires unconditionally from
`lib/rust/native_bridge_io.dart:77` whenever the FFI dlopen fails, even
when the host doesn't need it. Per AGENTS.md "LOUD about misconfigurations",
the warning should be **accurate**: only print when the FFI is genuinely
required and unavailable. Tiny fix.

### 2.3 Unfinished work from the prior session (e2e-harness-overhaul plan)

From `docs/specs/2026-07-21-e2e-harness-overhaul.md` + `docs/OPEN_ISSUES.md`:

| Phase | Item | State |
|---|---|---|
| P0-A..C | cache race, DB reset, e2e-desktop green | ✅ RESOLVED |
| P1-A..D | per-flow test files + tag filtering + single-flow fast path | ✅ RESOLVED |
| P2 | Web per-flow e2e harness | 🟡 **First increment only** (7/79 web-eligible flows; ~66 to port). Spec: P2-WEB in OPEN_ISSUES. |
| P3 | UX click-reduction sweep | 🟡 QW-1..5 done; broader audit pending. |
| P4 | Functional/visual sweep via real-app tmux/chrome-cli | ⏸ **NOT STARTED**. |
| P5 | Documentation maintenance | 🟡 Ongoing. |

### 2.4 Other context (from `docs/HUMAN_EXPECTATIONS.md` §5 steering log)

- "TUI" = Flutter desktop (`flutter run -d linux`); "Web UI" = Flutter Web.
  Both are real surfaces for e2e + UX.
- Subagents share one working tree + `.git` + build caches — **serialize**
  top-level implementers; parallel edits/commits race on the index.

## 3. This session's work breakdown

Each chunk is dispatchable to a subagent. Order reflects dependency.

### 3.1 SNS voting scripts independent verification (HIGH PRIO — user ask)

**3.1-V1. Readability/cleanliness audit** — dispatch to
`orchestrator-verifier` subagent.
- Re-read `08_nns_proposals.js`, `09_sns_proposals.js`, `10_alpha_vote.js`.
- Cross-reference against the Rust logic preserved in
  `third_party/ALPHA-Vote/src/alpha_backend/src/lib.rs` and
  `third_party/CO.DELTA/src/...` (follow + fallback-reject + quorum rules).
- Verify the bundles are: readable end-to-end by a newcomer; DRY (the
  NNS+SNS share ~90% logic — confirm helper names + bodies are identical,
  ready for a future extraction on the 3rd occurrence); candid args match
  live-shape comments; no dead code; no AI slop.
- **Output**: a findings report. If issues are found, file them in
  `docs/OPEN_ISSUES.md` with severity. Apply trivial fixes (typos,
  comment clarity) directly; defer larger refactors with a documented
  justification.

**3.1-V2. Visual demoability check** — dispatch to `orchestrator-verifier`
subagent with chrome-cli + zai-vision access.
- Boot the Flutter Linux desktop app via the run-with-mock-keyring wrapper
  (or the production path if the keyring is up).
- Open the Dapps tab → `nns_proposals`, `sns_proposals`, `alpha_vote`.
- Capture screenshots at meaningful points. Confirm: live mainnet
  round-trip succeeds; the per-DAO theme renders on the SNS variant;
  empty-result case shows the honest "no open proposals right now"
  message; the ALPHA-Vote transparency layer (what the 3 public neurons
  voted) renders.
- **Output**: screenshots saved under `docs/specs/ux_screenshots/
  2026-07-22-sns-voting/` + a findings report. File any visual/functional
  defects in `docs/OPEN_ISSUES.md`.

### 3.2 Complete the e2e-harness-overhaul P2-P4

**3.2-P2. Web per-flow e2e harness — port the remaining ~66 flows.**
Dispatch to one `orchestrator-implementer` subagent per flow category
(onboarding, marketplace, scripts, dapps, profile, canisters, settings,
shortcuts), running serially per the HUMAN_EXPECTATIONS §4 "serialize
top-level implementers" rule. Each chunk:
- Ports N flows from `integration_test/e2e/*_flows.dart` into
  `test/e2e_web/flows_web_test.dart` (one testWidgets per flow, tag-injected).
- Uses the existing `web_suite_helpers.dart` substrate reset.
- Verifies `just e2e-web-one <flow>` is <10s and `just e2e-web-tag <tag>`
  is fast.
- Updates `docs/OPEN_ISSUES.md` P2-WEB entry with the new count.

**3.2-P3. UX click-reduction sweep (broader audit).** Dispatch to one
`orchestrator-planner` subagent to produce the audit, then one
`orchestrator-implementer` per accepted finding. The audit walks every
cataloged user flow, counts current steps, proposes optimizations, and
classifies each by ROI (high-traffic low-effort first). The QW-1..5
fixes are the template.

**3.2-P4. Functional/visual sweep via real-app run.** Dispatch to one
`orchestrator-verifier` subagent with chrome-cli + tmux + zai-vision
access. Boots the app, walks EVERY screen + EVERY user flow as a real
user (no mocks), files defects with screenshots + severity into
`docs/OPEN_ISSUES.md`. Per AGENTS.md: "UX review MAY NEVER EVER USE MOCKS
— if UX review without mocks does not work for some reason, IT'S a BUG."

### 3.3 Tech-debt quick wins (LOW PRIO, opportunistic)

- **TD-SNS-1** (this session): silence the misleading `libicp_core.so`
  warning when the pure-Dart runtime is in use.
- Any high-ROI DRY/KISS refactor surfaced by §3.1-V1.

### 3.4 Documentation maintenance (P5, continuous)

- Update `docs/OPEN_ISSUES.md` as findings surface; close as fixed.
- Update `AGENTS.md` link to this plan.
- Update `TODO.md` to reflect actual state at session end.
- Update `docs/HUMAN_EXPECTATIONS.md` if the user provides steering.

## 4. Execution plan

1. Main orchestrator (this agent) writes this plan, commits it. ✅
2. Dispatch **§3.1-V1 (readability audit)** as a verifier subagent.
3. Dispatch **§3.1-V2 (visual demoability)** as a verifier subagent with
   chrome-cli + zai-vision. (In parallel with §3.1-V1 — read-only, no
   edit conflicts.)
4. Dispatch **§3.2-P4 (functional/visual sweep)** as a verifier subagent.
   (In parallel with §3.1 — distinct surface, no edit conflicts.)
5. After §3.1 reports: dispatch **§3.2-P3 planner** for the UX audit.
6. After §3.1 reports: dispatch **§3.2-P2 implementer** (one category at
   a time) for the web e2e port. SERIAL with any other implementer to
   avoid git index races.
7. After §3.2-P3 planner reports: dispatch **§3.2-P3 implementer(s)**
   for the accepted UX fixes. SERIAL with §3.2-P2.
8. **§3.3 (tech-debt quick wins)** slotted in by the main orchestrator
   between subagent waves.
9. **§3.4 (docs)** maintained continuously by the main orchestrator.

Each subagent is instructed to:
- Run `timeout <N>` on every shell command.
- Commit each unit of work with a clean message.
- Update `docs/OPEN_ISSUES.md` for any finding.
- Report back: changes made, files touched, tests added, confidence 1-10,
  anything blocking.
- Spawn additional subagents if a chunk is too large.

## 5. Verification contract

End of session:
- `just test-feature scripts` GREEN (SNS bundles + everything else).
- `just e2e-desktop` GREEN, ~9m.
- `just e2e-web` GREEN, faster than before (more flows ported).
- `flutter analyze` clean.
- `docs/OPEN_ISSUES.md` up to date — every new finding filed, every fix
  marked RESOLVED with a commit ref.
- `docs/specs/ux_screenshots/2026-07-22-sns-voting/` populated.

## 6. Out of scope (deferred with reason)

- Full Playwright Web Tier B migration (existing Playwright harness works).
- Mobile (Android/iOS) — out of dev-box scope.
- Backend performance optimisation.
- The 3-way DRY extraction of NNS+SNS bundle helpers (YAGNI until the 3rd
  occurrence — documented in the spec).
- Authenticated voting beyond ALPHA-Vote's user-driven RegisterVote /
  Follow (the autonomous Rust follow + fallback-reject loop is preserved
  in `third_party/` for a future "set-and-forget" canister example; not
  needed for the headliner demo).

## 7. Change log

- 2026-07-22: plan created. Empirically verified the prior session's SNS
  voting scripts (32/32 tests pass). Identified §3.1 independent
  verification + §3.2 P2-P4 completion as this session's work.
