# Human Expectations — icp-cc

> A **living reference** for what the humans behind icp-cc actually value. When
> guidance arrives via prompts, capture it here so every agent works from the
> same picture. Linked from `AGENTS.md`. Distilled from `AGENTS.md`, the
> example-dapp plan (`docs/specs/EXAMPLE_DAPP_INTEGRATION_PLAN.md`), and stated
> project direction.

## 1. What icp-cc is for (product vision)

A **premium Flutter desktop/mobile app** that lets a user:

- Hold **profiles** + owned **keypairs** (1–10 per profile; never shared across profiles).
- Run **signed TypeScript/QuickJS scripts** against **REAL Internet Computer
  canisters** (host-mediated effects — the bundle never holds raw keys).
- **Publish/browse** scripts via a marketplace (signed, verifiable).
- Authenticate with **passkey + zero-knowledge vault** (passkey for login, a
  separate vault password for client-side encryption; losing one ≠ losing data).
  > *(IMPLEMENTED — A-4 vault zero-knowledge migration COMPLETE, 2026-07-04.
  > Argon2id + AES-256-GCM run **client-side** via the Rust FFI bridge; the
  > password never leaves the device; the backend is a pure opaque-blob store
  > (it stores ciphertext + salt + nonce and returns them verbatim — it cannot
  > decrypt). Proven end-to-end by the W5 round-trip test. See
  > `docs/specs/A4_VAULT_ZK_MIGRATION_PLAN.md`.)*

**Now also:** interface with **full dapps**, not just raw scripts. Each example
dapp has ≥2 canisters (frontend + backend). icp-cc drives **BOTH/EITHER**:
- **Frontend** → embedded browser (real dapp UI), with the active profile's
  identity injected.
- **Backend** → native TS/QuickJS bundle talking to the backend canister directly.

## 2. Quality bar (non-negotiable)

- **Premium only.** No slop, no stubs, no placeholders, no "TODO" shipped as a
  feature. Every shipped thing works as a user.
- **Real services, never mocks in prod.** Tests use real keypairs; never mock
  cryptography.
- **Loud failures, always.** No `try { … } catch (_) {}`, no
  `if (status != 200) return null`, no silent anon fallback. Match-style
  handling; errors carry bodies + codes and surface to the UI/log.
- **Minimal clicks; keyboard-first.** Operable from the keyboard alone.
- **DRY/KISS/YAGNI to the radical extreme.** A single constant lives in ONE
  place; everywhere else references the symbolic name.
- **All I/O has timeouts.** Threads check termination flags.
- **Pedagogical value.** Code and examples should teach; a newcomer can follow
  the story end to end.
- **Iterate until done.** Build a working PoC first, prove it as a user, then
  write failing tests, then productionize. Commit each unit. Below 8/10
  confidence → stop and ask.

## 3. Pedagogical / project-direction intent

The **example dapp** exists for two reasons: to **TEACH** the dual-path model,
and to **PROVE** it against a real canister. Therefore it must **always** remain:

- Runnable **standalone** with `dfx` (frontend canister + backend canister),
  no icp-cc required.
- Runnable **integrated** from inside icp-cc (Backend Direct today; embedded
  frontend browser as the platform permits).
- **Talks to a REAL canister** — never a stub or recorded fixture.

A dapp that drifts from "real + dual-path + teachable" has drifted from intent.

## 4. Scope guardrails

- **Greenfield.** No backward compatibility, no legacy, no migration shims — fix
  things properly.
- **No offline mode / no cached fallbacks.** A failed call fails loudly.
- **Postgres** if a database is ever needed.
- **Orchestrate subagent swarms** for plan/build/verify; each unit gets its own
  commit with a clean message.
- **User-facing first.** No backend-only change lands without UI/CLI access and
  updated navigation.

## 5. How to keep this doc current

- When the human gives guidance in a prompt, add/refine the relevant bullet here
  in the same change (or flag it for the next verifier pass).
- Prefer crisp bullets over prose; link to the source prompt/spec where useful.
- If reality diverges from this doc, the doc wins as the intent of record — fix
  the code, or explicitly update the doc with the human's call.
