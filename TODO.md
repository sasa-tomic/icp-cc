## Fixes and urgent improvements

(none)

## Update this document (tasks from this section should always stay here)

- If some task needs to be broken down into smaller actions, add them all as nested subtasks into this TODO.md document
- Whenever some task is completed or found to be already done, REMOVE it from this TODO.md document
- If a whole section is empty, leave a placeholder: `(none)`
- Check if this document is well organized and structured and if not, reorganize and restructure to IMPROVE it.
- clarify in this document if some task is particularly complex or difficult to do and try to break it down to smaller tasks
- Remember: tasks from this section should always stay untouched. All other sections in this document MUST be kept up to date.

## ICP Autorun Marketplace

- add support from the app to upload scripts to the marketplace
- add support for searching for scripts in the marketplace: both without and with a search substring. The database side should do a FTS for the name of the script and the canister ids, for now

### Payment Processing (next)
- Integrate with icpay.org for script payments
- Implement purchase tracking and licensing
- Add support for paid script tiers
- Create payment history and receipts

### Authentication System (tbd later)
- Add authentication (Google OAuth or similar) required for script uploads
- Implement user profiles and author attribution
- Add user registration and login flows
- Secure API endpoints with authentication middleware

### Security (tbd later)
- Implement comprehensive input validation for API endpoints
- Add Lua code syntax validation and security scanning
- Sanitize user-generated content to prevent XSS attacks
- Add content filtering and moderation system

## Scripts tab and Lua scripting

Design pillars:
- Untrusted code isolation: Lua is sandboxed; no IO; effects executed by host
- Fail fast: strict schema validation, clear error messages, hard time/step limits
- Testability: pure functions (init/view/update) are directly testable

- E2E: integration tests covering read→transform→display and read→transform→call.
- Create security audit logs
- Add richer UI elements: tables with columns.
- Support paginated lists and loading states driven by Lua.
- Add menu to pick common UI elements/actions in the script editor: button, canister method call, message, list.
- Provide input bindings so button actions can incorporate user-entered values.
- Validation and error surfaces for action results in the UI container.
- Theming and layout presets for script UIs.
- (later) Implement script sandboxing and security scanning
- (later) Security: sandbox Lua (whitelist helpers only).

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

