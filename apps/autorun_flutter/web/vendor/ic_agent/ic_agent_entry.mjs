// R-3b WU-0 — vendored entry for `@dfinity/agent` (agent-js) on the browser.
//
// This file is the SINGLE source bundled into
// `web/vendor/ic_agent/ic_agent.bundle.js` via esbuild. Regenerate the bundle
// with (run in a temp npm project — NOT in the repo, to keep node_modules out):
//
//   npm install --no-save @dfinity/agent@3.4.3 @dfinity/candid@3.4.3 \
//       @dfinity/principal@3.4.3 @dfinity/identity@3.4.3 esbuild
//   esbuild ic_agent_entry.mjs --bundle --format=esm --platform=browser \
//       --minify --legal-comments=none \
//       --outfile=apps/autorun_flutter/web/vendor/ic_agent/ic_agent.bundle.js
//
// It mirrors the R-3a quickjs vendoring (`web/vendor/quickjs/quickjs_entry.mjs`):
// a small ESM entry that imports the agent-js exports we need and installs a
// plain global `globalThis.__icpCcAgent` that the Dart side
// (`lib/rust/web/ic_agent_engine.dart`) reads via `dart:js_interop`. There is
// NO WASM to inline here (agent-js is pure JS, unlike quickjs) — the bundle is
// plain JS.
//
// ## The CORS-evading design (plan §7.3.1)
// Browsers cannot call `ic0.app` directly: it sends no
// `Access-Control-Allow-Origin` for `/api/v2/*`. So the agent is created with
// `host: "https://ic0.app"` (so the MAINNET ROOT KEY is baked in +
// `verifyQuerySignatures` works as-is) but a CUSTOM `fetch` that rewrites the
// origin to the backend CORS byte-relay proxy (`/api/v1/ic`). agent-js builds
// URLs as `new URL('/api/v2/canister/.../query', 'https://ic0.app')` =
// `https://ic0.app/api/v2/...`; the custom fetch rewrites that to
// `${proxyOrigin}/api/v1/ic/api/v2/...` — same-origin to the browser, then the
// proxy relays bytes opaquely to ic0.app. The proxy never sees a private key.
//
// ## Why base64 transport
// All cross-boundary payloads are STRINGS (canisterId, methodName, argBase64,
// replyBase64) — no shared-JS-handle lifetime across calls. This mirrors the
// R-3a discipline ("all cross-boundary payloads are strings") and keeps the
// interop surface trivially VM-testable with a stubbed global.
import { HttpAgent } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";

globalThis.__icpCcAgent = {
  // Version of the vendored agent-js build, for diagnostics.
  version: "3.4.3",

  // Create an anonymous HttpAgent routed through the backend CORS proxy.
  // `proxyOrigin` is the backend origin, e.g. "http://127.0.0.1:58000".
  // Returns the agent (an opaque JS object — pass it to `query`).
  async createAnonymousAgent(proxyOrigin) {
    const IC_HOST = "https://ic0.app";
    const origin = String(proxyOrigin).replace(/\/$/, "");
    const agent = await HttpAgent.create({
      host: IC_HOST,
      // Secure default (plan §7.9): verify query signatures against subnet
      // node keys (fetched via read_state, also routed through the proxy).
      verifyQuerySignatures: true,
      // Custom fetch: rewrite the ic0.app origin to the proxy prefix so the
      // browser stays same-origin (no CORS). The proxy is protocol-blind.
      fetch: async (input, init) => {
        const url = new URL(typeof input === "string" ? input : input.url);
        const proxied = origin + "/api/v1/ic" + url.pathname + url.search;
        return globalThis.fetch(proxied, init);
      },
    });
    return agent;
  },

  // Perform an anonymous query.
  //   argBase64: base64 of the pre-encoded candid args ('' => empty args,
  //              encoded as IDL.encode([],[]) = 4449444c0000). This is the
  //              (γ) `base64:` raw-bytes args path (plan §7.5) — no did parser
  //              needed; callers pre-encode.
  // Returns:
  //   { ok: true, replyBase64 }            on success (status "replied")
  //   { ok: false, kind: "net", error }    on rejection / network error
  async query(agent, canisterId, methodName, argBase64) {
    try {
      const arg = argBase64 ? _fromB64(argBase64) : IDL.encode([], []);
      const res = await agent.query(String(canisterId), {
        methodName: String(methodName),
        arg,
      });
      if (res.status === "replied") {
        return { ok: true, replyBase64: _toB64(res.reply.arg) };
      }
      return {
        ok: false,
        kind: "net",
        error:
          "query rejected (code " +
          res.reject_code +
          "): " +
          (res.reject_message || ""),
      };
    } catch (e) {
      return { ok: false, kind: "net", error: _err(e) };
    }
  },

  // Decode the ICP ledger `symbol` reply to a JS string. The mainnet ledger's
  // `symbol` query returns `record { symbol: text }` (verified against the live
  // canister — the reply wire type is a record with a single `symbol` text
  // field, not bare `text`). Tries that shape first, then bare `text`, then
  // `vec text` (ICRC-1 `icrc1_symbol`), then `nat8` (decimals); on total
  // failure returns the raw hex so the harness can diagnose the wire type.
  // WU-2+ will replace this with typed decode via the fetched candid.
  decodeText(replyBase64) {
    const bytes = _fromB64(replyBase64);
    const hex = _toHex(bytes);
    // record { symbol: text } — the ICP ledger's actual `symbol` return shape.
    try {
      const [v] = IDL.decode([IDL.Record({ symbol: IDL.Text })], bytes);
      return v.symbol;
    } catch (_) {}
    try {
      const [v] = IDL.decode([IDL.Text], bytes);
      return v;
    } catch (_) {}
    try {
      const [v] = IDL.decode([IDL.Vec(IDL.Text)], bytes);
      return v.join("");
    } catch (_) {}
    try {
      const [v] = IDL.decode([IDL.Nat8], bytes);
      return String(v);
    } catch (_) {}
    return "hex:" + hex;
  },
};

// ── base64 + hex helpers (browser btoa/atob) ───────────────────────────────
function _toHex(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i++) {
    s += bytes[i].toString(16).padStart(2, "0");
  }
  return s;
}

// ── base64 helpers (browser btoa/atob) ─────────────────────────────────────
function _toB64(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}
function _fromB64(s) {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function _err(e) {
  return (e && (e.message || e.stack)) || String(e);
}
