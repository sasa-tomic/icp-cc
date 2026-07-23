# ICP Script Marketplace — TODO

A focused, current backlog. Historical work lives in git history and
`docs/OPEN_ISSUES.md`.

## Active Work

**No active work.** The app is in clean shape:
- `flutter analyze`: 0 issues
- `flutter test`: 2266 pass / 16 skip / 0 fail
- `OPEN_ISSUES.md`: every item RESOLVED
- E2E: 48/98 flows in ~3m via fast widget-test harness; remaining 50 via integration suites (~9m)

## Open Items

### Canister Frontend Vision (Phases 2-4)

Phase 1 (Candid-driven scaffold) shipped (commit `7ece3efb`). Remaining phases from
`docs/specs/2026-07-23-canister-frontend-vision.md`:

- **Phase 2** — Plug/Super Injector bridge (`window.ic.plug` impersonation). M effort.
- **Phase 3** — Marketplace-hosted frontend bundles (discovery + trust UX). M effort.
- **Phase 4** — IC-canister HTTP agent on Web (replace backend CORS proxy with
  `@dfinity/agent`). L effort.

### UX Click-Reduction (deferred CR items)

From `docs/specs/2026-07-22-ux-click-reduction-audit.md`:

- **CR-9** — Chip-based tag editor in QuickUpload (M effort)
- **CR-13** — Passkeys menu tile on profile menu (P3)
- **CR-14** — Cycle profile keyboard shortcut (P3)

### E2E Harness Expansion

- **Fast harness**: port remaining ~50 flows (vault, passkey, shortcuts, deeplink,
  dapp trust) from integration suites to `test/e2e_fast/`. Diminishing returns —
  many need platform-specific channels.
- **Web e2e**: ~47 more web-eligible flows to port to `test/e2e_web/`.

### ICPay — Verify-Live

The ICPay integration is code-complete but the sandbox was network-blocked during
development. Three items need verification against a live ICPay sandbox:
1. Hosted-checkout URL / field name (`PaymentIntent.fromJson` reads multiple keys
   defensively; verify the canonical name)
2. Webhook signature scheme (hex vs base64, header name, raw-body vs
   `timestamp.body`)
3. End-to-end create-intent → pay → webhook → `purchased:true` → download

## Deferred (decided, with justification)

- **A-3b** — structural `profileId` on `ProfileKeypair`. Data-integrity contract
  already enforced by `assertUniqueKeypairOwnership` invariant. KISS/YAGNI (wide
  blast radius: models/serializer/generator/controllers/many tests).
- **CR-3** — collapse wizard success screen. Skipped (high test churn: 6 test
  files + 2 e2e flows reference 'Start Exploring'; marginal benefit).
- **CR-12** — vault credential UI. Deferred (architectural, needs human decision).
- **TD-5** — `account_service.rs` split (1990 LOC). Under 2k threshold — deferred
  per KISS/YAGNI. Already guarded by drift-detection test.
- **Split candidates** — `account_profile_screen.dart` (1977),
  `marketplace_open_api_service.dart` (~1442). All under 2k threshold.

## Future / Optional

- **G8** — `qjsc` bytecode precompilation for faster QuickJS cold start.
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
