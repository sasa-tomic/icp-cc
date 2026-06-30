# ICP Script Marketplace — TODO

A focused, current backlog. Historical work lives in git history and the migration
ADR (`docs/specs/SCRIPTING_RUNTIME_MIGRATION.md`); the Lua-sunset execution record is
in `docs/specs/CLEANUP_PLAN.md`. Architecture reference at the bottom.

## Active Work

**Scripting runtime is TypeScript/QuickJS-only** as of 2026-06-30. The Lua sunset is
complete (`docs/specs/CLEANUP_PLAN.md` WU-1..WU-10 done; `SCRIPTING_RUNTIME_MIGRATION.md`
Phase 4 done). There is no active scripting work.

Genuinely open items are listed below.

## Known Issues

| Issue | Location | Severity | Notes |
|-------|----------|----------|-------|
| Cross-profile key sharing is allowed by the Flutter models (violates the profile-centric design; the backend enforces key uniqueness) | `lib/models/account.dart` (`FIXME` at L18, L304) | MEDIUM | Architectural — needs a human decision. See `docs/ACCOUNT_PROFILES_DESIGN.md`. |
| Key label editing is blocked by a missing backend endpoint | `AccountController` | MEDIUM | No rename/label route exists server-side. |

## Future / Optional

Not started; pulled from the migration spec's open questions (`docs/specs/SCRIPTING_RUNTIME_MIGRATION.md` §11):

- **G2** — Android NDK cross-compile of the QuickJS/rquickjs cdylib (NDK is not present in the current environment).
- **G8** — `qjsc` bytecode precompilation for faster cold start (optional).
- **G12** — Resource-limit (memory/time) tuning against a real pilot-script load test.
- **TD-7** — `backend/src/models.rs::SCRIPT_COLUMNS_WITH_ACCOUNT` is a hand-maintained SQL column list; derive it from struct metadata on the next schema change.

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
