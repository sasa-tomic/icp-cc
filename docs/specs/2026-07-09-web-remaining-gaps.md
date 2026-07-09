# Web (Flutter Web) — Remaining Gaps

**Status:** Plan · **Date:** 2026-07-09 · **Author:** Orchestrator
**Predecessors:** R-1..R-5, R-3a, R-3b, IC-agent — ALL ✅ COMPLETE (see
`docs/BROWSER_SUPPORT.md` Track items + `docs/specs/2026-07-09-r3-web-script-execution.md`).

> **Empirical grounding.** A ground-truth audit (every claim cited to `file:line`)
confirmed the crypto/bridge layer (Ed25519, principal, Argon2id, AES-GCM, QuickJS,
IC HTTP agent, CORS proxy) is genuinely real on Web. What remains are **three**
concrete gaps surfaced by that audit — two of them UNDOCUMENTED crash-on-boot bugs.

---

## §0 Ground truth (what is actually done vs. stubbed)

| Area | Verdict | Evidence |
|------|---------|----------|
| Ed25519 keygen/sign/principal | ✅ REAL | `native_bridge_web.dart:198-359` |
| Vault crypto (Argon2id + AES-GCM) | ✅ REAL | `native_bridge_web.dart:237-617` |
| QuickJS exec + lint/validate (R-3a) | ✅ REAL | `lib/rust/web/quickjs_engine.dart`; 51 golden vectors |
| IC HTTP agent (R-3b) | ✅ REAL | `lib/rust/web/ic_agent_engine.dart` + backend CORS proxy `handlers/ic_proxy.rs` |
| CORS / secure-storage / passkeys | ✅ REAL | `backend/src/main.rs:350`; `flutter_secure_storage_web`; `passkey_platform.dart:6` |
| `--wasm` target | 🟢 Correctly out of scope (transitive `dart:ffi`/`package:js`) | — |
| **`ProfileRepository` on Web** | ❌ **CRASH AT BOOT** | `profile_repository.dart:52-53` throws `UnsupportedError`; `dart:io` File-backed; `main.dart:69` triggers it |
| **`ScriptRepository` on Web** | ❌ **CRASH** | `script_repository.dart:42-43` throws; `dart:io` File-backed |
| **secp256k1 (alg=1) on Web** | ⚠️ STUBBED (documented deferred) | `native_bridge_web.dart:280,316,339` throw; first-class UI option (`key_parameters_dialog.dart:77`); deps ALREADY present (`bip32`, `elliptic`, `pointycastle`) |
| **BROWSER_SUPPORT.md** | ⚠️ STALE/CONTRADICTORY | L26 says IC calls "❌ STUBBED" (contradicts L25/L187); L10-11/L168 overstate runtime coverage |

---

## §1 The three work units (sequenced; serialize implementers — shared repo)

### WU-1 — P0 · Web JSON store: unblock ProfileRepository + ScriptRepository
**Impact:** CRITICAL. Without this the app **crashes at boot on Web** (`main.dart:69`
→ `ProfileController.ensureLoaded()` → `loadProfiles()` → `_ensureInitialized()` →
throw). Every identity/account/vault/passkey/share/publish flow is dead. This is an
UNDOCUMENTED gap that directly contradicts `BROWSER_SUPPORT.md` L10-11.

**Design (KISS — reuse existing deps):** Introduce a tiny JSON document store behind
a conditional-import split (mirrors the established `native_bridge.dart` pattern):
- Interface `JsonDocumentStore` (pure Dart): `Future<String?> read(String key)`,
  `Future<void> write(String key, String json)`, `Future<void> delete(String key)`.
- `file_json_store.dart` (IO, `dart.library.io`): wraps the existing `file_io.dart`
  `readJson`/`writeJson` + `path_provider` (the current behaviour, unchanged).
- `web_json_store.dart` (Web, `dart.library.html`): uses `shared_preferences`
  (**already a prod dep**, `pubspec.yaml:53`; `shared_preferences_web` backs it with
  `localStorage`). Profile/script JSON is non-sensitive metadata; sensitive keys stay
  in `flutter_secure_storage` (already Web-capable). No new dep.

**Wiring:** `ProfileRepository` + `ScriptRepository` delegate their `profiles.json` /
`scripts.json` read/write to the store selected by the conditional import. Remove the
two `kIsWeb` throw sites. The `_overrideDirectory` test-injection path stays (tests
pass a temp dir → the IO store). Add a `_overrideStore` injection point for symmetry.

**Files:** new `lib/services/json_store.dart` (facade) + `file_json_store.dart` +
`web_json_store.dart`; edit `profile_repository.dart`, `script_repository.dart`.
**Verification:** `flutter test` (existing repo tests stay green via the IO path +
injection); a new VM test of the store interface contract; `flutter build web` clean;
a Web smoke (boot the app — no crash). Confidence gate ≥8/10.
**Commit:** one unit.

### WU-2 — P1 · secp256k1 (alg=1) keygen / sign / principal on Web
**Impact:** HIGH. A first-class UI option (`key_parameters_dialog.dart:77`
"Secp256k1 — Bitcoin/Ethereum compatible") that works on native but throws on Web.
Account + script signing with `alg:1` (`account_signature_service.dart:252`,
`script_signature_service.dart:163`) are web-broken for any secp256k1 keypair.

**Design — pure-Dart port of `crates/icp_core/src/keypair.rs:43-129` + `principal.rs`:**
The deps are ALREADY in `pubspec.yaml` (`bip32: ^2.0.0`, `elliptic: ^0.3.12`,
`pointycastle: ^3.9.1` dev). Port the three operations:

1. **BIP32 key derivation** (`keypair.rs:43-67`): seed → `Xpriv::new_master` → derive
   `m/44'/223'/0'/0/0` → 32-byte private key + uncompressed pubkey (65 bytes
   `0x04||X||Y`). Pure-Dart via `package:bip32` (`BIP32.fromSeed` → `derivePath`).
2. **ECDSA sign** (`keypair.rs:99-129`): SHA-256(message) → secp256k1 ECDSA → 64-byte
   compact sig (low-S). Pure-Dart via `package:elliptic` (secp256k1 curve) or
   `pointycastle`'s `ECDSASigner`. **Must be deterministic/low-S** to match native
   (`bitcoin` crate's `sign_ecdsa` is RFC 6979 deterministic low-S).
3. **Principal derivation** (`principal.rs:26-41`): RFC 5480 SPKI DER for secp256k1
   (`SEQUENCE { SEQUENCE { OID ecPublicKey(1.2.840.10045.2.1), OID secp256k1
   (1.3.132.0.10) }, BIT STRING <uncompressed point> }`) → SHA-224 → `[0x02]` → CRC32
   → base32. **Reuses the existing `_principalFromEd25519PublicKey` algorithm** — only
   the DER prefix differs (extract a shared `_principalFromDer` helper).

**Wiring:** replace the three `_secpUnsupported` throw sites in `native_bridge_web.dart`
(`:280,316,339`) with real implementations. Generalize the principal helper to take a
DER prefix (Ed25519 RFC 8410 + secp256k1 RFC 5480).

**Files:** `native_bridge_web.dart`; possibly a new `lib/rust/web/secp256k1.dart` if
the code exceeds ~150 lines (keep the bridge file lean).
**Verification:** cross-compat golden vectors — derive the secp256k1 keypair /
principal / signature for the standard zero-entropy BIP39 mnemonic on BOTH native and
Web, assert byte-identical output (mirrors the R-2 Ed25519 proof). Add to
`test/features/web/`. `flutter test` + `flutter build web` clean. Confidence ≥8/10.
**Commit:** one unit.

### WU-3 — P0 · Documentation hygiene (cheap, high-value)
**Impact:** MEDIUM. The doc currently misleads any planner into re-doing R-3b, and
overstates web coverage (claiming identity flows "run" when they crash).

- `docs/BROWSER_SUPPORT.md`:
  - **L26** — delete the stale "❌ STUBBED" row; IC canister calls are ✅ (R-3b done,
    `native_bridge_web.dart:381-451`). The TL;DR table should reflect ground truth.
  - **L10-11** — correct the overstatement: the crypto/bridge layer runs; the
    file-IO-backed repositories were a gap (WU-1 fixes them). After WU-1 lands,
    update to reflect reality.
  - **L98-99** ("What is still stubbed") — `fetchCandid`/`parseCandid`/etc. are DONE;
    remove them; keep only secp256k1.
  - secp256k1 row (L24) — after WU-2, mark ✅.
- `docs/specs/NEXT_PHASE_PLAN.md` + `NEXT_ITERATION_PLAN.md` — flag as SUPERSEDED re:
  Web (they predate the 2026-07-09 web push and say "R-1 deferred").
- `docs/specs/2026-07-09-r3-web-script-execution.md` §5 L216 — stale "Full R-3b
  deferred" sentence; mark done (header already says complete).

**Commit:** one unit (do AFTER WU-1/WU-2 so the doc reflects shipped reality).

---

## §2 Execution order

**WU-1 → WU-2 → WU-3.** (Serialize — shared working tree + build caches; parallel
commits race on the index.) WU-1 first (unblocks boot); WU-2 (feature parity); WU-3
last (doc reflects what shipped). Each WU = one commit.

## §3 Verification (per WU)
- `flutter analyze` clean (no warnings).
- `flutter test` — existing suite green; new tests added per WU.
- `flutter build web` exit 0.
- WU-1: boot the app on Web (no crash at `main.dart:69`).
- WU-2: cross-compat golden vectors (native ↔ Web byte-identical).
- Confidence ≥8/10 per WU, else STOP and surface.

## §4 Out of scope
- `--wasm` Flutter target (correctly bounded — transitive `dart:ffi`/`package:js`).
- Live browser WebAuthn round-trip for passkeys (needs real authenticator; standard).
- Per-script persistent state across reloads (not in the engine contract).
