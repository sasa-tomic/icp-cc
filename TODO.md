# ICP Script Marketplace — TODO

A focused, current backlog. Historical work lives in git history and the migration
ADR (`docs/specs/SCRIPTING_RUNTIME_MIGRATION.md`); the Lua-sunset execution record is
in `docs/specs/CLEANUP_PLAN.md`. Architecture reference at the bottom.

## Active Work

**Scripting runtime is TypeScript/QuickJS-only** as of 2026-06-30. The Lua sunset is
complete (`docs/specs/CLEANUP_PLAN.md` WU-1..WU-10 done; `SCRIPTING_RUNTIME_MIGRATION.md`
Phase 4 done). There is no active scripting work.

Genuinely open items are listed below.

> **Next-phase tech-debt / test-quality / UX initiative: COMPLETE.** See
> `docs/specs/NEXT_PHASE_PLAN.md` (TD-1..5, TQ-1..3, UX-1) and
> `docs/specs/UX_REVIEW_ROUND4.md` (UX-2/3/7/9). Highlights: all local file I/O now
> timeout-bounded (TD-1); backend has a real cancellation/graceful-shutdown path (TD-2);
> no panics across the FFI boundary (TD-4); single-source semantic status colors (TD-5);
> WU-2/WU-3 snackbar actions now have real widget tests (TQ-1); ~233 false-confidence
> scripts tests dropped + a shared harness (TQ-3); keypair ownership invariant enforced
> (A-3a/c/d); `flutter build web` unblocked (R-1); Canisters label made honest (UX-2),
> searchable method picker (UX-3), local keys visible without backend (UX-7), intuitive
> keyboard shortcuts (UX-9).

## Known Issues

> **✅ RESOLVED (A-4, vault zero-knowledge):** the vault is **now genuinely
> zero-knowledge**. Argon2id + AES-256-GCM run **client-side** via the Rust FFI
> bridge (`apps/autorun_flutter/lib/services/vault_crypto_service.dart`); the
> password never leaves the device; the backend is a pure opaque-blob store
> (`backend/src/vault.rs` has no vault-crypto fns; recovery-code hashing only).
> End-to-end ZK proven by the W5 integration round-trip test
> (`test/features/vault/zk_integration_test.dart`). Commits: `b92a54d4`,
> `30d98a3e` (W4 backend opaque-blob + schema fix), `714c8568` (W1
> VaultCryptoService), `b4d709ab` (W2 PasskeyService encrypts locally),
> `d96661af` (W3 screens use local crypto), `f1d425d5` (W5 ZK round-trip test).
> Plan + outcome: `docs/specs/A4_VAULT_ZK_MIGRATION_PLAN.md`. (The former HIGH
> "human decision required" item is closed; option (b) — true client-side
> crypto — was executed in full.)

| Issue | Location | Severity | Notes |
|-------|----------|----------|-------|
| **Paid-script bundle is not server-side gated** (security) | `backend/src/main.rs::get_script` | HIGH | `GET /api/v1/scripts/:id` returns the full `bundle` for paid scripts with no purchase verification — only the Dart `downloadScript` wrapper checks `price > 0`. A paid script's source is readable by anyone hitting the details endpoint directly. Surfaced while implementing UX-6 (the preview path is now safe; the full-detail path is not). Needs a human decision on the server-side paywall shape. See **Architectural Issues Requiring Review** below. |
| Web *runtime* features are stubbed (build compiles) | `lib/rust/native_bridge_web.dart` | MEDIUM | R-1 unblocked `flutter build web` (conditional FFI split). Native-only calls throw honest `UnsupportedError`; full Web runtime is R-2..5 (see Future). |

## Architectural Issues Requiring Review

> Per AGENTS.md: issues needing a human decision. Do NOT work around these with
> symptom fixes — the root cause must be addressed.

- **Paid-script bundle is not server-side gated.** `GET /api/v1/scripts/:id`
  (`backend/src/main.rs::get_script`) returns the full `bundle` for paid scripts
  with **no purchase verification**. The paywall today exists only in the Dart
  `downloadScript` wrapper (`price > 0` check), which is trivially bypassed by a
  direct API call. Surfaced while implementing UX-6 (the new `/preview` path is
  safe by construction — no `bundle` field; but the existing `/scripts/:id`
  detail path leaks paid source). **Decision needed:** the shape of server-side
  purchase verification (signature challenge? purchase-record table? entitlement
  check at the handler?) and whether to gate the `bundle` field behind it while
  keeping metadata (title/author/description/stats) public. This intersects
  UX-5 (real ICP-token payments) — likely the same body of work.

## Next Iteration Candidates

Surfaced by the final live UX reviewer + verifier for the Next-Iteration plan
(all four waves now COMPLETE — see `docs/specs/NEXT_ITERATION_PLAN.md` §6).
Sized **S** ≈ half-day, **M** ≈ 1–2 days.

- **UX-12(b) — reactive Connection-panel auto-expand.** ✅ DONE — the Dapps
  Connection panel now auto-expands and surfaces a *"Canister unreachable"* hint
  the first time a canister call fails reachability. The Rust FFI emits a typed
  `kind` discriminator (`bfc55e52`) that the Dart host matches on
  (`CanisterFailureKind.isUnreachable`); net/invalid-canister-id → expand, candid
  / permission-denial → leave collapsed. Closes the
  stale-canister-id-after-`dfx-clean` stumble reactively. (Dart half landed in
  `53261a10` alongside UX-10; activated by the `kind` tag in `bfc55e52`.)
- **Revoke "Trust this dapp" UI.** ✅ DONE — the Dapps runner now exposes a
  *"Revoke trust"* affordance (`_kRevokeTrustButton`) that calls
  `DappTrustStore.clear(descriptorId)` and flips the in-memory trust flag
  (`dapp_runner_screen.dart`).
- **Inline "Create a profile to vote" CTA on the Dapps runner.** ✅ DONE — a
  keyless viewer of the Poll dapp now sees a one-tap *"Create a profile to
  vote"* button (`_kCreateProfileToVoteLabel`) that deep-links into profile
  creation (`dapp_runner_screen.dart`).
- **Key-label editing.** ✅ DONE — investigation proved the keypair label is a
  **LOCAL-only** attribute (`ProfileKeypair.label` in secure storage; the
  backend `account_public_keys` table has no label column and never sends one).
  The prior "needs a backend endpoint" blocker was a misdiagnosis. The UI in
  `account_profile_screen.dart` is now editable (tap label / edit icon → rename
  dialog), wired to the pre-existing `ProfileController.updateKeypairLabel`.
  Frontend-only by design (YAGNI/KISS — a personal friendly name is not backend
  data). 4 widget tests added.

## Deferred (decided, with justification)

- **A-3b — structural `profileId` on `ProfileKeypair`.** The data-integrity contract is
  **already enforced** by A-3a's `assertUniqueKeypairOwnership` invariant at persist + load
  + import (`lib/services/profile_invariants.dart`), closing the real silent-key-loss
  vector. A-3b's marginal value is construction-time assertions + a queryable field; it
  keeps the flat secure-storage keying anyway, so it's KISS/YAGNI for now (wide blast
  radius: models/serializer/generator/controllers/many tests). The `account.dart` FIXMEs
  (L18/L307) were resolved by A-3d (`AddPublicKeyRequest` now takes a `ProfileKeypair`).
- **R-2..R-5 — full Flutter Web runtime.** R-1 makes Web **build & launch**; the
  conditional-import scaffolding is in place. Remaining: R-2 WebCrypto Ed25519 keys, R-3
  WASM QuickJS, R-4 Web secure storage (IndexedDB), R-5 Web passkeys + CORS. A separate
  multi-day initiative. See `docs/BROWSER_SUPPORT.md`.
- **UX-5 purchase CTA / UX-6 / UX-8 — remaining Round-4/5 polish.** UX-4
  (collapse inline Add-Bookmark, `98f5a05c`), UX-5 lazy-load Details tabs
  (`448c8fab`), and UX-9 (surface-specific keyboard shortcuts, `97b42da3` +
  `f54bb58f`) are DONE in the Next-Iteration plan. Still open: **UX-5 paid-script
  purchase CTA** (deferred — no live paid marketplace listing to exercise it;
  existing *"Payments Coming Soon"* retained — real ICP-token payments are a
  separate, larger initiative needing a human decision on the payment
  integration), **UX-8** (largely resolved by the local-only account body —
  recommend CLOSE). **UX-6 is ✅ DONE**: `GET /api/v1/scripts/:id/preview`
  returns a lightweight payload (no `bundle` field by construction); free scripts
  get a 50-line preview (~51% smaller than the full bundle), paid scripts get a
  20-line teaser and NEVER the full source; the Details dialog no longer
  full-downloads to render 50 lines, and never full-downloads a paid script.
  See `docs/specs/NEXT_ITERATION_PLAN.md`.
- **TD-7 — SQL column list** (`backend/src/models.rs::SCRIPT_COLUMNS_WITH_ACCOUNT`). Already
  guarded by the drift-detection test at `models.rs:418-424`.

## Future / Optional

Not started; pulled from the migration spec's open questions (`docs/specs/SCRIPTING_RUNTIME_MIGRATION.md` §11):

- **G2** — Android NDK cross-compile of the QuickJS/rquickjs cdylib (NDK is not present in the current environment).
- **G8** — `qjsc` bytecode precompilation for faster cold start (optional).
- **G12** — Resource-limit (memory/time) tuning against a real pilot-script load test.

## Architecture Reference

### Design Principles
- **Profile-centric**: keys belong to profiles, not standalone.
- **Untrusted code isolation**: TypeScript bundles run sandboxed in QuickJS (no IO); effects are executed by the host.
- **Fail fast**: strict validation, clear errors, no silent failures.
- **Zero redundancy**: the backend is the single source of truth.

### TS App Contracts (QuickJS)
A bundle exposes plain functions the host calls directly:
- `init(arg)            -> { state, effects: [] }`
- `view(state)          -> ui_v1` (a UI node tree)
- `update(msg, state)   -> { state, effects: [] }`

Effects: `icp_call`, `icp_batch`. The host resolves each effect and re-enters `update`
with `{ type: "effect/result", id, ok, data? | error? }`.

> Unlike the legacy Lua runtime, `init`/`update` return a single `{ state, effects }`
> object rather than Lua multireturn.

### UI_v1 Widget Types
Handled by `lib/widgets/ui_v1_renderer.dart`:
- **Layout**: `column`, `row`, `section`
- **Basic**: `text`, `button`, `text_field`
- **Selection**: `toggle`, `select`
- **Data**: `list`, `table`, `result_display`
- **Media**: `image`

---

## Update Guidelines
- Remove completed tasks immediately.
- Break complex tasks into subtasks.
- Priority: HIGH = MVP/critical, MEDIUM = significant UX, LOW = nice-to-have.
