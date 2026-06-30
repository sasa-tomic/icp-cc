# Parity Vectors

`parity/vectors.json` is the **single source of truth** for the output of the
`icp_*` runtime helpers on the TypeScript/QuickJS runtime. It is consumed by:

- the Rust parity test at `crates/icp_core/tests/parity_vectors.rs` (runs every
  case through the QuickJS engine on every `cargo nextest run -p icp_core`), and
- the Node-side harness in `packages/marketplace-sdk` (cross-checks the
  TypeScript/QuickJS bundle output against the same goldens).

Because there is exactly one scripting runtime, this file is the regression
contract for the helper bodies: any silent change to a helper's frozen output
is caught here.

## Schema

```jsonc
{
  "schemaVersion": 1,                 // bump on incompatible schema change
  "sdkContractVersion": "0.1.0",      // MUST equal icp_core::SDK_CONTRACT_VERSION
  "notes": "...",                     // free-form documentation
  "cases": [
    {
      "id": "unique_case_id",
      "helper": "icp_call",           // runtime snake_case name installed by the engine
      "args": [ /* positional JSON; each element is one positional argument */ ],
      "expectedJs":  { /* authoritative QuickJS output */ },
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

## How to extend

1. Add a new case object with a unique `id`.
2. Derive `expectedJs` from the frozen helper bodies in
   `crates/icp_core/src/js_engine/runtime.rs` (`HOST_BOOTSTRAP_JS`). Those
   bodies are **immutable**; if they change the version must change.
3. Run `cargo nextest run -p icp_core --test parity_vectors`. If your
   `expectedJs` is wrong the failure prints actual vs expected — correct the
   golden to match the frozen output.

## Formatting policy

The engine is locale-free. Scripts must use the `icp_format_*` helpers rather
than `Intl.*` (see the Intl probe test in `crates/icp_core/tests/intl_probe.rs`),
which is statically rejected. Whole-number formatting is well-defined: QuickJS
`String(1.0)` drops the trailing zero, producing `"1"` — see the
`icp_format_icp_whole` case.
