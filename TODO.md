# ICP Script Marketplace - TODO

## Passkey Authentication (HIGH)

See [PASSKEY_IMPLEMENTATION_PLAN.md](PASSKEY_IMPLEMENTATION_PLAN.md) for architecture and details.

- [ ] Backend: WebAuthn endpoints (register/authenticate start/finish)
- [ ] Backend: Vault encryption utilities (Argon2id + AES-GCM)
- [ ] Backend: Recovery code system (generate, hash, verify)
- [ ] Backend: Database schema (passkeys, recovery_codes, user_vaults tables)
- [ ] Frontend: PasskeyService using `passkeys` package
- [ ] Frontend: Vault password UI (setup, unlock, recovery)
- [ ] Frontend: Passkey management UI (list, add, delete)

## Script Management (HIGH)

- [ ] Add secp256k1 script signing via Rust FFI (account signing done, script signing has `UnimplementedError` in `script_signature_service.dart:163`)
- [ ] Implement SHA256 checksums for script integrity verification
- [ ] Add support for installing a specific version of a script locally
- [ ] Implement version management and update notifications

## Lua Scripting UI (HIGH)

- [ ] Add tables with columns to UI elements
- [ ] Support paginated lists and loading states driven by Lua
- [ ] Add menu to pick common UI elements in script editor: button, canister method call, message, list
- [ ] Provide input bindings so button actions can incorporate user-entered values

## Testing (HIGH)

- [ ] Lua App integration tests: host loop, event dispatch, effect handling, renderer
- [ ] Integration tests for complete Lua app lifecycle
- [ ] Widget tests for ScriptAppHost state management

## UX Improvements (MEDIUM)

- [ ] Create hybrid view combining local and marketplace scripts
- [ ] Add source badges (Local/Marketplace) to distinguish script origins
- [ ] Add complexity indicators (beginner/intermediate/advanced)
- [ ] Display usage statistics (run count, last used)

## Marketplace (MEDIUM)

- [ ] Implement API key authentication for admin endpoints
- [ ] Add basic content moderation system

## Account/Profile (MEDIUM)

- [ ] Add `label` field to `account_public_keys` table and API (e.g., "Mobile", "Desktop", "Hardware Wallet")
- [ ] Multi-device sync: QR code import, encrypted export, or mnemonic entry to add keys from new devices
- [ ] Key import/export: Encrypted backup file for disaster recovery (password-derived key, mnemonic + private key)
- [ ] Hardware key support: WebAuthn integration for YubiKey etc.

## Canister Interaction (LOW)

- [ ] Canister autocomplete/search by ID or name
- [ ] Smart input forms based on Candid interface (.did file parsing)
- [ ] Response viewer with multiple formats (JSON, Table, Raw)
- [ ] Interaction history with replay capability
- [ ] Favorite canisters list

## Script Automation (LOW)

- [ ] Script scheduler UI (cron-like but user-friendly)
- [ ] Trigger system (time-based initially, event-based later)
- [ ] Automation logs with filtering and search
- [ ] Enable/disable toggle for automations
- [ ] Failure notifications

## Discovery (LOW)

- [ ] Trending algorithm based on recent downloads + ratings
- [ ] Personalized recommendations based on user's downloads
- [ ] Trust system: verified author badges, reputation score

---

## Architecture Reference

### Design Principles
- **Untrusted code isolation**: Lua is sandboxed; no IO; effects executed by host
- **Fail fast**: strict schema validation, clear error messages, hard time/step limits
- **Testability**: pure functions (init/view/update) are directly testable

### Lua App Contracts (JSON via FFI)
- `init(arg) -> state, effects[]`
- `view(state) -> ui_v1`
- `update(msg, state) -> state, effects[]`
- Messages: `{ type: string, id?: string, payload?: any }`
- Effects (executed by host): `icp_call`, `icp_batch`
- Host emits results as msgs: `{ type:"effect/result", id, ok, data?|error? }`

---

## Update Guidelines

- Remove completed tasks immediately
- Break complex tasks into subtasks
- Empty sections: use `(none)`
- Priority: HIGH = MVP/critical, MEDIUM = significant UX improvement, LOW = nice-to-have
