# Marketplace Scripting Runtime — Migration to TypeScript + QuickJS

- **Status:** DONE — Phase 4 (Lua sunset) complete on 2026-06-30
- **Date:** 2026-06-28 (decision); 2026-06-30 (sunset delivered)
- **Type:** Decision + Plan (ADR-style)
- **Owners:** Marketplace / Platform team

> **Phase 4 delivered.** The Lua runtime has been fully removed; TypeScript/QuickJS is
> the single scripting runtime (see `docs/specs/CLEANUP_PLAN.md` WU-1..WU-10 for the
> execution record). This document is retained as the ADR history. The §12 G5
> dual-runtime deprecation timeline was **collapsed to a direct sunset** (greenfield
> project — no backward compatibility, no Lua corpus to wind down).

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
- **Phase 4 — GA / Lua sunset:** TS-only marketplace authoring. **DONE (2026-06-30)** — the Lua runtime was removed entirely; only TS/QuickJS bundles execute.

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

## §12 Phase 2 Decisions (2026-06)

Recorded during Phase 2 (Parity Hardening) + Phase 3 (Migration Pilot) kickoff. These close out the open questions in §11 and lock in policy for the parity gate.

### Intl — FORBID `Intl.*` in scripts (G7)

Marketplace scripts MUST NOT call `Intl.*` (`Intl.DateTimeFormat`, `Intl.NumberFormat`, `Intl.Collator`, etc.).

- **Rationale:** The default QuickJS build ships without a full ICU data set. Bundling a full-ICU QuickJS bloats the binary (multi-MB locale tables), complicates the Android NDK and WASM toolchains, and is disproportionate to marketplace formatting needs.
- **Enforcement (host side):** the Rust host runs a `validate_intl` AST/static check that rejects any `Intl.*` reference at script-load time. Bundle-time `assertNoNodeBuiltinsInBundle` guards the dev path. Locale-sensitive formatting is delivered instead by the locale-free SDK helpers: `icp_format_number`, `icp_format_icp`, `icp_format_timestamp`, `icp_format_bytes`.
- **Author contract:** scripts that need humanized currency/date must go through those helpers (which the host can localize centrally); they may not reach for `Intl` directly.

### Pedantic lint — `clippy::all` only, NOT `clippy::pedantic` (N1)

- **Clippy gate:** `cargo clippy --workspace --all-targets -- -D warnings` (i.e. `clippy::all` at deny-on-warning). This is the required-green gate.
- **Pedantic is intentionally NOT enforced.** Adding `#![warn(clippy::pedantic)]` would surface an estimated 200–500 lints across unrelated pre-existing backend crates (`crates/**`), which is out of scope for the scripting migration and would derail the gate. Pedantic will be considered only as part of a dedicated, workspace-wide cleanup phase. Do NOT add the pedantic lint as a drive-by.

### Lua deprecation timeline (G5) — SUPERSEDED (collapsed to direct sunset)

A dual-runtime deprecation path was *proposed* here (write-disabled → read-only →
sunset across releases N+2..N+4). It was **never adopted**: the project is greenfield
with no backward-compatibility obligation and no production Lua corpus to wind down, so
the timeline was collapsed to a **direct sunset** delivered in Phase 4 (2026-06-30).
Kept for ADR history.

- **Release N (current):** TS is the primary authoring path; Lua still fully supported (create/edit/run).
- **Release N+2:** Lua becomes **write-disabled** — existing Lua scripts run, but creating/editing Lua scripts is blocked in the UI; TS is the only authoring path for new/changed scripts.
- **Release N+3:** Lua becomes **read-only** — existing Lua scripts continue to run, but no new Lua scripts can be registered at all.
- **Release N+4:** **Lua sunset** — the Lua runtime is removed from the host; only TS/QuickJS bundles execute.

> Status: SUPERSEDED — see the note above. The N+2..N+4 staging was not enacted.

### `cargo fmt` gate scope

`cargo fmt --all --check` is now **workspace-green**. Phase 2 paid down the pre-existing formatting debt across the backend so the formatting gate could be enforced on the whole workspace without churning unrelated PRs. New code must keep it green.

### Documented runtime divergences (N2/N3)

These are intentional, contract-level differences between the legacy Lua runtime and the TS/QuickJS runtime. Scripts must not rely on the legacy Lua behavior:

- **`icp_format_icp` whole floats (N2):** for whole e8s values, the TS helper formats as `"1"` where legacy Lua produced `"1.0"`. The TS output is the canonical form. Scripts/hosts must not depend on the trailing `.0` string.
- **`icp_section` nullish-coalesce semantics (N3):** the TS helper coerces missing `title`/`content` to `""` via `??` (JS nullish), where the legacy Lua `or` would also fall back on `false`. The TS behavior is nullish-only, matching the typed contract; callers should pass explicit strings rather than relying on falsy-coalescing.

These divergences are encoded in the SDK (`packages/marketplace-sdk/src`) and validated by the parity vectors; the Lua corpus migration (Phase 3) will rewrite any scripts that depended on the legacy forms.

### Phase 2 artifacts (this phase)

- Dependency allowlist CI scan: `scripts/check-deps-allowlist.mjs` + `scripts/deps-allowlist.json` (zero-dep-at-runtime for packages; dev deps on an explicit allowlist). Wired as `npm run check:deps`.
- Pilot migration: `packages/marketplace-sdk/samples/pilot-sample.ts` (the `kDefaultSampleLua` Flutter sample ported to TS), bundled to a self-contained IIFE fixture at `crates/icp_core/tests/fixtures/pilot_sample.bundle.js` via `npm run -w @icp-cc/marketplace-sdk build:samples`, with a byte-equality drift guard (`pilot.bundle-sync.test.ts`) and a real-QuickJS e2e (`pilot.e2e.test.ts`).
