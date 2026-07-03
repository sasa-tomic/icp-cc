# icp-cc Poll — standalone Internet Computer dapp

A small **poll / voting** dapp that runs as a real Internet Computer application:
a **Motoko backend canister** + a **vite/TypeScript frontend** (served from an
*assets* canister). It is the reference dapp for the icp-cc dual-path
integration model (see `docs/specs/EXAMPLE_DAPP_INTEGRATION_PLAN.md`).

> Toolchain: **dfx 0.29.2** (legacy: `dfx.json`, port **4943**, `@dfinity/agent`
> + `@dfinity/identity`). Do **not** use the newer `icp-cli` / `@icp-sdk` style.

## What it does

- **Create** a poll (question + ≥2 options).
- **Vote** — one vote per principal; re-voting **replaces** your previous choice
  (idempotent per principal, no stacking).
- See **live tallies** (vote counts per option, indexed).
- Shows **your principal** (`whoami`).

All state is **stable** — it survives canister upgrades via the Motoko
`preupgrade`/`postupgrade` + `transient` stable-storage pattern.

## Backend interface (Candid)

```
type PollRecord = record { id : text; question : text; options : vec text; creator : principal };
service : {
  listPolls : () -> (vec PollRecord) query;
  getTally  : (text) -> (vec nat) query;          // indexed by option
  whoami    : () -> (text) query;                 // msg.caller
  createPoll: (text question, vec text options) -> (text);   // returns new poll id
  vote      : (text pollId, nat optionIndex) -> ();          // one vote per principal
}
```

Inputs are validated; bad input is rejected loudly (`throw Error.reject(...)`)
— there are no silent failures. `getTally` of an unknown poll id returns an
empty vector (a deliberate read default, documented in `main.mo`).

## Prerequisites

- `dfx 0.29.2` on `PATH`
- Node.js v22 (with `npm`)

## Run it (local replica)

```bash
cd examples/icp_poll_dapp
dfx start --background --clean   # local replica on 127.0.0.1:4943
npm install                      # frontend deps (@dfinity/agent, vite, …)
dfx deploy                       # builds + installs backend + frontend canisters
```

Then open the printed frontend URL, e.g.:

```
http://<frontend-id>.localhost:4943/                            # recommended
http://127.0.0.1:4943/?canisterId=<frontend-id>                 # legacy form
```

In a standalone browser the frontend generates a random local identity (kept in
`localStorage`, so your principal/votes persist across reloads). No Internet
Identity is required. When embedded inside icp-cc's webview, the host injects
`window.__ICPCC_IDENTITY` (an Ed25519 secret key) and the frontend signs as the
active profile's principal instead — see `src/frontend/src/index.ts`.

### Mainnet (optional)

```bash
dfx deploy --network ic          # needs a cycles wallet
```

The frontend host switches automatically: `https://icp-api.io` (mainnet) vs
`http://127.0.0.1:4943` (local), driven by `DFX_NETWORK` at build time.

## Drive the backend directly

```bash
dfx canister call backend whoami
dfx canister call backend createPoll '("Tea or coffee?", vec {"Tea"; "Coffee"})'
dfx canister call backend listPolls
dfx canister call backend vote '("1", 1)'
dfx canister call backend getTally '("1")'        # (vec { 0 : nat; 1 : nat })
```

## Deployed canister ids (local replica, verified 2026-07-03)

Single source of truth: **`canister_ids.local.json`** (gitignored; produced
from `dfx deploy`).

| Canister  | Local id                          |
|-----------|-----------------------------------|
| backend   | `uxrrr-q7777-77774-qaaaq-cai`     |
| frontend  | `u6s2n-gx777-77774-qaaba-cai`     |

## Layout

```
dfx.json                       backend (motoko) + frontend (assets), port 4943
src/backend/main.mo            the Poll actor (stable storage, validation)
src/frontend/index.html        UI scaffold + styles
src/frontend/src/index.ts      agent + actor; dual identity mode; all UI wiring
src/frontend/vite.config.ts    build config; injects DFX_NETWORK + backend id
src/frontend/tsconfig.json
.ic-assets.json5               asset security policy
canister_ids.local.json        (gitignored) backend/frontend ids
```

`src/declarations/` and `dist/` are **generated** (by `dfx generate` and
`vite build`) and are gitignored; the frontend imports `idlFactory` straight
from `src/declarations/backend/backend.did.js`.
