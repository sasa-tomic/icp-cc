# Next Iteration Plan — Tech Debt · Test Quality · UX (Dapps + Round-5)

- **Status:** Wave 1 EXECUTED (original 7 COMPLETE; UX-10 added & ACTIVE),
  Waves 2–4 PLANNING. Extends `NEXT_PHASE_PLAN.md` (COMPLETE),
  `UI_EXCELLENCE_PLAN.md` (COMPLETE), and `EXAMPLE_DAPP_INTEGRATION_PLAN.md`
  (Phase 1 COMPLETE; Phase 2 webview DEFERRED). Grounded in two fresh audits
  (2026-07-04): `audit_techdebt_tests.md` + `audit_ux_round5.md` (both on disk
  under `/tmp/opencode/`; the UX round captured in this doc's findings).
- **Date:** 2026-07-04
- **Target:** Linux desktop + backend (Rust/Poem) + the example Poll dapp
  (`examples/icp_poll_dapp`, deployed to the local replica).
- **Method:** every claim re-verified by `rg`/`wc` and, for UX, by driving the
  **real app** under Xvfb + mock Secret Service against the **real dfx-deployed
  canister** (no product mocks). The Dapps tab was verified to talk to the real
  canister end-to-end (`dfx canister call backend listPolls` → 3 real polls;
  the live permission dialog names the real canister + method).

---

## 0. What changed since the last plans

- **Dapps tab shipped** (Phase 1, commits `a8b29c62` … `71f9d48d`): catalog +
  runner + Path B (backend-direct) bundle `06_icp_poll.js`, talking to a real
  local-replica canister. **Never UX-reviewed until now** → Round-5 is its first
  review.
- **Round-4 UX items landed:** UX-2 (Canisters label), UX-3 (searchable method
  picker), UX-7 (local keys reachable w/o backend), UX-9 (keyboard help +
  `Alt+3`). UX-8 is **largely resolved** by the local-only account body.
- **All prior TD/TQ claims re-verified DONE** (TD-1..5, TQ-1..3): file-I/O
  timeouts, backend cancellation, no FFI panics, status-color tokens (95%),
  ScriptsScreen DI seam, marketplace negatives, scripts harness — all hold.
- **New debt found:** TD-8 (clipboard slop — a real user-facing bug; DONE
  `d190be3d`), and what the audit framed as 9 residual status-color literals
  (TD-9, the TD-5 finish-up). **TD-9 was REDIRECTED in implementation** — see
  TD-9: the 9 literals are documented-bespoke (NOT status colors; converting
  them would corrupt UI semantics), and the one genuine residual was
  `offline_banner.dart`'s amber warning (DONE `76402018`).
- **`bookmarks_screen.dart` grew to 2119** (UX-3 search added) → now the
  app's largest file and the top split candidate (TD-10).

---

## 1. Architectural issue REQUIRING a human decision (flagged loudly, NOT auto-executed)

### A-4 — Vault crypto is NOT actually zero-knowledge (intent ↔ code divergence)
- **Problem:** `HUMAN_EXPECTATIONS.md` and `AGENTS.md` both state the vault is
  **zero-knowledge** (*"the server only ever encrypts the vault … decryption is
  client-side"*). The **code does not implement that**: the client sends the
  vault password in plaintext to `/api/v1/vault`, and the **backend** derives the
  Argon2id key and does the AES-256-GCM (`backend/src/vault.rs:70
  encrypt_vault`; `services/passkey_service.rs:509`). There is **no client-side
  crypto in Dart**. A compromised server / DB dump + a captured password can
  decrypt every vault. The `vault.rs:4` doc-comment *"Decryption happens
  client-side"* is **false** today.
- **Confidence: 9/10** (grounded in code; may be an intended-as-staged rollout).
- **Decision needed (NOT silently decided):**
  - (a) **Accept the current model** → fix the docs/comments to stop claiming
    zero-knowledge (downgrades the security promise); OR
  - (b) **Execute the migration** → Argon2id + AES-256-GCM in Dart, make
    `/vault` a pure opaque-blob store, delete `encrypt_vault` server-side.
    Multi-day, touches passkey/vault/recovery end-to-end.
- **This plan's interim action (mandatory regardless):** make the code comments
  honest (see **TD-13**) so the code does not lie while the decision is pending.
  Per AGENTS.md, this is documented, NOT worked around with a symptom fix.

---

## 2. Work Units

> Conventions (same as prior plans): every WU follows the **PoC-first** workflow.
> One commit per WU (file-split WUs: one commit per file). Every commit leaves
> `flutter analyze` clean and the cited tests green. **TD = tech debt,
> TQ = test quality, UX = UX.** Numbering continues prior plans.

### Wave 1 — independent, low-risk, parallel

> **Status (2026-07-04):** the original 7 Wave-1 items are all COMPLETE —
> TD-8 `d190be3d` (drive-by stale-comment `31d1149c`), TD-9 `76402018`
> (redirected — see its body), TD-13 `4a2cbb83`, UX-11 `7f543480` (impl DONE,
> acceptance PENDING-UX-10), UX-12 `3b0f05d8`, UX-13 `7648f636`, TQ-4
> `3e29990d`. **UX-10** (below) was pulled INTO scope after the round began —
> it is the one remaining ACTIVE Wave-1 item and the dependency that unblocks
> UX-11's acceptance.

#### TD-8 — Fix the `canister_call_builder` clipboard slop (user-facing lie) ✅ DONE `d190be3d` (drive-by `31d1149c`)
- **Problem:** the "Copy bundle" button shows *"Snippet copied to clipboard!"*
  **without ever calling `Clipboard.setData`** (the TODO at the call site admits
  it). Direct `HUMAN_EXPECTATIONS` §2 violation (*"no slop … every shipped thing
  works as a user"*). The lone offender — all 15+ other clipboard sites work.
- **Grounding:** `lib/widgets/canister_call_builder.dart:211-219` (`_copyToClipboard`
  → TODO, then success snackbar). Contrast `scripts_screen.dart:1263`,
  `result_display.dart:479`, `account_profile_screen.dart:1701` — all call
  `Clipboard.setData` first.
- **Change:** make `_copyToClipboard` `async`, add
  `await Clipboard.setData(ClipboardData(text: snippet));` before the snackbar,
  delete the TODO. Add a regression widget test (pump, tap copy, assert
  `Clipboard.getData` equals the generated bundle + snackbar appears).
- **Drive-by:** delete the stale *"// For now, just copy the script URL"* comment
  at `scripts_screen.dart:1256` (the code DOES copy at `:1263`).
- **Risk:** LOW. **Confidence 10/10.**
- **Commit:** `fix(canister-builder): TD-8 actually copy the bundle to clipboard`

#### TD-9 — Sweep residual status-color literals to tokens (TD-5 finish-up) ✅ DONE `76402018` (REDIRECTED)
- **Status:** COMPLETE — but **redirected** during implementation. The plan as
  originally written cited 9 `Colors.(green|red|orange)` literals as residual
  *status-color* debt. A PoC proved them all **documented-bespoke**, NOT status
  colors:
  - `bookmarks_screen.dart:1051,1109,1206,1619` (orange = **call-type category
    tint**, not "warning"),
  - `script_details_dialog.dart:534,665` (orange = **status badge** for a
    specific bespoke state, deliberately off-token by the prior TD-5 pass,
    commit `e664efe3`),
  - `script_card.dart:479,484,495` (red = **delete/error icon** + **purchase
    CTA** + **favorite-heart** tints).
  Converting any of these to `AppDesignSystem.{success,warning,error}Color`
  would **corrupt their UI semantics** (a call-type category is not a
  "warning"). So they are intentionally left untouched.
- **Genuine residual (the actual fix):** `lib/widgets/offline_banner.dart`
  used `Colors.amber.shade100/300/900` for a *warning* status — the one true
  status-color offender. Converted the whole palette (bg tint / border /
  foreground) to derive from the single `AppDesignSystem.warningColor` token.
- **Acceptance:** `offline_banner_test.dart` updated to assert the
  token-derived color. A status-palette swap is now a one-file change in
  `AppDesignSystem`. The `rg "Colors\.(green|red|orange)"` line in §4 is
  accordingly reworded (the 9 cited literals are bespoke and intentionally
  retained).
- **Risk:** LOW. **Confidence 10/10.**
- **Commit:** `refactor(design): TD-9 sweep residual status-color literal to token` (`76402018`)

#### TD-13 — Make the vault code comments honest (interim, pending A-4 decision) ✅ DONE `4a2cbb83`
- **Problem:** `vault.rs:4` claims *"Decryption happens client-side"* — false today.
  `vault_unlock_screen.dart:61` TODO is already honest. The lie must go while A-4
  is pending.
- **Change:** rewrite the `vault.rs` module doc-comment to describe the CURRENT
  model accurately (server-side Argon2id + AES-GCM) + add a `// TODO(A-4):`
  pointing to the client-side-crypto migration recorded in `TODO.md`. Do NOT
  touch `HUMAN_EXPECTATIONS.md` (it is the intent of record).
- **Risk:** LOW (comments only). **Confidence 10/10.**
- **Commit:** `docs(vault): TD-13 honest code comments pending A-4 zero-knowledge decision`

#### UX-11 — Poll dapp auto-loads on open (not "Polls (0)" + manual Refresh) ✅ impl DONE `7f543480` · acceptance PENDING-UX-10
- **Status:** implementation COMPLETE (`7f543480`) — `init` now emits the
  whoami+listPolls batch so polls load on open instead of "Polls (0)". The
  **acceptance criterion is reworded** (below) and now depends on **UX-10**;
  full acceptance is PENDING until UX-10 lands.
- **Problem (original):** the bundle's `init` returned `effects: []`, so the
  dapp opened to "Polls (0)" — contradicting the plan's *"sees a real canister
  respond … One click, no setup"*. Fixed by `7f543480`.
- **Remaining friction (the UX-10 dependency):** even with auto-load, the
  per-method permission gate still fires a prompt for `whoami` AND `listPolls`
  on every cold start, and re-prompts across restarts. The old acceptance
  ("One click, no setup" / "no extra prompt") was therefore **unachievable
  without UX-10**. UX-10's persisted "Trust this dapp" grant is what collapses
  those to a single prompt that survives restarts.
- **New acceptance (reworded, depends on UX-10):** opening the Poll dapp shows
  **real polls within ~1s** with **at most ONE prompt** — the trust-this-dapp
  grant from UX-10 — **persisting across restarts** (no re-prompt on the second
  open). Until UX-10 lands, acceptance is PENDING-UX-10.
- **Grounding:** `lib/examples/06_icp_poll.js` `init`/`refreshEffects`
  (auto-load done); permission gate around the effect dispatcher in
  `lib/screens/dapp_runner_screen.dart` (the UX-10 target).
- **Risk:** LOW (impl); MED (acceptance gated on UX-10). **Confidence 9/10**
  (impl), **8/10** (acceptance, once UX-10 lands).
- **Commit:** `fix(dapps): UX-11 poll bundle auto-loads on open` (`7f543480`)

#### UX-13 — Fix the DISPLAY double-prefix in `run-with-mock-keyring.sh` ✅ DONE `7648f636`
- **Problem:** the documented "regular user" launch command
  (`--display :99 …`) is **broken as written** — the app aborts with
  `cannot open display: DISPLAY=:99`. The wrapper emits
  `export DISPLAY=DISPLAY=:99` (double prefix).
- **Grounding:** `scripts/run-with-mock-keyring.sh` `${DISPLAY_ENV[0]:+export
  DISPLAY=${DISPLAY_ENV[0]}}`. Reproduced live in Round-5.
- **Change:** `${DISPLAY_ENV[0]:+export ${DISPLAY_ENV[0]}}` (drop the extra
  `DISPLAY=` prefix).
- **Risk:** TRIVIAL. **Confidence 10/10.**
- **Commit:** `fix(scripts): UX-13 fix DISPLAY double-prefix in run-with-mock-keyring`

#### UX-12 — Dapps Connection panel honesty ✅ DONE `3b0f05d8`
- **Problem:** collapsed-by-default Connection panel + *"Loading saved
  connection…"* copy (implies network; it's only SharedPreferences) hides the
  recovery path when a fresh `dfx start --clean` changes the canister ID.
- **Grounding:** `screens/dapp_runner_screen.dart:242` (`initiallyExpanded:
  false`), `:245-253` (loading copy), `:338-340` (spinner).
- **Change:** (a) reword the transient to *"Reading saved connection…"* (honest
  local read); (b) when the first canister call fails reachability, auto-expand
  the Connection panel + surface a *"Canister unreachable — check id/host in
  Connection"* hint. No happy-path behaviour change.
- **Risk:** LOW. **Confidence 8/10.**
- **Commit:** `feat(dapps): UX-12 honest Connection panel + reachable recovery`

#### TQ-4 — Fold the marketplace test `MaterialApp` harness (mirror TQ-3) ✅ DONE `3e29990d`
- **Problem:** `test/features/marketplace/` rebuilds `MaterialApp(...)` ~10×
  across 5 files. TQ-3 solved this for scripts.
- **Change:** add `test/features/marketplace/_marketplace_test_harness.dart` with
  `pumpMarketplaceWidget(tester, child, {...})`; migrate the ~10 callers
  mechanically.
- **Risk:** LOW. **Confidence 8/10.**
- **Commit:** `refactor(test): TQ-4 fold marketplace MaterialApp harness`

#### UX-10 — "Trust this dapp" grant for the shipped example (permission-gate fix) 🆕 ACTIVE (pulled into scope; previously omitted)
- **Status:** ACTIVE — pulled into scope after Wave 1's original 7 items
  completed. This was previously **omitted** from the plan (not in §5
  out-of-scope; simply missed). Implementation PENDING. It is the dependency
  that makes **UX-11's** reworded acceptance achievable.
- **Problem:** the Dapps permission gate prompts **per method**, so opening the
  Poll dapp fires a prompt for `whoami` AND `listPolls` on every cold start,
  and re-prompts across restarts. That friction is what made UX-11's old
  "no extra click" acceptance unachievable. The dual-path security model wants
  the user to **trust a dapp**, not re-approve individual methods for a known,
  catalog-shipped, signed example.
- **Grounding:** the permission gate around the effect dispatcher in
  `lib/screens/dapp_runner_screen.dart` keys prompts on `(canister, method)`;
  there is no persisted "trusted dapp" set today.
- **Change:** add a single **"Trust this dapp"** grant scoped to the **shipped
  example** dapp (catalog-bundled, signed). Once accepted it persists across
  restarts (SharedPreferences, alongside the connection state) and skips
  subsequent per-method prompts for that dapp's canister(s). The **strict
  per-method gate is retained unchanged** for user-added and marketplace
  scripts (untrusted) — no weakening of the security model for non-shipped
  code.
- **Dependencies:** none (it *unblocks* UX-11's acceptance).
- **Risk:** MED (touches the permission path; must not weaken the gate for
  untrusted scripts). **Confidence 8/10.**
- **Acceptance (this WU):** after accepting "Trust this dapp" once, opening the
  Poll dapp on a later session shows real polls with **zero** additional
  prompts; a user-added script still prompts per-method exactly as before.
- **Commit:** `feat(dapps): UX-10 trust-this-dapp grant for shipped example`

---

### Wave 2 — file splits (independent across different files)

#### TD-10 — Split `bookmarks_screen.dart` (2119 lines) into cohesive files
- **Problem:** the app's largest file crams 6 concerns (screen scaffold, a
  ~1040-line canister-call builder sheet, args editor, recent-calls list,
  well-known-canister catalog, saved-bookmarks list).
- **Grounding (class/line map):**
  | Lines | Concern |
  |---|---|
  | 332–1370 | `CanisterClientSheet` + state (~1040 lines — the bulk) |
  | 1371–1527 | `_ArgsEditor` |
  | 1528–1708 | `_RecentCallsList` |
  | 1709–1911 | `WellKnownCanister` + `_WellKnownList` + `_WellKnownCard` |
  | 1912–2119 | `_BookmarksList` |
- **Change (one commit per file):**
  1. `lib/widgets/canister_client_sheet.dart` ← `CanisterClientSheet` (do FIRST —
     removes ~half the file).
  2. `lib/widgets/canister_args_editor.dart` ← `_ArgsEditor`.
  3. `lib/widgets/recent_calls_list.dart` ← `_RecentCallsList`.
  4. `lib/widgets/well_known_canisters.dart` ← `WellKnownCanister` + 2 widgets.
  5. `lib/widgets/bookmarks_list.dart` ← `_BookmarksList`.
  - Promote moved classes to public (drop `_`); move imports with them. Pure
    move, byte-identical behavior.
- **Acceptance:** `just test-feature canister-client` (or the canister tests)
  green after each commit; `wc -l bookmarks_screen.dart` ≤ ~400.
- **Risk:** MED (large file; clean seams). **Confidence 9/10.**
- **Commit(s):** `refactor(bookmarks): TD-10a extract CanisterClientSheet`, etc.

#### TD-11 — Split `script_details_dialog.dart` (1526 lines)
- **Problem:** the most-traversed dialog holds 3 concerns: dialog shell + tabs,
  a reviews subsystem (~246 lines), and a versions + diff subsystem (~272 lines).
- **Change:**
  1. `lib/widgets/script_details/reviews_tab.dart` ← reviews block.
  2. `lib/widgets/script_details/versions_tab.dart` ← versions block + diff.
  3. (Optional, only if the diff is clearly small) unify `_buildWideLayout` /
     `_buildNarrowLayout` into one `LayoutBuilder`-driven adaptive layout.
     **YAGNI** if the duplication isn't obviously small — just extract the tabs.
- **Risk:** MED (tab extraction LOW; layout unification needs visual check under
  Xvfb). **Confidence 8/10.**
- **Commit:** `refactor(script-details): TD-11 extract reviews + versions tabs`

---

### Wave 3 — touches the split files (after Wave 2 settles)

#### UX-5 — Details dialog: lazy-load Reviews/Versions per-tab + paid-script purchase CTA
- **Problem:** `initState` fires **all three** loads at once (preview + reviews +
  versions) → triple spinner/error on slow/offline links. Separately, paid
  scripts have `onDownload: null` and **no in-dialog purchase CTA** → dead end.
- **Grounding:** `widgets/script_details_dialog.dart:50-55` (initState triple-load);
  `screens/scripts_screen.dart:477` (`onDownload: script.price == 0 ? … : null`).
- **Change:** (a) load only Details/preview on open; fetch reviews/versions when
  their tab is first selected (track a `_loadedTabs` set). (b) When
  `script.price > 0`, render a *"Purchase & Download"* primary action wiring to
  the existing purchase flow.
- **Dependencies:** after **TD-11** (same file).
- **Risk:** MED. **Confidence 8/10.**
- **Commit:** `feat(details): UX-5 lazy-load tabs + paid-script purchase CTA`

#### UX-4 — Canisters: collapse the inline Add-Bookmark form behind a button
- **Problem:** the `BookmarkComposer` form (Canister ID / Method / Label / Add)
  is always rendered inline on the explore screen, pushing Recent Calls below the
  fold.
- **Grounding:** `bookmarks_screen.dart:169-181` (always-inline `BookmarkComposer`).
- **Change:** render a compact `OutlinedButton.icon` ("+ Add Bookmark") that
  expands the composer on tap and auto-collapses after save. Keep the empty-state.
- **Dependencies:** after **TD-10** (same file).
- **Risk:** LOW. **Confidence 8/10.**
- **Commit:** `feat(canisters): UX-4 collapse inline Add-Bookmark form`

---

### Wave 4 — cross-cutting

#### UX-9 (finish) — Surface-specific keyboard shortcuts
- **Problem:** `Alt+3` (Dapps) + Canisters `/`/`Esc` are done; **remaining**:
  Dapps runner (`R`=Refresh, `Esc`=back), Details dialog (`Esc`=close,
  `Enter`=primary action, ←/→ tab traversal), Account (`mod+S`=save, `Esc`=back).
- **Change:** add to `kShortcutSpecs` + wire `Shortcuts`/`Actions` per surface;
  all appear in the `?` help sheet.
- **Dependencies:** after Waves 2–3 (so the targets exist).
- **Risk:** MED. **Confidence 8/10.**
- **Commit:** `feat(ux): UX-9 finish surface-specific keyboard shortcuts`

---

## 3. Dependency graph

```
  Wave 1 (parallel, independent) — original 7 COMPLETE; UX-10 added & ACTIVE:
    ✅ TD-8 (d190be3d, +stale-comment 31d1149c)   ✅ TD-9 (76402018, redirected)
    ✅ TD-13 (4a2cbb83)                            ✅ UX-13 (7648f636)
    ✅ UX-12 (3b0f05d8)                            ✅ TQ-4 (3e29990d)
    ✅ UX-11 (7f543480) — impl DONE, acceptance PENDING-UX-10
    🆕 UX-10 (trust-this-dapp grant) — ACTIVE; unblocks UX-11 acceptance
        UX-11 acceptance ─► after UX-10

  Wave 2 (file splits, parallel across different files):
    TD-10 (bookmarks_screen.dart)   TD-11 (script_details_dialog.dart)

  Wave 3 (touches the split files):
    UX-4 ─► after TD-10          UX-5 ─► after TD-11

  Wave 4 (cross-cutting):
    UX-9 (finish) ─► after Waves 2–3

  Flagged (NOT auto-executed):
    A-4 (vault zero-knowledge migration) ─► human decision (HIGH; see TODO.md)
    Key-label editing backend endpoint   ─► optional feature (1–2 days)
```

---

## 4. Definition of Done + acceptance (mirrors prior plans)

A WU/track is DONE when **all** of:
- [ ] **User access:** reachable in the running app (UI/CLI), not backend-only.
- [ ] **PoC demonstrated** end-to-end before productionizing.
- [ ] **Tests:** the WU's named tests + `just test-feature <name>` pass; a new
      test codifies the behavior (positive + negative/edge where applicable).
- [ ] **Clean:** `cd apps/autorun_flutter && flutter analyze` warning-clean.
- [ ] **Rust clean:** `cargo test` from repo root green.
- [ ] **Minimal diff;** no zombie code / dead imports / legacy comments.
- [ ] **Fail-loud:** no `try { … } catch (_) {}`, no silent no-ops.
- [ ] **Confidence ≥ 8/10** (else STOP and ask).

### Full-gate command set (before final sign-off)
```bash
just test-feature scripts        # TD-8, UX-5, UX-9 (parts)
just test-feature canister-client# TD-10, UX-4
just test-feature marketplace    # TQ-4 (harness); TD-9 redirected off marketplace
just test-feature dapps          # UX-10, UX-11 (acceptance), UX-12
flutter test test/widgets/offline_banner_test.dart   # TD-9 (token-derived warning color)
cd apps/autorun_flutter && flutter analyze
just test                        # Rust + Flutter full suite
# TD-9 (redirected, DONE 76402018): the genuine residual (offline_banner amber
# warning) is now token-derived. The 9 cited literals are documented-bespoke
# (call-type / purchase-CTA / favorite-heart) and intentionally KEPT — do NOT
# expect them to disappear:
rg "AppDesignSystem.warningColor" apps/autorun_flutter/lib/widgets/offline_banner.dart | wc -l  # TD-9: ≥1 (token in use)
wc -l apps/autorun_flutter/lib/screens/bookmarks_screen.dart         # TD-10: ≤ ~400
```

---

## 5. What is explicitly OUT OF SCOPE (with justification)

- **A-4 vault migration** — architectural; awaiting human decision (§1).
- **Key-label editing backend endpoint** — feature (1–2 days); human to prioritise.
- **TD-12 marketplace service split** — low ROI (flat file); do when next touching.
- **UX-6 lightweight preview endpoint** — needs a backend route (cross-cutting);
  defer.
- **UX-8** — largely resolved by the local-only account body; recommend CLOSE.
- **Phase 2 embedded webview** — blocked (no root for WPE libs); deferred.
- **R-2..R-5 Flutter Web runtime** — deferred (multi-day).
```
