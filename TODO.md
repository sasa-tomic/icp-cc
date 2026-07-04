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

| Issue | Location | Severity | Notes |
|-------|----------|----------|-------|
| Key label editing is blocked by a missing backend endpoint | `AccountController` | MEDIUM | No rename/label route exists server-side. |
| Web *runtime* features are stubbed (build compiles) | `lib/rust/native_bridge_web.dart` | MEDIUM | R-1 unblocked `flutter build web` (conditional FFI split). Native-only calls throw honest `UnsupportedError`; full Web runtime is R-2..5 (see Future). |
| A-4 — Vault is NOT actually zero-knowledge (intent ↔ code) | `backend/src/vault.rs`, `lib/screens/vault_unlock_screen.dart` | HIGH (security promise) | The Dart client sends the vault password in plaintext to `/api/v1/vault`; the **backend** does Argon2id + AES-GCM (`vault.rs::encrypt_vault`). There is **no** client-side crypto in Dart. A compromised server (or a DB dump + captured password) can decrypt every vault. `HUMAN_EXPECTATIONS.md` states zero-knowledge as the intent. **Decision needed:** (a) accept the current server-side model and downgrade the doc promise, or (b) migrate to true client-side crypto (Argon2id + AES-GCM in Dart; `/vault` becomes a pure opaque-blob store). Decision + grounding: `docs/specs/NEXT_ITERATION_PLAN.md` §1. |

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
- **UX-4/5/6/8 — lower-priority UX polish** from `docs/specs/UX_REVIEW_ROUND4.md` (collapse
  inline Add-Bookmark, lazy per-tab load + paid purchase CTA, lightweight preview endpoint,
  unify Import/Export). The P0/P1 items (UX-2 header↔tab, UX-3 searchable method picker,
  UX-7 local keys visible, UX-9 keyboard shortcuts) are done.
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
