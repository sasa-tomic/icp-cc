# ICP Script Marketplace — TODO

A focused, current backlog. Historical work lives in git history and the migration
ADR (`docs/specs/SCRIPTING_RUNTIME_MIGRATION.md`); the Lua-sunset execution record is
in `docs/specs/CLEANUP_PLAN.md`. Architecture reference at the bottom.

## Active Work

**Scripting runtime is TypeScript/QuickJS-only** as of 2026-06-30. The Lua sunset is
complete (`docs/specs/CLEANUP_PLAN.md` WU-1..WU-10 done; `SCRIPTING_RUNTIME_MIGRATION.md`
Phase 4 done). There is no active scripting work.

Genuinely open items are listed below.

> **Wave-7 security, functional, visual & tech-debt sweep: COMPLETE (2026-07-15,
> confidence 9/10).** See `docs/specs/2026-07-14-wave7-issue-hunt.md`
> (W7-1..W7-20, 35 commits across 3 phases). The headline was the **systemic
> backend auth-gating cluster**: 6 subsystems (vault, passkey register/delete,
> recovery generate, review, detail-entitlement, script-stats) all trusted a
> client-supplied `account_id` with ZERO auth — `account_id` is public. A new
> shared `signature_gate::verify_signed_account_request` (factors the proven
> entitlement pattern: resolve account_id SERVER-SIDE from the verified public key
> → verify Ed25519 → replay-prevention → audit fail-closed) gates every
> state-changing route. Also closed: **SQL injection** in the `category` filter
> (W7-1, live-proven exploit), **entitlement bundle leak** via GET (W7-2, paid
> source no longer reachable without a signed download), **non-constant-time**
> admin/recovery/webhook compares (W7-3), **permissive CORS** + TRACE/CONNECT
> (W7-4), **dead unauthenticated `update-script-stats`** removed (W7-16),
> **config-var leak** in ICPay 503 (W7-6 follow-up). Frontend: null-unsafe
> `success` check + `getScriptVersions` malformed-data → typed throw (W7-7),
> dead Versions tab removed (W7-8 — no `/versions` backend route), dead
> "Marketplace Website" link removed (W7-9), Polls contradictory identity fixed
> (W7-10), 26 Candid `startsWith` heuristics DRY'd into one typed classifier
> (W7-11). Robustness: `nonce` UNIQUE + TOCTOU kill (W7-011), typed
> `Environment` enum fail-closed, `eprintln!`→`tracing`, shared `tokio::Runtime`.
> UX: word-based avatar initials, run-panel iconUrl, distinct Copy labels,
> wizard placeholder, dapp-chip full+copyable principal, a11y dedup. Tests:
> `ScriptContextMenuSheet` + `ScriptEditorDialog` coverage (surfaced + fixed a
> non-BMP emoji crash), low-signal test cleanup. Dev workflow: reproducible
> `just web-dev-build`/`web-dev-serve` (kills the dead-host Web build default).
> Verify: `flutter analyze` clean; 2010 passed / 11 skipped; integration 49/49
> with `MARKETPLACE_API_PORT`; backend 308/308; clippy clean; live security +
> UX re-review PASS (no mocks).

> **Wave-6 functional/visual/tech-debt sweep: COMPLETE (2026-07-11, confidence 9/10).** See
> `docs/specs/2026-07-10-wave6-issues.md` (W6-1..W6-13, 14 commits). 13 work units:
> IC-agent proxy origin fix + friendly dapp errors + generic copy (W6-1), auth.rs
> substring-heuristic removal (W6-2, security), marketplace service `_decode` helper +
> fragile-status/status-bound/null-data/error-mask fixes (W6-3), `getCompatibleScripts`
> signature tightening (W6-4), profile_repository null-safe cast (W6-5), Versions-tab
> regression tests (W6-6), dead settings links fixed (W6-7), search no-match distinct
> empty state (W6-8), misc robustness (W6-9), a11y + icon polish (W6-10), REAL test
> signatures (W6-11), loud test guards + tautology/throwsA cleanup (W6-12), backend
> passkey/recovery/auth-middleware tests (W6-13 — surfaced+fixed **3 production passkey
> bugs**: wrong column name, missing `webauthn_challenges` table, string-vs-bytes
> credential lookup). Verify: `flutter analyze` clean; 1988 tests passed / 0 failed /
> 11 skipped; backend 224/224; clippy clean; live UX re-review PASS.

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
| **✅ RESOLVED:** paid-script `bundle` is now server-side gated | `backend/src/main.rs::get_script` | ~~HIGH~~ | `GET /scripts/:id` strips `bundle` for paid scripts unless the requester is the owner or holds a purchase record (`?account_id=`); the only paid-bundle path is the authenticated `POST /scripts/:id/download` (Ed25519-signed). See **ICPay / entitlement** below. |
| **✅ RESOLVED:** secp256k1 (alg=1) real on Web | `lib/rust/native_bridge_web.dart` | ~~LOW~~ | Pure-Dart BIP32 `m/44'/223'/0'/0/0` + RFC 6979 deterministic low-S ECDSA + RFC 5480 principal in `lib/rust/web/secp256k1.dart`. Both `alg=0` (Ed25519) and `alg=1` (secp256k1) are fully real on Web — native-byte-identical (golden vectors). See `docs/BROWSER_SUPPORT.md`. |

## ICPay / paid-script entitlement (UX-5) — COMPLETE

Real ICP-token payments via [icpay.org](https://icpay.org), end-to-end:

- **Backend entitlement gate** (`backend/src/main.rs::get_script`): paid scripts
  return `bundle: null, purchased: false` unless the requester is the script
  owner or holds a `purchases` row; metadata (title/description/stats) stays
  public. Closes the HIGH security leak this work surfaced.
- **`purchases` table** (migration `006_*`): `UNIQUE(account_id, script_id)` →
  idempotent webhook redelivery. Repo: `purchase_repository.rs`.
- **Authenticated download** `POST /api/v1/scripts/:id/download` — Ed25519
  signature over `download:{id}:{ts}:{nonce}`; resolves account from the public
  key; free or purchased → 200 bundle; else `402 {data:{price}}`.
- **ICPay webhook** `POST /payments/icpay/webhook` — HMAC-SHA256(raw_body,
  secret) constant-time verify; inserts the purchase on `completed/succeeded/paid`.
- **Config** `GET /payments/icpay/config` → `{publishableKey, shortcode:"ic_icp",
  apiUrl}`; 503 LOUD when unset (marketplace still browses; startup warns).
- **Frontend**: `IcpayService` creates the intent (`tokenShortcode:"ic_icp"`,
  `usdAmount: script.price`, `metadata:{account_id,script_id}`) with the
  browser-safe publishable key; Buy CTA in the script list + details dialog;
  `url_launcher` hosted checkout; `WidgetsBindingObserver` resume refetches
  entitlement. Registered in the get_it service locator.

> **⚠️ Verify-live (sandbox was network-blocked):** (1) the ICPay
> hosted-checkout URL / field name — `PaymentIntent.fromJson` reads
> `checkoutUrl`/`hosted_url`/`payment_url`/`url` defensively and falls back to
> `https://app.icpay.org` with a loud warning; (2) webhook signature scheme
> (hex vs base64, header name, raw-body vs `timestamp.body`) — isolated in
> `payment_service.rs::verify_webhook`, one-function swap; (3) end-to-end
> create-intent → pay → webhook → `purchased:true` → download. Backend
> entitlement/webhook proven by `cargo nextest` (148) + curl PoC; frontend glue
> unit-tested (mocked HTTP, real crypto).

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
  conditional-import scaffolding is in place. **R-2 (Ed25519 + ICP principal +
  sign), R-4 (vault crypto: Argon2id + AES-256-GCM), and R-5 (passkeys + CORS)**
  are **DONE** — pure-Dart crypto, bit-for-bit cross-compatible with the Rust
  FFI (verified against the `icp_core` reference vectors + native↔web round-trip).
  `flutter build web` succeeds. **R-3a DONE (execution + lint/validate)** —
  scripts run on Web via quickjs-emscripten (51 golden vectors at native parity).
  **R-3b DONE** — IC-canister HTTP agent (`fetchCandid`/`parseCandid`/
  `callAnonymous`/`callAuthenticated`) via `@dfinity/agent@3.4.3` + a backend
  byte-relay CORS proxy; live-verified against mainnet (ICP ledger `symbol()`.
  **Still staged:** secp256k1 (alg=1) only — Ed25519 is ICP-critical.
- **UX-5 purchase CTA / UX-6 / UX-8 — remaining Round-4/5 polish.** UX-4
  (collapse inline Add-Bookmark, `98f5a05c`), UX-5 lazy-load Details tabs
  (`448c8fab`), and UX-9 (surface-specific keyboard shortcuts, `97b42da3` +
  `f54bb58f`) are DONE in the Next-Iteration plan. **UX-5 (paid-script purchase
  CTA via ICPay) is ✅ DONE** — see **ICPay / paid-script entitlement** above
  (backend gate + purchases + webhook + Buy CTA; live ICPay checkout shape is a
  verify-live item). **UX-6 is ✅ DONE**: `GET /api/v1/scripts/:id/preview`
  returns a lightweight payload (no `bundle` field by construction); free scripts
  get a 50-line preview (~51% smaller than the full bundle), paid scripts get a
  20-line teaser and NEVER the full source; the Details dialog no longer
  full-downloads to render 50 lines, and never full-downloads a paid script.
  **UX-8** (largely resolved by the local-only account body — recommend CLOSE).
  See `docs/specs/NEXT_ITERATION_PLAN.md`.
- **TD-7 — SQL column list** (`backend/src/models.rs::SCRIPT_COLUMNS_WITH_ACCOUNT`). Already
  guarded by the drift-detection test at `models.rs:418-424`.

## Future / Optional

Not started; pulled from the migration spec's open questions (`docs/specs/SCRIPTING_RUNTIME_MIGRATION.md` §11):

- **G2** — Android NDK cross-compile of the QuickJS/rquickjs cdylib (NDK is not present in the current environment).
- **G8** — `qjsc` bytecode precompilation for faster cold start (optional).
- **G12** — Resource-limit (memory/time) tuning against a real pilot-script load test.

### Wave-6 follow-ups (surfaced 2026-07-11, not blockers)

- ✅ **Slow recovery test** — `#[ignore]`-by-default with run instructions (`cargo test -- --ignored`).
- ✅ **webauthn-rs in-blob counter-replay gap** — `passkey_service` now re-serialises the `Passkey` blob via `update_credential` after each auth; regression test `in_blob_counter_replay_rejects_non_monotonic_assertion`.
- ✅ **Async test consumers** — `script_repository_api_test.dart:299,348` now `await` `generateTestSignature`.
- ✅ **TQ-W6-2e:** dedicated repository unit tests — `backend/tests/repository_tests.rs` (50 tests: account 18, script 23, review 6).
- ⏸️ **Split candidates** (all under 2k threshold — deferred per KISS/YAGNI): `account_profile_screen.dart` (1977), `account_service.rs` (1990), `marketplace_open_api_service.dart` (~1442).
- ✅ **`web_probe_*_main.dart`** — relocated from `lib/` to `tool/` with `package:` imports.
- ✅ **Narrow mobile-width dialog** — header badges `Row`→`Wrap` in `script_details_dialog.dart`.
- ✅ **Frontend category list** — now consumes `/scripts/categories` via `fetchCategories()`.

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
