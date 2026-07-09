//! Content-based source-language detector for script bundles.
//!
//! Single source of truth for the `language` field surfaced by `GET
//! /preview` and `GET /scripts/:id`. The runtime is **TypeScript-on-QuickJS
//! ONLY** (see `AGENTS.md`); a Lua bundle is stale and CANNOT execute. The
//! detector's job is therefore to recognize valid TS contract bundles and flag
//! Lua/unknown **honestly** — never to fabricate `"typescript"` for content
//! that isn't TS.
//!
//! Detection inspects the bundle text directly (no DB column, no declared
//! metadata) so the UI badge always reflects what the bundle *actually is*,
//! not what a stale seed or a mislabeled upload claims.
//!
//! # Markers (defined ONCE here, referenced by name everywhere)
//!
//! **TypeScript / QuickJS** — the app-contract patterns from `AGENTS.md`:
//!   - `globalThis.init` / `globalThis.view` / `globalThis.update` — the IIFE
//!     export contract every shipped TS bundle uses.
//!   - the single-object return shape `effects: []` / `state:` — TS bundles
//!     return one `{ state, effects: [] }` object (Lua returns two values).
//!   - JS-only lexemes: `=>` arrows, `const `/`let ` declarations, `//` line
//!     comments, `"use strict"`, TS type annotations (`interface `, `: type`).
//!
//! **Lua** (stale — the runtime dropped Lua):
//!   - the `end` keyword closing a `function`/`if`/`for` block (TS uses `}`).
//!   - `local ` declarations (TS has no `local` keyword).
//!   - multireturn `}, {` — Lua returns `state, effects` as TWO values; TS
//!     returns one `{ state, effects: [] }` object. The `}, {` shape is the
//!     most reliable Lua signature in this codebase's seed/fixtures.
//!
//! When Lua and TS signals conflict, **Lua wins ties**: a stale Lua bundle
//! MUST NOT be badged "TypeScript" (the exact bug this fixes). An honest
//! "Lua" verdict is strictly safer than a false "TypeScript".

/// The detected source language of a script bundle.
///
/// Serialized as its lowercase string identifier (`"typescript"` / `"lua"` /
/// `"unknown"`) so the wire shape stays stable and the frontend maps it to a
/// display label.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScriptLanguage {
    /// Valid TypeScript / QuickJS contract bundle — the only runtime-supported
    /// language.
    TypeScript,
    /// Stale Lua bundle — cannot execute in the TS/QuickJS runtime. The UI must
    /// badge this honestly (e.g. "Legacy"), never as "TypeScript".
    Lua,
    /// Indeterminate content (no clear contract markers either way). The UI
    /// shows NO language badge rather than guess.
    Unknown,
}

impl ScriptLanguage {
    /// Detects the language of `bundle` by inspecting its content.
    ///
    /// Pure, allocation-free, deterministic. Safe to call on read for every
    /// `/preview` and `/scripts/:id` response — the cost is a handful of
    /// substring scans over a typically-small bundle.
    pub fn detect(bundle: &str) -> Self {
        let lua = lua_signal(bundle);
        let ts = typescript_signal(bundle);
        if lua == 0 && ts == 0 {
            return ScriptLanguage::Unknown;
        }
        // Tie → Lua (see module docs: a stale Lua bundle must never be badged
        // TypeScript). `lua > 0` is required so a pure-TS bundle (lua == 0)
        // resolves to TypeScript even when ts is small.
        if lua > 0 && lua >= ts {
            ScriptLanguage::Lua
        } else {
            ScriptLanguage::TypeScript
        }
    }

    /// The stable wire identifier — the value of the JSON `language` field.
    pub fn as_str(&self) -> &'static str {
        match self {
            ScriptLanguage::TypeScript => "typescript",
            ScriptLanguage::Lua => "lua",
            ScriptLanguage::Unknown => "unknown",
        }
    }
}

/// Count of distinct Lua-only signal hits in the bundle. Each marker is a
/// construct that does NOT appear in a valid TypeScript/QuickJS contract
/// bundle, so any non-zero score is strong evidence the bundle is stale Lua.
///
/// Defined inline (not a `const` slice) because the checks need word/line
/// context, not bare substrings — a bare `"end"` would false-match `end`
/// inside JS strings. The checks here anchor on Lua syntax shape.
fn lua_signal(bundle: &str) -> u32 {
    let mut score = 0u32;
    // `local ` declaration — Lua-only keyword (TS has no `local`).
    if bundle.contains("local ") {
        score += 1;
    }
    // The `end` keyword closing a block. Anchor on a line-start (possibly
    // indented) `end` so it matches Lua's `function … end` / `if … end`
    // without matching the word "end" inside a JS string or identifier.
    if bundle
        .lines()
        .any(|line| line.trim_start().starts_with("end"))
    {
        score += 1;
    }
    // Multireturn `}, {` — Lua's `return { … }, { … }` (two values). TS
    // contract bundles return ONE `{ state, effects: [] }` object, so this
    // two-value shape is the most reliable Lua signature in this codebase.
    if bundle.contains("}, {") || bundle.contains("},{}") {
        score += 1;
    }
    // Lua string concatenation `..` — TS uses `+` / template literals.
    // (Bare `..` is rare in TS bundles; weight lightly via a single hit.)
    if bundle.contains("..\"") || bundle.contains(".. '") {
        score += 1;
    }
    score
}

/// Count of distinct TypeScript/QuickJS-only signal hits. Each marker is a
/// construct that does NOT appear in valid Lua, so any non-zero score is
/// strong evidence the bundle is the runtime-supported TS contract.
fn typescript_signal(bundle: &str) -> u32 {
    let mut score = 0u32;
    // IIFE export contract — every shipped TS bundle exposes its entry points
    // on `globalThis`. This is the single most reliable TS signature.
    if bundle.contains("globalThis.") {
        score += 1;
    }
    // Single-object return shape `{ state, effects: [] }`. The `effects: []`
    // literal (JS object key + empty array) is JS-only syntax; Lua tables use
    // `effects = {}`.
    if bundle.contains("effects:") || bundle.contains("state:") {
        score += 1;
    }
    // JS arrow function — Lua has no `=>`.
    if bundle.contains("=>") {
        score += 1;
    }
    // JS block-scoped declarations — Lua has no `const`/`let`.
    if bundle.contains("const ") || bundle.contains("let ") {
        score += 1;
    }
    // JS line comment — Lua uses `--`.
    if bundle.contains("//") {
        score += 1;
    }
    // JS strict-mode directive — Lua has no equivalent.
    if bundle.contains("\"use strict\"") || bundle.contains("'use strict'") {
        score += 1;
    }
    score
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A real TS/QuickJS contract bundle (mirrors `examples/01_hello_world.js`).
    const TS_BUNDLE: &str = "\"use strict\";
(() => {
  function init() {
    return { state: { count: 0, name: \"\" }, effects: [] };
  }

  function view(state) {
    const count = state.count || 0;
    return {
      type: \"column\",
      children: [
        { type: \"text\", props: { text: \"Count: \" + count } },
      ],
    };
  }

  function update(msg, state) {
    if (msg.type === \"inc\") {
      return { state: { ...state, count: (state.count || 0) + 1 }, effects: [] };
    }
    return { state: state, effects: [] };
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();";

    /// A stale Lua bundle (the shape the old seed + test fixtures shipped).
    const LUA_BUNDLE: &str = "function init(arg)
  return {
    message = \"Hello from published script!\",
    count = 0
  }, {}
end

function view(state)
  return {
    type = \"text\",
    text = state.message
  }
end

function update(msg, state)
  if msg.type == \"increment\" then
    state.count = state.count + 1
  end
  return state, {}
end";

    #[test]
    fn detects_real_typescript_contract_bundle() {
        assert_eq!(
            ScriptLanguage::detect(TS_BUNDLE),
            ScriptLanguage::TypeScript
        );
        assert_eq!(ScriptLanguage::detect(TS_BUNDLE).as_str(), "typescript");
    }

    #[test]
    fn detects_stale_lua_bundle() {
        // The acceptance gate for UXR5-2: a Lua bundle MUST NOT be detected as
        // TypeScript (the bug was a hardcoded "TypeScript" badge over Lua).
        let detected = ScriptLanguage::detect(LUA_BUNDLE);
        assert_eq!(detected, ScriptLanguage::Lua);
        assert_ne!(detected, ScriptLanguage::TypeScript);
        assert_eq!(detected.as_str(), "lua");
    }

    #[test]
    fn detects_minimal_ts_bundle_with_globalthis_contract() {
        // Even a tiny TS bundle is recognized via the globalThis export marker.
        let minimal =
            "function init() { return { state: {}, effects: [] }; }\nglobalThis.init = init;";
        assert_eq!(ScriptLanguage::detect(minimal), ScriptLanguage::TypeScript);
    }

    #[test]
    fn detects_lua_via_multireturn_alone() {
        // The `}, {}` multireturn is the canonical Lua signature here.
        let minimal_lua = "function init(arg)\n  return { count = 0 }, {}\nend";
        assert_eq!(ScriptLanguage::detect(minimal_lua), ScriptLanguage::Lua);
    }

    #[test]
    fn ambiguous_content_is_unknown_not_typescript() {
        // `print(...)` is valid in BOTH Lua and JS — no contract markers →
        // Unknown. The badge shows NOTHING rather than guess. (This is the
        // old seed's `print(\"Hello, World!\")` filler — now honestly unknown.)
        assert_eq!(
            ScriptLanguage::detect("print('hello')"),
            ScriptLanguage::Unknown
        );
        assert_eq!(
            ScriptLanguage::detect("line one\nline two"),
            ScriptLanguage::Unknown
        );
        assert_eq!(ScriptLanguage::detect(""), ScriptLanguage::Unknown);
    }

    #[test]
    fn ts_bundle_with_incidental_end_in_string_is_not_mislabeled() {
        // A TS bundle that happens to contain the word "end" inside a string
        // must still detect as TypeScript (the globalThis + effects: markers
        // dominate, and "end" inside a string is not a line-start `end`).
        let ts = "const msg = \"the end\";
function init() { return { state: {}, effects: [] }; }
globalThis.init = init;";
        assert_eq!(ScriptLanguage::detect(ts), ScriptLanguage::TypeScript);
    }

    #[test]
    fn conflicting_signals_prefer_lua_to_avoid_false_typescript() {
        // When Lua and TS signals TIE, the honest verdict is Lua — a stale Lua
        // bundle must never be badged "TypeScript". Here `local ` (Lua) and
        // `const ` (TS) each score one hit → 1-1 tie → Lua wins.
        let mixed = "local x = 1\nconst y = 2";
        assert_eq!(ScriptLanguage::detect(mixed), ScriptLanguage::Lua);
    }

    #[test]
    fn as_str_round_trips_all_variants() {
        assert_eq!(ScriptLanguage::TypeScript.as_str(), "typescript");
        assert_eq!(ScriptLanguage::Lua.as_str(), "lua");
        assert_eq!(ScriptLanguage::Unknown.as_str(), "unknown");
    }
}
