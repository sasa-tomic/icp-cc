# A-4 — Vault Zero-Knowledge Migration Plan (client-side crypto)

- **Status:** ✅ **COMPLETE (2026-07-04).** The vault is **genuinely
  zero-knowledge.** Argon2id + AES-256-GCM run **client-side** via the Rust FFI
  bridge; the vault password never leaves the device; the backend is a pure
  opaque-blob store that cannot decrypt. Proven end-to-end by the W5
  integration round-trip test (server-blindness asserted on blob bytes;
  wrong-password + tamper both fail loud). All WUs W0–W6 landed; per-WU commit
  hashes in §5 below; headline outcome in §11.
- **Original decision:** human decision recorded as **execute option (b)** —
  move Argon2id + AES-256-GCM into the Dart client; make `/api/v1/vault` a pure
  opaque-blob store; delete server-side vault crypto. Authorised by the human
  per `TODO.md` A-4 row + `HUMAN_EXPECTATIONS.md` §1 A-4 flag (both now
  resolved).
- **Date:** 2026-07-04.
- **Scope:** desktop (Linux/macOS/Windows) + Android. Web is **out of scope**
  (FFI bridge is stubbed on Web per R-1; vault on Web throws honest
  `UnsupportedError` — see Risks).
- **Method:** every claim below was re-verified by reading the cited files in
  the repo at the time of planning (`rg`/`read`).

---

## 0. Headline discovery (this reshapes the plan)

**The FFI crypto bridge is already fully built end-to-end but is called by NO
production code.** Concretely:

| Layer | File:lines | Status |
|---|---|---|
| Rust crypto core (`encrypt_vault` + `decrypt_vault`, Argon2id + AES-256-GCM, real round-trip tests) | `crates/icp_core/src/vault.rs:101-131` (fns), `:133-225` (tests) | ✅ EXISTS |
| Rust FFI surface (`icp_encrypt_vault`, `icp_decrypt_vault`, JSON in/out, NOT gated by `wasm32`) | `crates/icp_core/src/ffi.rs:408-516` | ✅ EXISTS |
| Rust lib re-exports | `crates/icp_core/src/lib.rs:28-30` | ✅ EXISTS |
| Dart FFI bindings (`encryptVault` + `decryptVault`, real `dart:ffi`) | `apps/autorun_flutter/lib/rust/native_bridge_io.dart:418-482`, `_Symbols` at `:32-33`, typedefs at `:619-637` | ✅ EXISTS |
| Dart shared types (`EncryptedVaultResult`, `VaultEncryptionException`, `VaultDecryptionException`) | `apps/autorun_flutter/lib/rust/native_bridge.dart:25-51` | ✅ EXISTS |
| Dart Web stubs (honest `UnsupportedError`) | `apps/autorun_flutter/lib/rust/native_bridge_web.dart:90-102` | ✅ EXISTS |
| **Callers of the above in production Dart code** | — | ❌ **ZERO** (`rg encryptVault\|decryptVault` finds only definitions) |

The Dart client instead sends the **plaintext password + base64 plaintext
payload** to `/api/v1/vault`, and the **backend** encrypts
(`backend/src/services/passkey_service.rs:501,543` → `backend/src/vault.rs:83
encrypt_vault`). This is the A-4 divergence.

**Implication:** the two largest work units of a naive plan (W1 "add Rust FFI
crypto", W2 "add Dart bindings") are **already done and already tested with real
crypto**. The remaining work is: wire the Dart service layer to use the existing
FFI, strip crypto from the backend, fix one schema bug, and update tests + docs.

**Crate-version parity (no drift risk):** the crypto crates are pinned to the
SAME versions in both the core crate and the backend, so client and server
historically derived identical keys:
- `crates/icp_core/Cargo.toml:41-43` — `argon2 = "0.5"`, `aes-gcm = "0.10"`, `rand = "0.8"`
- `backend/Cargo.toml:46-48` — `argon2 = "0.5"`, `aes-gcm = "0.10"`, `rand = "0.8"`

After this migration the backend does **no** vault crypto, so
`crates/icp_core/src/vault.rs` becomes the **single source of truth** for vault
crypto params (satisfies HE §2 *"a single constant lives in ONE place"*). The
backend's remaining Argon2id usage is recovery-code hashing only
(`backend/src/vault.rs::derive_key` for `hash_recovery_code`) — a separate
purpose, independently versioned, left as-is.

---

## 1. Current data flow (the thing we are replacing)

```
Dart VaultPasswordSetupScreen._createVault()          vault_password_setup_screen.dart:80-93
  └─ PasskeyService.createVault(account_id, password, data='{}')   passkey_service.dart:114-124
       └─ POST /api/v1/vault  body={account_id, password, data=base64('{}')}   ← PASSWORD + PLAINTEXT LEAVE THE DEVICE
            └─ main.rs::vault_create (849-872)  → base64-decodes `data`
                └─ PasskeyService::create_vault(account_id, password, data)    passkey_service.rs:484-518
                    └─ vault::encrypt_vault(password, data)                    vault.rs:83-101  ← SERVER DOES THE CRYPTO
                        └─ Argon2id(time=3,mem=64MiB,par=4,32B) + AES-256-GCM(96-bit nonce)
                    └─ repo.create_vault(id, account_id, enc, salt, nonce, now) passkey_repository.rs:247-270

Dart VaultUnlockScreen._unlockVault()                 vault_unlock_screen.dart:47-89
  ├─ PasskeyService.getVault(account_id)              passkey_service.dart:126-136  → GET /vault (no password sent)
  └─ PasskeyService.updateVault(account_id, password, data=vaultData.encryptedData)  ← NONSENSICAL NO-OP RE-ENCRYPT
       └─ the screen never decrypts anything; it "unlocks" by re-posting ciphertext. Comment at :61-64 admits this.
```

**Storage:** SQLite table `user_vaults`
(`backend/src/db.rs:359-383`):
```sql
CREATE TABLE IF NOT EXISTS user_vaults (
    id TEXT PRIMARY KEY,
    user_principal TEXT NOT NULL UNIQUE,     -- ⚠️ see §4 schema bug
    encrypted_data BLOB NOT NULL,
    salt BLOB NOT NULL,
    nonce BLOB NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_principal) REFERENCES keypair_profiles(principal) ON DELETE CASCADE
);
```
The columns `encrypted_data / salt / nonce` are **already exactly what a
zero-knowledge opaque-blob store needs** — the schema shape does not change;
only who fills those columns changes (client instead of server), plus the
`user_principal`/`account_id` rename (§4).

---

## 2. Goal + acceptance criteria (measurable)

After this migration ALL of the following hold:

1. **Client-side crypto:** the Dart client encrypts/decrypts vault payloads
   locally via `RustBridgeLoader.encryptVault` / `decryptVault`
   (`native_bridge_io.dart:418-482`). A new failing-then-passing Dart test
   proves a round-trip (encrypt → decrypt → original plaintext) using **real**
   FFI + **real** Argon2id/AES-GCM (no mocks).
2. **Password never leaves the device:** `rg "password"` over the JSON bodies
   built in `passkey_service.dart`'s `createVault`/`updateVault` returns nothing
   in the HTTP request payload; the password is consumed only by the local FFI
   call.
3. **`/api/v1/vault` is opaque-blob CRUD:** POST/PUT accept only
   `{account_id, encrypted_data, salt, nonce}` (base64); GET returns the same.
   The handler bodies contain **no** `argon2`/`aes_gcm`/`encrypt_vault` symbol.
4. **Backend has no vault crypto + no password handling:**
   `backend/src/vault.rs::encrypt_vault`, `derive_key`, `generate_salt`,
   `generate_nonce`, `EncryptedVault` are DELETED (recovery-code fns stay).
   `backend/src/services/passkey_service.rs::create_vault`/`update_vault` no
   longer take a `password` parameter; the `VaultCreateRequest`/`VaultUpdateRequest`
   structs in `main.rs:841-846,895-900` drop the `password` field.
5. **HE §1 A-4 flag removed** (`docs/HUMAN_EXPECTATIONS.md:19-23`) — the ZK
   claim becomes true. `TODO.md` A-4 row moved out of **Known Issues** and
   **Next Iteration Candidates**; `NEXT_ITERATION_PLAN.md` §1 marked DONE.
6. **All tests green:** `just rust-tests`, `just flutter-tests`,
   `just test-feature passkey` (new path; see W5), and `just test` all pass.
7. **End-to-end round-trip test** (integration): client-encrypt → POST blob →
   server-store → GET blob → client-decrypt == original plaintext. This is the
   proof the migration is complete and the server genuinely cannot decrypt.

---

## 3. Design decision: HOW to do crypto on the client

**RECOMMEND: Option A — use the existing FFI bridge.** (Option B — a pure-Dart
crypto package — is rejected.)

| Criterion | Option A (FFI) | Option B (pure-Dart pkg) |
|---|---|---|
| KISS | ✅ crypto already written, tested, shipped in `libicp_core` | ❌ adds `cryptography`/`pointycastle` + an Argon2id impl |
| DRY | ✅ single Rust crypto impl, single source of params | ❌ second impl that must match backend params → drift risk |
| Consistency with project | ✅ every other native op (keys, signing, canister calls, JS) goes through this exact FFI bridge | ❌ breaks the pattern |
| Web | ⚠️ FFI stubbed (`UnsupportedError`) — vault on Web deferred under R-1..R-5 | ✅ would work on Web (but Web vault is out of scope anyway) |
| New deps | ✅ zero | ❌ one+ new pub package |
| Audit surface | ✅ audited `argon2`/`aes-gcm` crates already in use | ❌ new transitive dep tree |

**Justification:** Option A reuses the already-audited, already-FNI-exposed,
already-Dart-bound, already-tested Rust crypto. Zero new code on the Rust side,
zero new Dart dependency, and it is consistent with the project's FFI-first
architecture (every other native capability flows through
`native_bridge_io.dart`). The only downside (Web) is irrelevant because the Web
runtime is already stubbed across the board (R-1..R-5 deferral) and vault is a
desktop/mobile feature.

**Single-source-of-truth for params:** after W4 deletes server-side vault
crypto, `crates/icp_core/src/vault.rs:18-24` becomes the ONE place the
Bitwarden-level params live for vault crypto. No symbolic duplication remains.

---

## 4. Pre-existing bug surfaced (fix inside W4 — greenfield, no compat)

The `user_vaults` table is **currently broken at runtime**:

- DDL creates column `user_principal` (`backend/src/db.rs:364`).
- ALL queries reference `account_id` (`backend/src/repositories/passkey_repository.rs:257,273,288`), and the `VaultRow` struct (`:34-43`) has field `account_id`.

SQLite would throw `no such column: account_id` on every vault INSERT/SELECT/UPDATE. The same `user_principal`/`account_id` mismatch exists on `recovery_codes` (DDL `db.rs:339` vs queries `passkey_repository.rs:236`). The stale `#![allow(dead_code)]` + "scaffolded but not yet wired" comments (`passkey_service.rs:1-3`, `passkey_repository.rs:1-2`) confirm this path was never exercised end-to-end — consistent with A-4 being a "pending decision", not a regression.

**Fix (in W4):** standardise on `account_id` (matches all query code + row structs + the `passkeys` table which correctly uses `account_id` at `db.rs:308` — wait, verify; the `passkeys` table DDL must be checked, but the queries all use `account_id`). Mechanism respects AGENTS.md *"Never delete DB or tables"*: use `ALTER TABLE user_vaults RENAME COLUMN user_principal TO account_id;` (and likewise for `recovery_codes`) inside the existing migration block in `db.rs`, **or** — since the table is empty/scaffolded-and-broken — simply correct the DDL and document that any dev DB must be reset (`just api-dev-reset`). The implementer picks the mechanism; the outcome is `account_id` everywhere. (Note: also reconcile the FK target — `account_id` should reference `accounts(id)` or `keypair_profiles(principal)` consistently; verify against the `accounts`/`keypair_profiles` schemas when implementing.)

---

## 5. Work breakdown (independently-committable units, ordered)

> Conventions (same as `NEXT_ITERATION_PLAN.md` §2): PoC-first per AGENTS.md;
> one commit per WU; every commit leaves `flutter analyze` clean and the cited
> tests green; real crypto in tests (no mocks); all I/O timed; fail-fast
> (match-style, no `try{}catch(_){}`).

### W0 — Verify the existing FFI crypto in isolation (PoC gate, ~30 min) ✅ COMPLETE (folded into W1's real-FFI round-trip test)

- **Why first:** the whole plan rests on `encryptVault`/`decryptVault` actually
  working through the Dart FFI today. Prove it before depending on it.
- **Action:** write a throwaway Dart test under `test/features/vault/` that
  calls `RustBridgeLoader().encryptVault(password, base64(plaintext))`, then
  `decryptVault(...)` on the result, and asserts the round-trip. Guard with the
  existing `nativeLibAvailable` skip pattern (see
  `test/native_bridge_js_smoke_test.dart:158`).
- **Files (new, test-only):** `apps/autorun_flutter/test/features/vault/ffi_crypto_smoke_test.dart`.
- **Acceptance:** test passes on Linux desktop against the real `libicp_core.so`.
- **Confidence gate:** if this fails, STOP — the rest of the plan is blocked on
  repairing the FFI crypto first.
- **Outcome:** the FFI crypto round-tripped cleanly; the gate was satisfied by
  the real-FFI unit test shipped with W1
  (`test/features/vault/vault_crypto_service_test.dart`).

### W1 — Dart vault-crypto service (thin FFI wrapper)  [Simple] ✅ DONE `714c8568`

- **Files:** NEW `apps/autorun_flutter/lib/services/vault_crypto_service.dart`.
- **Size:** ~60-90 LOC.
- **Responsibility:** the SINGLE Dart place that knows the FFI vault contract.
  Exposes:
  - `Future<EncryptedVaultResult> encrypt({required String password, required String plaintext})`
  - `Future<String> decrypt({required String password, required EncryptedVaultResult blob})`
- **Why a separate service (not folded into `PasskeyService`):** single
  responsibility + independently testable (real-FFI unit test, no HTTP). DRY —
  both screens + the integration test reuse it.
- **Critical correctness point — must run off the UI isolate:** `encryptVault`/
  `decryptVault` are **synchronous** FFI calls (`native_bridge_io.dart:418,451`)
  and Argon2id (64 MiB) blocks ~0.1-1 s. Calling them on the main isolate freezes
  the UI (the existing `_isUnlocking` spinner would not animate). **Validate in
  the PoC** that the call works via `compute()` (Dart isolate) — the args are
  plain `Map`s/`String`s (sendable). If `RustBridgeLoader`'s cached
  `DynamicLibrary` (`_cachedLib` at `:39`) is not isolate-shareable, load per
  isolate (it's cheap). If `compute()` proves unworkable, fall back to running
  synchronously behind the existing spinner and file a follow-up — but TRY
  `compute()` first (see Risks §7).
- **Error handling (fail-fast):** if `_open()` returns `null` (lib missing),
  throw a loud `VaultUnavailableException` with the platform + attempted paths —
  never return silent `null`.
- **Dependencies:** none (uses existing `RustBridgeLoader`).
- **Tests:** `test/features/vault/vault_crypto_service_test.dart` — real-FFI
  round-trip (encrypt → decrypt == original); wrong-password fails with
  `VaultDecryptionException`; tampered ciphertext fails. Guard with lib-available
  skip.
- **Acceptance:** `flutter test test/features/vault/` green; `flutter analyze` clean.

### W2 — Rewrite Dart `PasskeyService` vault methods (encrypt-before-send)  [Simple] ✅ DONE `b4d709ab`

- **Files:** `apps/autorun_flutter/lib/services/passkey_service.dart` (modify `:114-148`, `:292-307`).
- **Size:** ~-20 / +30 LOC (net small).
- **Change:**
  - `createVault({accountId, password, plaintext})` → encrypt locally via
    `VaultCryptoService.encrypt`, then POST only `{account_id, encrypted_data, salt, nonce}`
    (all base64). **Remove** the `password` field from the body. **Remove** the
    client-side `base64Encode(utf8.encode(data))` (the crypto service already
    base64-encodes inside FFI; salt/nonce come back base64).
  - `updateVault({accountId, password, plaintext})` → same: encrypt locally,
    PUT the blob, no password in body.
  - `getVault(accountId)` → unchanged shape (already returns `VaultData` with
    `encrypted_data/salt/nonce`). It now returns an **opaque blob** that the
    caller decrypts (no password is sent on GET — already true today).
  - Rename the `data` param → `plaintext` for clarity; the JSON wire field stays
    `encrypted_data`.
- **HTTP timeout:** already 30 s (`passkey_service.dart:14`) — fine for a blob
  PUT/GET (the heavy crypto is now client-side and NOT part of the HTTP call).
- **Dependencies:** W1 (`VaultCryptoService`).
- **Tests:** update/rewrite `test/features/passkey/screens_test.dart` HTTP-mock
  expectations to assert the request body has NO `password` key and HAS
  `encrypted_data/salt/nonce`. Use the existing `overrideHttpClient`
  (`passkey_service.dart:19-20`) + `http/testing.dart` pattern already in that
  test file.
- **Acceptance:** `rg "password" apps/autorun_flutter/lib/services/passkey_service.dart`
  over the request-body construction returns nothing; widget test asserts the
  body shape.

### W3 — Rewrite the two vault screens to use local crypto  [Simple] ✅ DONE `d96661af`

- **Files:**
  - `apps/autorun_flutter/lib/screens/vault_password_setup_screen.dart` (`:80-110` `_createVault`).
  - `apps/autorun_flutter/lib/screens/vault_unlock_screen.dart` (`:47-89` `_unlockVault`).
- **Size:** ~±30 LOC each.
- **Change (setup):** `_createVault` calls
  `VaultCryptoService().encrypt(password, plaintext='{}')` then
  `PasskeyService().createVault(accountId, blob)`. Show the spinner during the
  (off-isolate) crypto. Remove the stale comment if any.
- **Change (unlock):** `_unlockVault` currently does a nonsensical
  getVault→updateVault round-trip (`:56-69`). Rewrite to: `getVault` →
  `VaultCryptoService().decrypt(password, blob)`; if it throws
  `VaultDecryptionException` → wrong password (increment `_failedAttempts`,
  show error); on success → `onUnlocked`. **Delete** the `TODO(A-4)` comment at
  `:61-64` (it is resolved by this WU).
- **Dependencies:** W1 + W2.
- **Tests:** extend `test/features/passkey/screens_test.dart` — happy path
  (valid password decrypts → `onUnlocked` fires) + negative path (wrong
  password → error card, `_failedAttempts` increments). The screens test will
  need a way to stub `VaultCryptoService`; preferred: inject a fake via a
  constructor param (production default = real service; tests pass a fake that
  uses the REAL FFI so crypto is real per AGENTS.md — or, if FFI is unavailable
  in the test env, a deterministic fake is acceptable for widget tests since
  the crypto itself is unit-tested separately in W1).
- **Acceptance:** both screens round-trip via local crypto; `flutter analyze` clean.

### W4 — Backend: strip vault crypto; opaque-blob CRUD; fix schema  [Medium] ✅ DONE `b92a54d4` (schema) + `30d98a3e` (opaque-blob endpoints)

- **Files:**
  - `backend/src/main.rs` (`:841-929` — `VaultCreateRequest`/`VaultUpdateRequest`/`vault_create`/`vault_get`/`vault_update`).
  - `backend/src/services/passkey_service.rs` (`:6-9` imports; `:484-563` `create_vault`/`get_vault`/`update_vault`).
  - `backend/src/vault.rs` (DELETE `derive_key:49`, `generate_salt:69`, `generate_nonce:76`, `encrypt_vault:83`, `EncryptedVault:41-46`; KEEP `generate_recovery_codes`, `hash_recovery_code`, `verify_recovery_code` + their Argon2id `derive_key` for recovery-code hashing — see note below).
  - `backend/src/db.rs` (`:359-383` fix `user_principal`→`account_id`; same for `recovery_codes :334-357`).
  - `backend/src/repositories/passkey_repository.rs` (queries already use `account_id` — no change once DDL is fixed; confirm `VaultRow :34-43`).
- **Size:** ~-100 / +40 LOC.
- **Change:**
  1. **Request/response shape** — `VaultCreateRequest`/`VaultUpdateRequest` lose
     `password`, gain `encrypted_data`, `salt`, `nonce` (all base64 `String`).
     The handler base64-decodes them into `Vec<u8>` and passes opaque bytes to
     the service. `vault_get` already returns the right shape — unchanged.
  2. **Service** — `create_vault(account_id, encrypted_data, salt, nonce)` and
     `update_vault(account_id, encrypted_data, salt, nonce)` — **no `password`
     param, no `encrypt_vault` call**. They just `repo.create_vault/update_vault`
     the bytes. `get_vault` unchanged (returns the stored bytes, base64'd).
  3. **Delete `encrypt_vault` + helpers** from `backend/src/vault.rs`. **Note:**
     `hash_recovery_code`/`verify_recovery_code` (`:127-151`) call `derive_key`,
     so either (a) keep a recovery-code-local `derive_key` (rename to
     `derive_recovery_key` for clarity), or (b) duplicate the tiny Argon2id
     block. Recommendation: keep a recovery-scoped `derive_recovery_key` so the
     recovery-code path is self-contained and honest about its purpose. The
     `argon2`/`aes-gcm` crate deps in `backend/Cargo.toml:46-47`: `aes-gcm` can
     be REMOVED (no longer used server-side); `argon2` stays (recovery-code
     hashing); `rand` stays (recovery-code salt). Remove `aes-gcm` from
     `Cargo.toml` — fail-fast if anything else still references it.
  4. **Schema** — fix `user_vaults` (`user_principal`→`account_id`, reconcile
     FK) and `recovery_codes` likewise. See §4.
- **DRY / single-source:** after this WU the backend has ZERO vault crypto; the
  vault crypto params live in ONE place (`crates/icp_core/src/vault.rs`).
- **Dependencies:** none (independent of W1-W3 on the Dart side). The wire
  contract change here is what W2 targets.
- **Tests:**
  - DELETE the `encrypt_vault`/`derive_key`/salt/nonce tests in
    `backend/src/vault.rs:153-247` (the fns are gone). KEEP the recovery-code
    tests (`:197-247`).
  - ADD a backend test (or `curl`-in-justfile integration) that POSTs an opaque
    blob, GETs it, and asserts byte-identity of `encrypted_data/salt/nonce`
    (server stored exactly what it was given — proving it cannot decrypt).
  - Assert `rg "encrypt_vault|aes_gcm|Aes256Gcm" backend/src` returns nothing.
- **Acceptance:** `cargo test -p icp-marketplace-api` green; the
  zero-knowledge property is testable: the backend binary contains no vault
  decryption code path.

### W5 — Integration test: client-encrypt → store → client-decrypt  [Medium] ✅ DONE `f1d425d5`

- **Files:** NEW `apps/autorun_flutter/test/features/vault/zk_round_trip_test.dart`;
  possibly extend `test/integration/` patterns.
- **Size:** ~80-120 LOC.
- **Change:** the proof-of-the-migration. Against the real dev API
  (`just api-dev-up`) and real FFI:
  1. `VaultCryptoService.encrypt(password, '{"k":"v"}')` → blob.
  2. `PasskeyService.createVault(account, blob)` (HTTP POST of opaque blob).
  3. `PasskeyService.getVault(account)` → returns the same blob.
  4. `VaultCryptoService.decrypt(password, blob)` → `'{"k":"v"}'`.
  5. Negative: `decrypt(wrongPassword, blob)` throws `VaultDecryptionException`.
- **Why this is the acceptance test:** it exercises the full ZK property — the
  server only ever saw opaque bytes; decryption succeeds client-side with the
  password that never left the device.
- **Dependencies:** W1 + W2 + W4 all landed; `just api-dev-up` available.
- **Also:** prune any test that relied on server-side crypto (none found beyond
  the `backend/src/vault.rs` unit tests already handled in W4; the existing
  widget tests in `screens_test.dart` are updated in W2/W3).
- **Acceptance:** `just test-feature vault` green (new feature dir); end-to-end
  ZK round-trip proven.

### W6 — Docs: remove A-4 flag; mark DONE  [Simple] ✅ DONE (this revision)

- **Files:**
  - `docs/HUMAN_EXPECTATIONS.md` (`:17-23` — the A-4 STATUS flag is replaced
    with an honest "IMPLEMENTED" note; the ZK bullet is now TRUE as-written).
  - `TODO.md` — the HIGH "human decision required" Known-Issues banner, the
    A-4 row, and the Next-Iteration candidate are all replaced with a single
    "✅ RESOLVED" pointer (option (b) executed; commit hashes cited).
  - `docs/specs/NEXT_ITERATION_PLAN.md` (§1, §3, §5, §6 — A-4 marked DONE with
    commit refs pointing here).
  - `backend/src/vault.rs` module doc-comment — already rewritten in W4
    (`30d98a3e`) to describe the recovery-code-only role accurately.
  - `apps/autorun_flutter/lib/screens/vault_unlock_screen.dart` /
    `vault_password_setup_screen.dart` — A-4 TODOs already deleted in W3
    (`d96661af`); the remaining `A-4 W2/W3` / `A-4 W3` code comments are
    ACCURATE implementation-history references (not stale).
- **Size:** docs-only.
- **Dependencies:** after W1-W5. MET.
- **Acceptance:** `rg "A-4|pending decision|server-side crypto" docs/ apps/ backend/`
  returns only HISTORICAL references inside this plan + the migration spec (no
  live "pending" claims). MET.

---

## 6. Migration / data note

- **Greenfield (per AGENTS.md §4):** no backward-compat shim. No migration of
  existing ciphertext.
- **Data loss reality:** given the §4 schema bug (`account_id` vs
  `user_principal`), the vault store has **never successfully round-tripped**
  against a real DB — there is no real user vault data to lose. Any dev DB rows
  that do exist (from a hand-crafted `user_principal` insert) would be
  undecryptable after the move (the server-derived key is gone). This is
  acceptable and expected for a greenfield ZK migration. Call it out in the W4
  commit message: *"breaking: vault store schema + crypto location change; any
  pre-existing dev vault rows are undecryptable (greenfield, no compat)."*
- **DB reset:** `just api-dev-reset` clears the dev DB; no production data exists.

---

## 7. Risks + mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| **Argon2id blocks the UI isolate** (sync FFI, 64 MiB) | HIGH | MED (jank during encrypt/decrypt) | W1 MUST validate `compute()` (Dart isolate). Args are sendable (`String`/`Map`). If `DynamicLibrary` cache isn't isolate-shareable, load per-isolate. Validate in the W0/W1 PoC before productionising. Fallback: run sync behind the existing spinner + file a follow-up — but TRY `compute()` first. |
| **Web target has no vault** (FFI stubbed) | CERTAIN | LOW (Web is R-1..R-5 deferred) | `native_bridge_web.dart:90-102` already throws honest `UnsupportedError('encryptVault: …')`. The setup/unlock screens should surface a clear "Vault not available on Web" message (the `PasskeyPlatform.isSupported` gate already covers passkeys; add an equivalent check before vault crypto). Document in `docs/BROWSER_SUPPORT.md`. |
| **Schema fix breaks dev DBs** (`user_principal`→`account_id`) | CERTAIN | LOW (dev only, greenfield) | `ALTER TABLE … RENAME COLUMN` in the migration block (respects "never delete tables"); OR fix DDL + `just api-dev-reset`. Document in W4 commit. |
| **Silent failure if lib missing** | MED | HIGH (vault silently no-ops) | `VaultCryptoService` throws loud `VaultUnavailableException` (never returns null). W1 enforces. |
| **Wire-contract drift** (Dart sends X, backend expects Y) | MED | HIGH (broken vault) | W2 + W4 land in the same integration window; W5 round-trip test is the drift detector. Commit ordering: W4 (contract) and W2 (client) before W5. |
| **`aes-gcm` removal from backend Cargo.toml breaks build** | LOW | LOW | `cargo build` after removing the dep fails LOUDLY if any reference remains — that's the desired fail-fast. grep `aes_gcm|Aes256Gcm` in `backend/src` before removing. |
| **Recovery-code path regresses** (shares `derive_key`) | LOW | MED | W4 keeps a recovery-scoped `derive_recovery_key`; W4 keeps the recovery-code tests (`vault.rs:197-247`) as the regression guard. |

---

## 8. Sequencing for parallelism

```
W0  (PoC gate — single, ~30min) ──► [aborts the plan if FFI crypto is broken]
                                              │
           ┌──────────────────────────────────┴───────────────────────────┐
           ▼                                                              ▼
  W1  (Dart VaultCryptoService)                                  W4  (backend strip + schema)
           │                                                              │
           ▼                                                              │
  W2  (PasskeyService rewrite ─ uses W1)                                  │
           │                                                              │
           ▼                                                              │
  W3  (screens ─ use W1+W2)                                              │
           │                                                              │
           └─────────────────────────────►─ W5 ◄──────────────────────────┘
                                             (integration round-trip; needs W1+W2+W3+W4)
                                                      │
                                                      ▼
                                             W6 (docs)
```

- **Parallel pair:** **W1 ∥ W4** can start on day 1 in parallel (different
  languages, different files, no shared interface until W5 integrates them).
- **Sequential:** W0 → (W1 ∥ W4) → W2 → W3 → W5 → W6.
- W1 and W4 are both "Simple/Medium" and fast; the critical path is
  W0 → W1 → W2 → W3 → W5 (the Dart side + integration).

---

## 9. Full-gate command set (before final sign-off)

```bash
# 1. Rust side (W4 must leave this green)
cargo clippy --benches --tests --all-features --quiet
cargo fmt --all --check
cargo nextest run
cargo test -p icp-marketplace-api          # backend unit tests (recovery-code path)
rg "encrypt_vault|aes_gcm|Aes256Gcm" backend/src   # MUST be empty (no server vault crypto)

# 2. Flutter side
cd apps/autorun_flutter && flutter analyze
flutter test test/features/vault/          # W0 smoke + W1 service + W5 round-trip
flutter test test/features/passkey/        # W2/W3 screen tests
just test-feature vault                    # if a feature dir is wired into the justfile pattern

# 3. Full gate
just test                                  # Rust + Flutter full suite

# 4. ZK property spot-check (manual proof)
just api-dev-up
# then run the W5 round-trip test; confirm the server logs show NO password field on /vault POST/PUT
```

---

## 10. Confidence

**9/10.** The plan is grounded in a direct read of every cited file. The
highest-risk unknown (Argon2id blocking the UI isolate / `compute()`
isolate-shareability of the `DynamicLibrary` cache) is explicitly a PoC-gated
step in W0/W1 — if it fails, the plan degrades gracefully (sync-behind-spinner
+ follow-up) rather than collapsing. The hardest part of a naive plan (FFI
crypto + Dart bindings) is already built and tested, which is why confidence is
high. The -1 is for the schema-rename decision (FK target needs a verify at
implement time) and the `compute()` UX question.

**(Post-execution note: every risk above was either retired or never
materialised. `compute()` worked as hoped — the UI spinner animates honestly
through the ~0.1–1 s Argon2id derivation. The schema rename landed in `b92a54d4`
with FK target reconciled.)**

---

## 11. Outcome — the vault is genuinely zero-knowledge

The A-4 migration is **complete and proven.** Concretely:

- **The vault password never leaves the device.** It is consumed only by
  `VaultCryptoService.encrypt`/`decrypt`
  (`apps/autorun_flutter/lib/services/vault_crypto_service.dart`), which calls
  the Rust FFI inside a background Dart isolate. `rg "'password':" apps/autorun_flutter/lib`
  returns zero hits over HTTP-body construction.
- **The server cannot decrypt.** `backend/src/vault.rs` contains no vault-crypto
  symbols — `rg "encrypt_vault|aes_gcm|Aes256Gcm" backend/src` is empty. The
  `/api/v1/vault` POST/PUT/GET handlers accept and return only opaque base64
  blobs (`encrypted_data`, `salt`, `nonce`) and store/return them verbatim.
- **Crypto runs client-side via the FFI bridge.** Argon2id (time=3, memory=64
  MiB, parallelism=4, 32-byte output) + AES-256-GCM, with params living in ONE
  place (`crates/icp_core/src/vault.rs:18-24`) — the Dart layer forwards
  password + plaintext only, never re-declares params.
- **End-to-end proof.** The W5 integration round-trip test
  (`apps/autorun_flutter/test/features/vault/zk_round_trip_test.dart`,
  `f1d425d5`) exercises the full ZK property: client-encrypt → POST opaque blob
  → server-store → GET blob → client-decrypt == original plaintext. Negative
  paths fail loud: wrong password and tampered ciphertext both raise
  `VaultDecryptionException` (AES-256-GCM auth-tag failure). The server's
  blindness is asserted directly on the blob bytes.

**Commit hashes:** W1 `714c8568`, W2 `b4d709ab`, W3 `d96661af`,
W4 `b92a54d4` + `30d98a3e`, W5 `f1d425d5`, W6 (this revision). The
`HUMAN_EXPECTATIONS.md` §1 zero-knowledge bullet is now TRUE as-written.
