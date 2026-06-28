# Marketplace Scripting Runtime — Migration to TypeScript + QuickJS

- **Status:** Accepted — Primary High-Priority Objective
- **Date:** 2026-06-28
- **Type:** Decision + Plan (ADR-style)
- **Owners:** Marketplace / Platform team

---

## 1. Objective (High Priority)

Migrate the marketplace's user-authored scripting runtime from **Lua** to **TypeScript executing on QuickJS**, to deliver static analysis, first-class testing, and best-in-class AI + human developer ergonomics for marketplace scripts. This is the primary high-priority initiative for the scripting platform.

**One-line summary:** *Same script, developed and tested locally, runs unchanged in production — typed, testable, and AI-friendly.*

## 2. Problem Statement

The current Lua-based scripting suffers from three concrete, compounding problems:

1. **No static analysis** — Lua (as used) has no mature type checker or linter on par with `tsc`/Pyright. Defects surface only at runtime.
2. **Awkward, hard-to-test code** — minimal testing tooling, an indirect table-centric data model, and no mocking/coverage story.
3. **Poor AI + human ergonomics** — both AI assistants and human authors struggle; Lua is comparatively underrepresented in model training data and in general developer familiarity.

**Net effect:** higher defect rates, slower authoring, weaker automation, and a poor experience for marketplace developers.

## 3. Decision

Adopt **TypeScript** as the authoring language, compiled/bundled and executed on **QuickJS** as the embedded engine, as the target runtime for marketplace scripts.

## 4. Decision Rationale

Against the three evaluation criteria:

| Criterion | TypeScript + QuickJS |
| --- | --- |
| Static analysis | First-class (`tsc`, ESLint, LSP, Pyright-class tooling) |
| Testability | Vitest/Jest, mocking, coverage — best-in-class |
| AI + human ergonomics | Best-served language by AI tooling; most widely known |

**QuickJS is fit-for-purpose:** small footprint, embeddable, WASM-portable, sandboxable, ES2023+-complete, and proven at scale (Cloudflare, Figma, Shopify).

## 5. Alternatives Considered (and Why Rejected)

- **Teal / LuaCATS** — typed Lua. Lowest-risk incremental path, but remains in Lua's awkwardness and a small tooling ecosystem.
- **Luau** (Roblox's typed Lua) — real type checker + LuaJIT-class performance; the best option if keeping a Lua flavor. **Revisit if full TS migration proves too costly.**
- **Starlark** — Python-like, deterministic, sandboxed. Strong for rules/transforms only; weak for general-purpose/async.
- **CEL** — excellent for pure rules/predicates; insufficient for general-purpose scripting.
- **Python** — strong AI/typing/testing, but heavy embed (~10s MB, GIL) and hard to sandbox untrusted code.
- **Rhai** — embed-friendly + trivial sandboxing, but dynamically typed, niche (poor AI), tiny ecosystem.
- **Rust (as a scripting language)** — not viable; no `eval`/dynamic loading. Only relevant as a WASM *source* language.
- **WASM (multi-language)** — strongest isolation + flexibility, but highest complexity and no single language story.

## 6. Target Architecture (Dev/Prod Parity)

**Core principle:** *The artifact you test locally is the artifact that runs in production.*

### Components
1. **Typed SDK package** (`@yourco/marketplace-sdk`): TypeScript types + `.d.ts`. Local = mock/in-memory implementation; prod = host bindings. **Types are the contract.**
2. **Bundle artifact:** esbuild/rollup → single ESM/IIFE bundle, no runtime imports. Optionally precompiled to QuickJS bytecode (`qjsc`) for cold start.
3. **Local QuickJS test harness:** run tests inside **real QuickJS** via `quickjs-emscripten` (`@jitl/quickjs-*`) in Vitest — so dev, CI, and prod share the exact same engine (no V8-vs-QuickJS drift).
4. **Scaffold CLI** (`npx create-marketplace-script`): TS + SDK types + Vitest-QuickJS + esbuild — parity-correct by default for every new script.

### Non-JS host
The bundle artifact is host-language-agnostic: loads in Go (`quickjs-go`), Rust (`rquickjs`), or Python QuickJS bindings. Scripts and tests do not depend on the host language.

## 7. Parity Requirements / Managed Risks

- **QuickJS is an engine, not Node.** Forbid Node built-ins (`fs`/`path`/`crypto`/`process`) via lint + esbuild config.
- **No built-in `fetch`/`setTimeout`/`URL`/`TextEncoder`** — expose these only through the typed SDK.
- **`std`/`os` QuickJS modules are non-portable** — disable them in sandbox mode.
- **Intl/locale is limited** without a full-ICU build — flag for currency/date formatting code.
- **Third-party npm deps** may pull in Node/browser-only code — bundle + lint, or maintain an allowlist.
- **SDK drift is the #1 parity killer** — treat the SDK as a versioned contract; CI must test against the same SDK version the host implements.

## 8. Migration Considerations

- **Existing Lua corpus** needs assessment. Options: (a) a dual-runtime period with Lua deprecated on a timeline; (b) AI-assisted transpilation/rewrites Lua → TS.
- **Phasing recommended** (below) to de-risk rollout.

## 9. Phased Plan

- **Phase 0 — Foundations:** embed QuickJS in the host; define sandbox + resource limits (CPU/memory/time); expose a minimal SDK surface.
- **Phase 1 — SDK + Tooling:** typed SDK package, scaffold CLI, Vitest-QuickJS harness, esbuild + lint rules (no Node built-ins).
- **Phase 2 — Parity Hardening:** Intl/SDK-drift controls, dependency allowlist, CI parity gate (local QuickJS == prod QuickJS).
- **Phase 3 — Migration:** onboard pilot scripts; AI-assisted Lua → TS rewrites; publish a Lua deprecation timeline.
- **Phase 4 — GA / Lua sunset:** TS-only marketplace authoring.

## 10. Success Criteria

- Marketplace scripts type-check and unit-test locally and run **unchanged** in production.
- Measurable reduction in script defects / runtime errors vs. the Lua baseline.
- AI-assisted authoring produces working scripts on first attempt at a materially higher rate.
- Cold-start / throughput performance within budget (vs. LuaJIT).

## 11. Open Questions / Risks

- Cold-start / throughput vs. **LuaJIT** — needs a benchmark.
- Resource-limit / sandboxing model specifics (CPU, memory, time, network).
- Size of the existing Lua corpus → migration effort.
- Intl requirements (currency/date) for target locales.
