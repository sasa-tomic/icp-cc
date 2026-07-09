# Next Iteration Plan — Tech Debt · Test Quality · UX (Dapps + Round-5)

> **⚠️ SUPERSEDED re: Flutter Web.** This plan (2026-07-04) states the
> "R-2..R-5 Flutter Web runtime — deferred". That is **stale**: all of
> R-1..R-5, R-3a, R-3b, secp256k1-on-Web, and Web local stores are
> **COMPLETE** now. For current Web status see `docs/BROWSER_SUPPORT.md`
> and `docs/specs/2026-07-09-web-remaining-gaps.md`. The non-Web portions
> remain the design record.

- **Status:** ✅ **ALL FOUR WAVES COMPLETE** (Wave 1 incl. UX-10 pulled into
  scope, Wave 2, Wave 3, Wave 4). Per-WU commit hashes in §2; headline outcome
  + deferred follow-ups in §6. Earlier draft of this doc marked only Wave 1
  done (commit `c1912672`); this revision records Waves 2–4 landing. Extends
  `NEXT_PHASE_PLAN.md` (COMPLETE), `UI_EXCELLENCE_PLAN.md` (COMPLETE), and
  `EXAMPLE_DAPP_INTEGRATION_PLAN.md` (Phase 1 COMPLETE; Phase 2 webview
  DEFERRED). Grounded in two fresh audits (2026-07-04):
  `audit_techdebt_tests.md` + `audit_ux_round5.md` (both on disk under
  `/tmp/opencode/`; the UX round captured in this doc's findings).
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

## 1. Architectural issue — RESOLVED: A-4 vault zero-knowledge migration COMPLETE

### A-4 — Vault crypto is now genuinely zero-knowledge ✅ RESOLVED (executed option (b))

- **Original problem (now fixed):** `HUMAN_EXPECTATIONS.md` and `AGENTS.md`
  both stated the vault is **zero-knowledge**, but the code previously did NOT
  implement that — the client sent the vault password in plaintext to
  `/api/v1/vault`, and the **backend** derived the Argon2id key and did the
  AES-256-GCM. A compromised server / DB dump + a captured password could
  decrypt every vault. The `vault.rs:4` doc-comment *"Decryption happens
  client-side"* was previously false; TD-13 (`4a2cbb83`) made the comment
  honest as the interim while the decision was pending.
- **Resolution:** **option (b) executed in full** (the multi-day migration).
  Argon2id + AES-256-GCM now run **client-side** via the Rust FFI bridge
  (`apps/autorun_flutter/lib/services/vault_crypto_service.dart`); the vault
  password never leaves the device; `/api/v1/vault` is a pure opaque-blob
  store; server-side vault crypto is deleted
  (`rg "encrypt_vault|aes_gcm|Aes256Gcm" backend/src` is empty). Proven
  end-to-end by the W5 integration round-trip test.
- **Commit hashes:** schema fix `b92a54d4`, opaque-blob endpoints `30d98a3e`,
  VaultCryptoService `714c8568`, PasskeyService rewrite `b4d709ab`, screens
  `d96661af`, ZK round-trip test `f1d425d5`.
- **Full plan + outcome:** `docs/specs/A4_VAULT_ZK_MIGRATION_PLAN.md` (W0–W6
  all COMPLETE; headline outcome in its §11).
- **This entry is retained as history** (the §2 WU `TD-13` that made the lie
  honest in the interim is also retained as a completed WU). No further action.

---

## 2. Work Units

> Conventions (same as prior plans): every WU follows the **PoC-first** workflow.
> One commit per WU (file-split WUs: one commit per file). Every commit leaves
> `flutter analyze` clean and the cited tests green. **TD = tech debt,
> TQ = test quality, UX = UX.** Numbering continues prior plans.

### Wave 1 — independent, low-risk, parallel

> **Status (2026-07-04):** the original 7 Wave-1 items are all COMPLETE —
> TD-8 `d190be3d` (drive-by stale-comment `31d1149c`), TD-9 `76402018`
> (redirected — see its body), TD-13 `4a2cbb83`, UX-11 `7f543480`
> (acceptance unlocked by UX-10 below — see §6), UX-12 `3b0f05d8`
> (part (a) only — part (b) deferred; see body + §6), UX-13 `7648f636`,
> TQ-4 `3e29990d`. **UX-10** (below) was pulled INTO scope after the round
> began and is also COMPLETE: `26e22056`. Wave 1 has no remaining ACTIVE
> items.

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

#### TD-13 — Make the vault code comments honest (interim, pending A-4 decision) ✅ DONE `4a2cbb83` (subsequently superseded by A-4's full execution — see §1)
- **Problem:** `vault.rs:4` claimed *"Decryption happens client-side"* — false at the time.
  `vault_unlock_screen.dart:61` TODO was already honest. The lie had to go while A-4
  was pending.
- **Change:** rewrote the `vault.rs` module doc-comment to describe the THEN-current
  model accurately (server-side Argon2id + AES-GCM) + added a `// TODO(A-4):`
  pointing to the client-side-crypto migration recorded in `TODO.md`. Did NOT
  touch `HUMAN_EXPECTATIONS.md` (intent of record).
- **Status:** shipped as the honest interim. **A-4 has since been executed in full**
  (see §1 above + `docs/specs/A4_VAULT_ZK_MIGRATION_PLAN.md`); the interim
  `TODO(A-4)` markers were removed in W3/W4, and `vault.rs` now documents the
  actual client-side-crypto reality.
- **Risk:** LOW (comments only). **Confidence 10/10.**
- **Commit:** `docs(vault): TD-13 honest code comments pending A-4 zero-knowledge decision`

#### UX-11 — Poll dapp auto-loads on open (not "Polls (0)" + manual Refresh) ✅ DONE `7f543480` · acceptance UNLOCKED by UX-10 (`26e22056`)
- **Status:** implementation COMPLETE (`7f543480`) — `init` now emits the
  whoami+listPolls batch so polls load on open instead of "Polls (0)". The
  **acceptance criterion was reworded** (below) to depend on **UX-10**;
  UX-10 (`26e22056`) has now landed, so acceptance is **MET** (see §6 for
  the live-verified outcome: real canister, one prompt on first open, zero
  on restart).
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
  open). **ACCEPTANCE MET** by UX-10 (`26e22056`) — live-verified; see §6.
- **Grounding:** `lib/examples/06_icp_poll.js` `init`/`refreshEffects`
  (auto-load done); permission gate around the effect dispatcher in
  `lib/screens/dapp_runner_screen.dart` (the UX-10 target).
- **Risk:** LOW (impl); MED (acceptance gated on UX-10). **Confidence 9/10**
  (impl), **8/10** (acceptance — UX-10 has landed; live-verified in §6).
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

#### UX-12 — Dapps Connection panel honesty ✅ DONE `3b0f05d8` (part (a) only; part (b) DEFERRED — see §6)
- **Problem:** collapsed-by-default Connection panel + *"Loading saved
  connection…"* copy (implies network; it's only SharedPreferences) hides the
  recovery path when a fresh `dfx start --clean` changes the canister ID.
- **Grounding:** `screens/dapp_runner_screen.dart:242` (`initiallyExpanded:
  false`), `:245-253` (loading copy), `:338-340` (spinner).
- **Change DELIVERED (part a):** reworded the transient to
  *"Reading saved connection…"* (honest local read); added an actionable
  recovery hint at the top of the **expanded** panel naming the exact
  command that invalidates ids (`dfx start --clean`) and the recovery action
  (`dfx canister id …` output → Apply). No happy-path behaviour change.
- **Change DEFERRED (part b — see §6 follow-up UX-12(b)):** auto-expand the
  panel + surface a *"Canister unreachable"* hint when the first effect
  actually fails reachability. Deliberately scoped out of this WU: the
  live UX reviewer found the always-visible expanded-panel hint (part a)
  already makes the stale-canister-id-after-`dfx-clean` path discoverable
  enough for a teaching example, and wiring the reactive auto-expand into
  the effect-dispatch path is a non-trivial follow-up better done as its
  own small WU.
- **Risk:** LOW. **Confidence 8/10.**
- **Commit:** `feat(dapps): UX-12 honest Connection panel + reachable recovery` (`3b0f05d8`)

#### TQ-4 — Fold the marketplace test `MaterialApp` harness (mirror TQ-3) ✅ DONE `3e29990d`
- **Problem:** `test/features/marketplace/` rebuilds `MaterialApp(...)` ~10×
  across 5 files. TQ-3 solved this for scripts.
- **Change:** add `test/features/marketplace/_marketplace_test_harness.dart` with
  `pumpMarketplaceWidget(tester, child, {...})`; migrate the ~10 callers
  mechanically.
- **Risk:** LOW. **Confidence 8/10.**
- **Commit:** `refactor(test): TQ-4 fold marketplace MaterialApp harness`

#### UX-10 — "Trust this dapp" grant for the shipped example (permission-gate fix) ✅ DONE `26e22056` (pulled into scope mid-iteration)
- **Status:** COMPLETE (`26e22056`) — previously **omitted** from the plan
  (not in §5 out-of-scope; simply missed), then pulled into Wave 1 after the
  original 7 completed. It is the dependency that made **UX-11's** reworded
  acceptance achievable. **UX-11 acceptance is now MET** (live-verified; see
  §6).
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

### Wave 2 — file splits (independent across different files) ✅ COMPLETE

#### TD-10 — Split `bookmarks_screen.dart` (2119 lines) into cohesive files ✅ DONE `23b17fbf` (2119 → 307; 5 widget files extracted in one commit)
- **Result:** the app's largest file crammed 6 concerns (screen scaffold, a
  ~1040-line canister-call builder sheet, args editor, recent-calls list,
  well-known-canister catalog, saved-bookmarks list). Shipped as a single
  commit extracting all 5 widgets (`bookmarks_list.dart`,
  `canister_args_editor.dart`, `canister_client_sheet.dart`,
  `recent_calls_list.dart`, `well_known_canisters.dart`) — pure mechanical
  move, byte-identical behavior, classes promoted to public.
- **Acceptance MET:** `wc -l bookmarks_screen.dart` = **307** (target ≤ ~400);
  canister-client tests green.
- **Grounding (class/line map, pre-split):**
  | Lines | Concern |
  |---|---|
  | 332–1370 | `CanisterClientSheet` + state (~1040 lines — the bulk) |
  | 1371–1527 | `_ArgsEditor` |
  | 1528–1708 | `_RecentCallsList` |
  | 1709–1911 | `WellKnownCanister` + `_WellKnownList` + `_WellKnownCard` |
  | 1912–2119 | `_BookmarksList` |
- **Original plan (retained for reference):**
  1. `lib/widgets/canister_client_sheet.dart` ← `CanisterClientSheet` (do FIRST —
     removes ~half the file).
  2. `lib/widgets/canister_args_editor.dart` ← `_ArgsEditor`.
  3. `lib/widgets/recent_calls_list.dart` ← `_RecentCallsList`.
  4. `lib/widgets/well_known_canisters.dart` ← `WellKnownCanister` + 2 widgets.
  5. `lib/widgets/bookmarks_list.dart` ← `_BookmarksList`.
  - Promote moved classes to public (drop `_`); move imports with them. Pure
    move, byte-identical behavior.
- **Risk:** MED (large file; clean seams). **Confidence 9/10.**
- **Commit:** `refactor(bookmarks): TD-10 split bookmarks_screen into cohesive widget files` (`23b17fbf`)

#### TD-11 — Split `script_details_dialog.dart` (1526 lines) ✅ DONE `aa231ea3` (1526 → 1003 at split; 3 files extracted)
- **Result:** the most-traversed dialog held 3 concerns (dialog shell + tabs,
  a reviews subsystem, and a versions + diff subsystem). Split into the dialog
  shell + 3 cohesive files under `lib/widgets/`: `script_details_helpers.dart`
  (shared `formatDate`), `script_details_reviews_tab.dart`
  (`ScriptDetailsReviewsTab` + 4 private widgets), and
  `script_details_versions_tab.dart` (`ScriptDetailsVersionsTab` + diff).
  Pure mechanical extraction — no behavior, logic, or copy changes. The
  optional `_buildWide/NarrowLayout` unification was **declined as YAGNI**
  (per the plan's own guard). Note: subsequent commits (UX-5 `448c8fab`,
  UX-9 `f54bb58f`) added logic to the dialog shell, which is now **1057**
  lines — the TD-11 split figure of 1003 is the post-split, pre-later-WUs
  baseline.
- **Risk:** MED (tab extraction LOW). **Confidence 8/10.**
- **Commit:** `refactor(script-details): TD-11 split script_details_dialog into cohesive files` (`aa231ea3`)

---

### Wave 3 — touches the split files (after Wave 2 settles) ✅ COMPLETE

#### UX-5 — Details dialog: lazy-load Reviews/Versions per-tab + paid-script purchase CTA ✅ DONE `448c8fab` (lazy-load delivered; purchase CTA HONESTLY DEFERRED)
- **Result (lazy-load delivered):** `initState` previously fired **all three**
  loads at once (preview + reviews + versions) → triple spinner/error on
  slow/offline links. UX-5 replaces that with lazy-loading: only the visible
  Details/preview tab loads on open; the Reviews and Versions tabs fetch the
  first time they are selected and then cache (re-selecting does not re-fetch).
  Implementation is a small parent-owned gate (the post-TD-11 tabs are
  conditionally created/disposed on every switch, so per-tab caching would
  need `IndexedStack` or keep-alive plumbing — heavier than gating in the
  parent, which already owns the load lifecycle).
- **Purchase CTA — HONESTLY DEFERRED (not silently dropped):** the planned
  in-dialog *"Purchase & Download"* CTA for `script.price > 0` depends on a
  real paid-script purchase flow. Live verification against the running
  marketplace found paid scripts currently surface as **NOT FOUND** (no live
  paid listings), so the CTA could not be exercised end-to-end and was NOT
  shipped as a stub. The existing **"Payments Coming Soon"** affordance is
  retained as the honest placeholder. Wiring the CTA is a follow-up gated on
  a real paid listing existing.
- **Grounding:** `widgets/script_details_dialog.dart` (parent-owned
  `_loadedTabs`-style gate); `screens/scripts_screen.dart:477`
  (`onDownload: script.price == 0 ? … : null` — unchanged for now).
- **Dependencies:** after **TD-11** (same file) — MET.
- **Risk:** MED. **Confidence 8/10.**
- **Commit:** `feat(ux): UX-5 lazy-load Details dialog tabs` (`448c8fab`)

#### UX-4 — Canisters: collapse the inline Add-Bookmark form behind a button ✅ DONE `98f5a05c`
- **Result:** the `BookmarkComposer` form (Canister ID / Method / Label / Add)
  was always rendered inline on the explore screen, pushing Recent Calls below
  the fold. UX-4 collapses it behind a compact `OutlinedButton.icon`
  ("+ Add Bookmark") that expands the composer on tap and auto-collapses after
  save; the empty-state is kept.
- **Grounding:** `widgets/bookmark_composer.dart` (collapsed/expanded state);
  new test `test/features/canister_client/bookmarks_inline_add_test.dart`.
- **Dependencies:** after **TD-10** (same file) — MET.
- **Risk:** LOW. **Confidence 8/10.**
- **Commit:** `feat(ux): UX-4 inline Add-Bookmark form` (`98f5a05c`)

---

### Wave 4 — cross-cutting ✅ COMPLETE

#### UX-9 (finish) — Surface-specific keyboard shortcuts ✅ DONE `97b42da3` (Dapps runner R/Esc + Account Ctrl+S/Esc) + `f54bb58f` (Details ←/→/Esc)
- **Result:** completed the surface-specific shortcut sweep (prior carries had
  done `Alt+3` for Dapps and Canisters `/`/`Esc`). Two commits shipped:
  - `97b42da3` — Dapps runner (`R`=Refresh, `Esc`=back) + Account
    (`mod+S`=save, `Esc`=back), both added to `kShortcutSpecs` and surfaced
    in the `?` help sheet.
  - `f54bb58f` — Details dialog (`Esc`=close, ←/→ tab traversal), rebuilt the
    dialog's keyboard wiring on top of the post-TD-11 / post-UX-5 shell.
  All shortcuts appear in the `?` help sheet; both commits include widget
  tests (`account_profile/keyboard_shortcuts_test.dart`,
  `features/dapps/dapp_runner_screen_test.dart`,
  `marketplace/script_details_keyboard_test.dart`).
- **Dependencies:** after Waves 2–3 (so the targets exist) — MET.
- **Risk:** MED. **Confidence 8/10.**
- **Commits:** `feat(ux): UX-9 keyboard shortcuts for Dapps runner + Account`
  (`97b42da3`); `feat(ux): UX-9 keyboard shortcuts for Details dialog`
  (`f54bb58f`)

---

## 3. Dependency graph

```
  Wave 1 (parallel, independent) — ✅ ALL COMPLETE (incl. UX-10 pulled in):
    ✅ TD-8 (d190be3d, +stale-comment 31d1149c)   ✅ TD-9 (76402018, redirected)
    ✅ TD-13 (4a2cbb83)                            ✅ UX-13 (7648f636)
    ✅ UX-12 (3b0f05d8) — part (a) only; part (b) deferred (§6)
    ✅ TQ-4 (3e29990d)
    ✅ UX-11 (7f543480) — acceptance UNLOCKED by UX-10
    ✅ UX-10 (26e22056) — trust-this-dapp grant; unblocked UX-11 acceptance

  Wave 2 (file splits) — ✅ COMPLETE:
    ✅ TD-10 (23b17fbf) bookmarks_screen.dart 2119→307, 5 widgets extracted
    ✅ TD-11 (aa231ea3) script_details_dialog.dart 1526→1003, 3 files extracted

  Wave 3 (touches the split files) — ✅ COMPLETE:
    ✅ UX-4 (98f5a05c)  — after TD-10
    ✅ UX-5 (448c8fab)  — after TD-11; lazy-load delivered, purchase CTA deferred

  Wave 4 (cross-cutting) — ✅ COMPLETE:
    ✅ UX-9 (97b42da3 + f54bb58f) — after Waves 2–3

  Flagged (resolved this iteration):
    ✅ A-4 (vault zero-knowledge migration) ─► EXECUTED option (b); see §1 +
       docs/specs/A4_VAULT_ZK_MIGRATION_PLAN.md (W0–W6 COMPLETE)
    Key-label editing backend endpoint   ─► optional feature (1–2 days; still open)
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

- **A-4 vault migration** — ✅ RESOLVED. Option (b) executed in full; see §1
  above and `docs/specs/A4_VAULT_ZK_MIGRATION_PLAN.md` (W0–W6 COMPLETE with
  commit hashes; outcome in its §11). The vault is genuinely zero-knowledge.
- **Key-label editing backend endpoint** — feature (1–2 days); human to prioritise.
- **TD-12 marketplace service split** — low ROI (flat file); do when next touching.
- **UX-6 lightweight preview endpoint** — needs a backend route (cross-cutting);
  defer.
- **UX-8** — largely resolved by the local-only account body; recommend CLOSE.
- **Phase 2 embedded webview** — blocked (no root for WPE libs); deferred.
- **R-2..R-5 Flutter Web runtime** — deferred (multi-day).
- **UX-5 paid-script purchase CTA** — gated on a real paid marketplace listing
  existing (live verification found paid listings currently surface as NOT
  FOUND; the existing "Payments Coming Soon" affordance is retained as the
  honest placeholder). See §2 UX-5.
- **UX-12(b) reactive auto-expand** — auto-expand the Dapps Connection panel
  on a canister-unreachable effect failure. UX-12 shipped part (a) only (§2).

---

## 6. Iteration complete — headline outcome + deferred follow-ups

**All four waves are landed.** 12 work units shipped across 13 commits
(Wave 1: 8 incl. the drive-by; Wave 2: 2; Wave 3: 2; Wave 4: split into 2
commits).

### Headline outcome (the point of the iteration)

The shipped Poll dapp now delivers the **"one click, no setup"** teaching
promise from `HUMAN_EXPECTATIONS.md` §3 — **verified live** against the
real `dfx`-deployed canister (not a mock):

- **First open:** exactly **one** prompt — the UX-10 *"Trust this dapp?"*
  grant dialog — then real polls + tallies render within ~1s.
- **Second open (restart):** **zero** prompts — the trust grant persists in
  `SharedPreferences` (keyed by `descriptor.id`) and is awaited before any
  effect dispatches, so no redundant prompt flashes on cold start.
- **Unchanged:** user-added and marketplace scripts (untrusted) still go
  through the strict per-method gate exactly as before — no weakening of
  the security model for non-shipped code.

This is UX-10 (`26e22056`) + UX-11 (`7f543480`) together closing the loop
the round-5 audit opened. The prior "Polls (0) + manual Refresh +
per-method prompt gauntlet" experience is gone.

### Deferred from this iteration (recorded; not silently dropped)

| Item | Why deferred | Size | Tracking |
|---|---|---|---|
| **UX-5 paid-script purchase CTA** | Live marketplace has no real paid listing to exercise the flow end-to-end (paid scripts surface as NOT FOUND). Shipped as a stub would violate the no-slop rule. Existing *"Payments Coming Soon"* retained. | S-M | §2 UX-5; TODO.md next-iteration candidates |
| **UX-12(b) reactive auto-expand** | UX-12 shipped part (a) (honest copy + always-visible expanded-panel recovery hint). Part (b) (auto-expand the panel on a canister-unreachable effect failure) is a non-trivial wiring into the effect-dispatch path, better as its own WU. The expanded-panel hint already makes the stale-canister-id-after-`dfx-clean` path discoverable for a teaching example. | S | §2 UX-12; TODO.md next-iteration candidates (UX-12(b)) |

### Next-iteration candidates surfaced by the final verifier + live UX reviewer

Captured in `TODO.md` under **Next Iteration Candidates** (this iteration's
live review pass). Headline additions: UX-12(b), a "Manage trust" UI to
revoke a granted dapp-level trust (`DappTrustStore.clear()` exists, no UI
yet), an inline *"Create a profile to vote"* CTA on the Dapps runner for
keyless viewers, and key-label editing (field present-but-disabled, needs
the backend endpoint). **A-4 (vault zero-knowledge) is now RESOLVED** — see
§1 above and `docs/specs/A4_VAULT_ZK_MIGRATION_PLAN.md`.
```
