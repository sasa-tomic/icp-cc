# ICP Canister Client - Work Spec (2025-10-12)

Objective: Add a Rust-first canister client to `crates/icp_core` that can:
- Fetch embedded Candid for a canister id (metadata key `candid:service`) from the IC replica.
- Introspect methods (name, kind, args/returns) from the Candid and present them to the UI.
- Send anonymous or authenticated requests to a selected endpoint and return results.
- Save favorite `(canister_id, method)` pairs for quick access.

Constraints:
- Minimal surface area (YAGNI) and reuse existing crate (`icp_core`).
- DRY + test-driven; unit tests must pass and no warnings.

Planned modules and APIs:
1) `canister_client` (new)
   - Types:
     - `MethodKind` = `Query | Update | CompositeQuery`
     - `MethodInfo { name, kind, args: Vec<String>, rets: Vec<String> }`
     - `ParsedInterface { methods: Vec<MethodInfo> }`
   - Parsing:
     - `parse_candid_interface(candid: &str) -> Result<ParsedInterface, Error>`
       - Implemented with a minimal regex-based extractor. Good enough for listing methods and optional signatures.
  - `fetch_candid(canister_id: &str, host: &str) -> Result<String, Error>` — Implemented via HTTPS GET to replica.
  - `call_anonymous(canister_id, method, kind, arg_candid, host) -> Result<String, Error>` — Implemented using `ic-agent`.
  - `call_authenticated(canister_id, method, kind, arg_candid, ed25519_private_key_b64, host) -> Result<String, Error>` — Implemented using `ic-agent` with identity.
  - Args supported now: `"()"` or `"base64:<encoded_candid_bytes>"`. Returns decoded candid as string.

2) `favorites` (new)
   - File: `$XDG_CONFIG_HOME/icp-cc/favorites.json` (fallback `~/.config/icp-cc/favorites.json`).
   - Types:
     - `FavoriteEntry { canister_id: String, method: String, label: Option<String> }`
   - APIs:
     - Implemented: `load`, `save`, `add`, `remove`, `list`.

Tests:
- Unit tests (always on):
  - Candid parsing for method enumeration.
  - Favorites add/list/remove using a temporary directory.
- Integration tests (opt-in): deferred for now.

FFI:
- Done: thin FFI exports `fetch_candid`, `parse_candid_interface`, `call_anonymous`/`call_authenticated`, and favorites `add`/`list`/`remove` from `crates/icp_core/src/ffi.rs`. A Dart bridge in `apps/autorun_flutter/lib/rust/native_bridge.dart` wires these into the Flutter app layer.

UI guidance:
- It's sufficient to show a list of functions; optionally show signature text (args/results) if trivial. No renderer required.
- For calling, allow selecting anonymous/authenticated and inputting args as "()" or base64.
Out of scope for now:
- Full Candid UI renderer. We will list functions and optionally show signatures as text; no rendering engine.
- Custom subnets UI; accept explicit `host` param.

Done (current status):
- Canister client implemented: `fetch_candid`, Candid parsing, and `call_anonymous`/`call_authenticated` using `ic-agent`.
- Favorites persistence implemented and tested.
- FFI exports added and wired via Dart bridge.
- Core compiles cleanly; unit tests pass; clippy/fmt clean.

Remaining:
- Integrate the canister client UX in the Flutter app (list methods, call flow).
- Keep integration tests optional; add when an environment is available.
