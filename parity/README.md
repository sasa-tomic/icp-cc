# Parity Vectors

`parity/vectors.json` is the **single source of truth** for the output of the
`icp_*` runtime helpers across the two scripting engines (QuickJS / TypeScript
and Lua). It is consumed by:

- the Rust parity test at `crates/icp_core/tests/parity_vectors.rs` (runs every
  case against both engines on every `cargo nextest run -p icp_core`), and
- the Node-side harness in `packages/marketplace-sdk` (cross-checks the
  TypeScript/QuickJS bundle output against the same goldens).

When the two implementations are changed together, this file is the contract
that prevents silent drift.

## Schema

```jsonc
{
  "schemaVersion": 1,                 // bump on incompatible schema change
  "sdkContractVersion": "0.1.0",      // MUST equal icp_core::SDK_CONTRACT_VERSION
  "notes": "...",                     // free-form documentation
  "cases": [
    {
      "id": "unique_case_id",
      "helper": "icp_call",           // runtime snake_case name in BOTH engines
      "args": [ /* positional JSON; each element is one positional argument */ ],
      "expectedJs":  { /* authoritative QuickJS output */ },
      "expectedLua": null,            // null  => identical to expectedJs
      "notes": "optional per-case note"
    }
  ]
}
```

- `args` is a **positional** JSON array. Each element becomes one positional
  argument to the helper (e.g. `icp_format_icp` takes `[value, decimals]`).
- `expectedJs` is **authoritative**. The Rust test canonicalises both the actual
  output and the golden by recursively sorting object keys, so key order does
  not matter; values must match exactly.
- `expectedLua` is `null` when Lua must produce the same value as QuickJS. Set
  it to a literal JSON value only to document an accepted divergence.

## How to extend

1. Add a new case object with a unique `id`.
2. Derive `expectedJs` from the frozen helper bodies in
   `crates/icp_core/src/js_engine/runtime.rs` (`HOST_BOOTSTRAP_JS`). Those
   bodies are **immutable**; if they change the version must change.
3. Run `cargo nextest run -p icp_core --test parity_vectors`. If your
   `expectedJs` is wrong the failure prints actual vs expected — correct the
   golden to match the frozen output.
4. Only if Lua genuinely differs (and the difference is accepted) set
   `expectedLua` and record the reason in `notes`.

## Divergence policy

Divergences are tolerated only when they are **measured, documented, and
localized** to number formatting. The current accepted divergence:

| Case | QuickJS | Lua | Reason |
|------|---------|-----|--------|
| `icp_format_icp_whole_divergence` (`icp_format_icp(100000000, 8)`) | `"1"` | `"1.0"` | QuickJS `String(1.0)` drops the trailing zero; Lua `tostring(1.0)` keeps it. Non-whole results agree. |

Any *new* divergence is a regression until reviewed and recorded here. The
frozen decision is that both engines stay locale-free; scripts must use the
`icp_format_*` helpers rather than `Intl.*` (see the Intl probe test).
