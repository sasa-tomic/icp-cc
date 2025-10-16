## Scripts tab and Lua scripting (planned activities)

- Navigation: add `Scripts` tab to Flutter app (bottom nav + screen scaffold).
- Data model: define `ScriptRecord` (id, title, emoji or imageUrl, script body, createdAt, updatedAt).
- Persistence: implement `ScriptRepository` for local JSON storage with fail-fast IO.
- Scripts UI: list scripts, creation/edit sheet (title + emoji/image picker), delete/rename.
- Script runner: wire Lua engine via `RustBridgeLoader.luaExec`, JSON in/out contract.
- Canister reads: UI to compose canister method calls whose outputs feed the Lua script.
- Output actions: show results in UI or trigger a follow-up canister call with transformed data.
- Security: sandbox Lua (whitelist helpers only), permission prompts for canister access.
- Tests: unit tests for model/repo, Lua execution plumbing, and navigation/UI flows.
- E2E: integration tests covering read→transform→display and read→transform→call.


## Follow-ups: Lua-driven UI (next iterations)

- Add richer UI elements: text fields, toggles, select menus, tables with columns, images.
- Support paginated lists and loading states driven by Lua.
- Add menu to pick common UI elements/actions in the script editor: button, canister method call, message, list.
- Provide input bindings so button actions can incorporate user-entered values.
- Validation and error surfaces for action results in the UI container.
- Theming and layout presets for script UIs.

