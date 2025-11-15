## Fixes and urgent improvements

## ICP Autorun Marketplace - Future Enhancements

### Authentication System
- Add authentication (Google OAuth or similar) required for script uploads
- Implement user profiles and author attribution
- Add user registration and login flows
- Secure API endpoints with authentication middleware

### Input Validation & Sanitization
- Implement comprehensive input validation for API endpoints
- Add Lua code syntax validation and security scanning
- Sanitize user-generated content to prevent XSS attacks
- Add content filtering and moderation system

### Database Schema Improvements
- Add missing fields to Scripts collection:
  - `createdAt`: timestamp for script creation
  - `updatedAt`: timestamp for last modification
  - `version`: script versioning support
  - `isDeleted`: soft delete support
- Add Users collection for authenticated users
- Add Reviews collection for future review functionality

### Payment Processing
- Integrate with icpay.org for script payments
- Implement purchase tracking and licensing
- Add support for paid script tiers
- Create payment history and receipts

### Enhanced Security Features
- Implement script sandboxing and security scanning
- Add code review and approval workflow
- Create security audit logs
- Implement rate limiting and abuse protection

## Scripts tab and Lua scripting

Design pillars:
- Untrusted code isolation: Lua is sandboxed; no IO; effects executed by host
- Fail fast: strict schema validation, clear error messages, hard time/step limits
- Testability: pure functions (init/view/update) are directly testable

- Security: sandbox Lua (whitelist helpers only).
- E2E: integration tests covering read→transform→display and read→transform→call.
- Add richer UI elements: tables with columns.
- Support paginated lists and loading states driven by Lua.
- Add menu to pick common UI elements/actions in the script editor: button, canister method call, message, list.
- Provide input bindings so button actions can incorporate user-entered values.
- Validation and error surfaces for action results in the UI container.
- Theming and layout presets for script UIs.

Contracts (JSON via FFI):
- `init(arg) -> state, effects[]`
- `view(state) -> ui_v1`
- `update(msg, state) -> state, effects[]`
- Msgs: `{ type: string, id?: string, payload?: any }`
- Effects (executed by host): `icp_call`, `icp_batch` (more later)
- Host emits results as msgs: `{ type:"effect/result", id, ok, data?|error? }`

Implementation plan:
1) Rust core
   - Add Lua app runtime that loads script once, locates `init/view/update`, and calls them with JSON bridges
   - Add per-call time/step limits and input/output validation
   - Serialize/deserialize `state`, `msg`, `ui`, `effects` using serde/json
   - New FFI: `icp_lua_app_init(json_arg) -> { ok, state, effects, error? }`, `icp_lua_app_view(state) -> { ok, ui, error? }`, `icp_lua_app_update(msg, state) -> { ok, state, effects, error? }`

2) Dart bridge
   - Extend `RustBridgeLoader` and `ScriptBridge` to expose `luaAppInit/View/Update`

3) Flutter host + renderer
   - New `ScriptAppHost` widget manages state, runs init/view/update, renders UI, dispatches msgs
   - Implement UI v1 renderer (column, row, text, button, list)
   - Implement effects executor for `icp_call`/`icp_batch`; dispatch result msgs to update
   - Validate schemas and fail fast with surfaced errors

4) Integration
   - Update `ScriptsScreen` to launch `ScriptAppHost` instead of one-shot dialog
   - Provide migration shim for old `return icp_ui_list(...)` (optional)

5) Testing
   - Rust: unit tests for init/view/update JSON roundtrips and timeouts (DONE)
   - Flutter: widget tests for host loop, event dispatch, effect result handling, and renderer

