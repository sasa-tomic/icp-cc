// R-3b WU-0/WU-2/WU-3/WU-4 — vendored entry for `@dfinity/agent` (agent-js).
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
import { HttpAgent, fetchCandid as agentFetchCandid, polling } from "@dfinity/agent";
import { IDL } from "@dfinity/candid";
import { Ed25519KeyIdentity } from "@dfinity/identity";
import { Principal } from "@dfinity/principal";

// The IC mainnet host. The agent THINKS it's talking to ic0.app (so the mainnet
// root key is baked in + verifyQuerySignatures works), but a custom `fetch`
// rewrites every request to the CORS proxy (single-upstream, plan §7.8.5).
const IC_HOST = "https://ic0.app";

/// Build a custom fetch that rewrites ic0.app URLs to the CORS proxy prefix.
/// Both anonymous + authenticated agents use this — the proxy is protocol-blind
/// (it never sees a private key; the auth is the agent-js-signed CBOR body).
function _proxyFetch(origin) {
  return async (input, init) => {
    const url = new URL(typeof input === "string" ? input : input.url);
    const proxied = origin + "/api/v1/ic" + url.pathname + url.search;
    return globalThis.fetch(proxied, init);
  };
}

globalThis.__icpCcAgent = {
  // Version of the vendored agent-js build, for diagnostics.
  version: "3.4.3",

  // Validate a canister ID (principal text). Uses agent-js's own
  // `Principal.fromText` — the SAME validation native does
  // (`Principal::from_text`, `canister_client.rs:578`). Returns true/false so
  // the Dart side can classify the error as `invalid_canister_id` (parity with
  // native's `CanisterClientError::InvalidCanisterId`) BEFORE any network call.
  validateCanisterId(canisterId) {
    try {
      Principal.fromText(String(canisterId));
      return true;
    } catch (_) {
      return false;
    }
  },

  // Create an anonymous HttpAgent routed through the backend CORS proxy.
  // `proxyOrigin` is the backend origin, e.g. "http://127.0.0.1:58000".
  // Returns the agent (an opaque JS object — pass it to `query`/`update`/
  // `fetchCandid`).
  async createAnonymousAgent(proxyOrigin) {
    const origin = String(proxyOrigin).replace(/\/$/, "");
    const agent = await HttpAgent.create({
      host: IC_HOST,
      // Secure default (plan §7.9): verify query signatures against subnet
      // node keys (fetched via read_state, also routed through the proxy).
      verifyQuerySignatures: true,
      fetch: _proxyFetch(origin),
    });
    return agent;
  },

  // R-3b WU-4 — create an authenticated HttpAgent with an Ed25519 identity.
  // `privateKeyB64` is the base64-encoded 32-byte Ed25519 seed (the SAME bytes
  // R-2 derives on Web — `Ed25519KeyIdentity.fromSecretKey(seed)` is byte-parity
  // with native `BasicIdentity::from_raw_key`, `canister_client.rs:674`).
  // The agent signs update calls (submit) + query calls with this identity.
  async createAuthenticatedAgent(proxyOrigin, privateKeyB64) {
    const origin = String(proxyOrigin).replace(/\/$/, "");
    const seed = _fromB64(privateKeyB64);
    const identity = Ed25519KeyIdentity.fromSecretKey(seed);
    const agent = await HttpAgent.create({
      host: IC_HOST,
      identity,
      verifyQuerySignatures: true,
      fetch: _proxyFetch(origin),
    });
    return agent;
  },

  // R-3b WU-2 — fetch a canister's `.did` interface. Delegates to agent-js's
  // `fetchCandid(canisterId, agent)` (`fetch_candid.ts`): a certified
  // `read_state` for the `candid:service` metadata, with the
  // `__get_candid_interface_tmp_hack` query fallback. EXACT parity with native
  // `fetch_candid` (`canister_client.rs:529-567`) — both consult the same
  // certified metadata path against the SAME mainnet root key.
  //
  // Returns:
  //   string  — the raw candid `.did` text (the `candid:service` metadata).
  //   null    — the canister exposes no candid interface (neither metadata nor
  //             the tmp hack). The Dart caller maps `null` to a friendly
  //             "could not load interface" message (parity with native's
  //             `null_c_string` on error).
  // Throws on network/proxy failure (the Dart access module maps that to `null`
  // too, with a loud log).
  async fetchCandid(agent, canisterId) {
    try {
      const did = await agentFetchCandid(String(canisterId), agent);
      // agent-js returns `undefined` (not a string) if both metadata + tmp hack
      // miss; normalise to `null` for a clean cross-boundary contract.
      return typeof did === "string" ? did : null;
    } catch (e) {
      // Re-throw with a clean message — the Dart side maps any throw to `null`
      // (parity with native) but logs the cause loudly.
      throw new Error("agent-js fetchCandid failed: " + _err(e));
    }
  },

  // Perform an anonymous query (mode 0/2: query/composite_query).
  //   argBase64: base64 of the pre-encoded candid args ('' => empty args,
  //              encoded as IDL.encode([],[]) = 4449444c0000).
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

  // R-3b WU-3 — perform an update call (mode 1: update). Submits the signed
  // call then polls read_state for the request status (certified reply).
  // Mirrors native `agent.update().call_and_wait()` (`canister_client.rs:615`).
  //   argBase64: base64 of the pre-encoded candid args ('' => empty args).
  // Returns:
  //   { ok: true, replyBase64 }            on success (request "replied")
  //   { ok: false, kind: "net", error }    on rejection / network error
  async update(agent, canisterId, methodName, argBase64) {
    try {
      const arg = argBase64 ? _fromB64(argBase64) : IDL.encode([], []);
      const cid = Principal.fromText(String(canisterId));
      const { requestId } = await agent.call(cid, {
        methodName: String(methodName),
        arg,
        effectiveCanisterId: cid,
      });
      const { reply } = await polling.pollForResponse(agent, cid, requestId);
      return { ok: true, replyBase64: _toB64(reply) };
    } catch (e) {
      return { ok: false, kind: "net", error: _err(e) };
    }
  },

  // R-3b WU-3 — encode JSON args to candid bytes using type descriptors from
  // the pure-Dart candid parser (`methodTypeDescriptors`). This is the
  // `build_args_from_json` parity path (`canister_client.rs:432-499`): the Dart
  // side fetches the `.did`, parses it to type descriptors (resolving aliases),
  // and passes them here. The JS side converts descriptors → agent-js IDL type
  // objects + converts JSON values → agent-js values, then `IDL.encode`.
  //
  //   argDescsJson: JSON string `{"args":[<desc>...],"rets":[...]}` (only
  //                 `args` is used here; `rets` is for decode).
  //   jsonArgsStr:  the raw JSON args string the caller passed (e.g.
  //                 `{"symbol":"ICP"}` or `42` or `"hello"`). Parsed as a
  //                 single JSON value; if the method has multiple args, it
  //                 must be a JSON array.
  // Returns: base64 of the encoded candid args bytes.
  // Throws on any encode failure (the Dart side maps to a `candid` error).
  encodeArgsWithTypes(argDescsJson, jsonArgsStr) {
    const parsed = JSON.parse(argDescsJson);
    const argDescs = parsed.args || [];
    const jsonVal = JSON.parse(jsonArgsStr);
    // Mirror native `build_args_from_json` arity handling:
    //  - 0 args: empty (IDL.encode([], []))
    //  - 1 arg:  the JSON value IS the single arg (unwrapped)
    //  - >1 args: the JSON value must be an array; each element is one arg
    let values;
    if (argDescs.length === 0) {
      values = [];
    } else if (argDescs.length === 1) {
      values = [_toIdlValue(jsonVal, argDescs[0])];
    } else {
      if (!Array.isArray(jsonVal)) {
        throw new Error(
          "expected JSON array for " + argDescs.length + " args, got " + typeof jsonVal
        );
      }
      if (jsonVal.length !== argDescs.length) {
        throw new Error(
          "args arity mismatch: expected " + argDescs.length + ", got " + jsonVal.length
        );
      }
      values = jsonVal.map((v, i) => _toIdlValue(v, argDescs[i]));
    }
    const idlTypes = argDescs.map(_toIdl);
    const bytes = IDL.encode(idlTypes, values);
    return _toB64(bytes);
  },

  // R-3b WU-3 — decode a candid reply to JSON using type descriptors from the
  // pure-Dart candid parser. This is the `try_decode_with_types` parity path
  // (`canister_client.rs:135-159`): fetch `.did`, parse ret types → descriptors,
  // decode the reply with those types, then normalize to the native
  // `idl_value_to_json` / `idl_args_to_json` JSON shape.
  //
  //   retDescsJson: JSON string `{"args":[...],"rets":[<desc>...]}` (only
  //                 `rets` is used here).
  //   replyBase64:  base64 of the raw candid reply bytes.
  // Returns: JSON string of the decoded reply (the `result` value in the
  // native `{"ok":true,"result":<json>}` envelope). Mirrors native
  // `idl_args_to_json`:
  //   - 0 rets → null
  //   - 1 ret  → the unwrapped value
  //   - >1 rets → JSON array
  // And `idl_value_to_json` per-value:
  //   - Nat/Int/Nat64/Int64 → string (avoids JSON precision loss)
  //   - Nat8..32, Int8..32, Float → number
  //   - Principal → text string
  //   - Opt → unwrapped (None → null, Some(v) → v)
  //   - Blob (vec nat8) → "base64:..." string
  //   - Variant → { caseName: value }
  decodeReplyWithTypes(retDescsJson, replyBase64) {
    const parsed = JSON.parse(retDescsJson);
    const retDescs = parsed.rets || [];
    const bytes = _fromB64(replyBase64);
    const idlTypes = retDescs.map(_toIdl);
    const values = IDL.decode(idlTypes, bytes);
    return JSON.stringify(_normalizeArgs(values, retDescs));
  },

  // Decode the ICP ledger `symbol` reply to a JS string (WU-0 PoC helper).
  // The mainnet ledger's `symbol` query returns `record { symbol: text }`.
  // Tries that shape first, then bare `text`, then `vec text` (ICRC-1
  // `icrc1_symbol`), then `nat8` (decimals); on total failure returns the raw
  // hex so the harness can diagnose the wire type. WU-3's `decodeReplyWithTypes`
  // supersedes this for general typed decode; this stays for the probe.
  decodeText(replyBase64) {
    const bytes = _fromB64(replyBase64);
    const hex = _toHex(bytes);
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

// ── Type descriptor → agent-js IDL type object converter ─────────────────────
// The Dart-side `methodTypeDescriptors` emits a JSON type descriptor; this
// converts it to the agent-js IDL constructor calls `IDL.encode`/`IDL.decode`
// require. Every type a method arg/ret can be is covered.
function _toIdl(desc) {
  switch (desc.t) {
    case "null": return IDL.Null;
    case "reserved": return IDL.Reserved;
    case "empty": return IDL.Empty;
    case "bool": return IDL.Bool;
    case "text": return IDL.Text;
    case "nat": return IDL.Nat;
    case "int": return IDL.Int;
    case "nat8": return IDL.Nat8;
    case "nat16": return IDL.Nat16;
    case "nat32": return IDL.Nat32;
    case "nat64": return IDL.Nat64;
    case "int8": return IDL.Int8;
    case "int16": return IDL.Int16;
    case "int32": return IDL.Int32;
    case "int64": return IDL.Int64;
    case "float32": return IDL.Float32;
    case "float64": return IDL.Float64;
    case "principal": return IDL.Principal;
    case "opt": return IDL.Opt(_toIdl(desc.inner));
    case "vec": return IDL.Vec(_toIdl(desc.inner));
    case "record": {
      const fields = {};
      for (const f of desc.fields) {
        const key = f.n !== undefined ? f.n : f.i;
        fields[key] = _toIdl(f.t);
      }
      return IDL.Record(fields);
    }
    case "variant": {
      const fields = {};
      for (const f of desc.fields) {
        const key = f.n !== undefined ? f.n : f.i;
        fields[key] = _toIdl(f.t);
      }
      return IDL.Variant(fields);
    }
    case "func": {
      const args = (desc.args || []).map(_toIdl);
      const rets = (desc.rets || []).map(_toIdl);
      const modes = (desc.modes || []).map((m) => {
        if (m === "query") return ["query"];
        if (m === "oneway") return ["oneway"];
        if (m === "composite_query") return ["composite_query"];
        return [];
      }).flat();
      return IDL.Func(args, rets, modes);
    }
    case "service": {
      const fields = {};
      for (const m of (desc.methods || [])) {
        fields[m.n] = _toIdl(m.t);
      }
      return IDL.Service(fields);
    }
    default:
      throw new Error("unknown type descriptor kind: " + desc.t);
  }
}

// ── JSON value → agent-js value converter (for IDL.encode) ──────────────────
// Mirrors native `json_to_idl_value` (`canister_client.rs:203-430`): converts
// the caller's JSON value to the shape agent-js's IDL.encode expects for each
// candid type (BigInt for big ints, Principal objects for principals, []/[v]
// for opt, etc.).
function _toIdlValue(jsonVal, desc) {
  switch (desc.t) {
    case "nat":
    case "int":
    case "nat64":
    case "int64":
      // agent-js expects BigInt for big ints. JSON numbers → BigInt; JSON
      // strings (native accepts string-encoded big ints) → BigInt.
      return BigInt(jsonVal);
    case "nat8": case "nat16": case "nat32":
    case "int8": case "int16": case "int32":
    case "float32": case "float64":
    case "bool":
    case "text":
      return jsonVal;
    case "null":
    case "reserved":
    case "empty":
      return null;
    case "principal":
      // JSON gives a text principal → agent-js expects a Principal object.
      return Principal.fromText(String(jsonVal));
    case "opt":
      // Native: null → None; else → Some(v). agent-js: None = [], Some = [v].
      if (jsonVal === null || jsonVal === undefined) return [];
      return [_toIdlValue(jsonVal, desc.inner)];
    case "vec":
      if (!Array.isArray(jsonVal)) {
        throw new Error("expected JSON array for vec, got " + typeof jsonVal);
      }
      return jsonVal.map((v) => _toIdlValue(v, desc.inner));
    case "record": {
      const obj = {};
      for (const f of desc.fields) {
        const key = f.n !== undefined ? f.n : f.i;
        const jsonKey = String(key);
        if (jsonVal[jsonKey] !== undefined && jsonVal[jsonKey] !== null) {
          obj[key] = _toIdlValue(jsonVal[jsonKey], f.t);
        } else if (f.t.t === "opt") {
          // Missing opt field → None (parity with native's opt-defaulting,
          // `canister_client.rs:333-337`).
          obj[key] = [];
        } else if (f.t.t === "null" || f.t.t === "reserved") {
          obj[key] = null;
        } else {
          throw new Error("missing record field: " + jsonKey);
        }
      }
      return obj;
    }
    case "variant": {
      // Native: variant as { "Case": value }. Exactly one case key.
      if (typeof jsonVal !== "object" || jsonVal === null) {
        throw new Error("expected object for variant, got " + typeof jsonVal);
      }
      const keys = Object.keys(jsonVal);
      if (keys.length !== 1) {
        throw new Error("variant expects exactly one case, got " + keys.length);
      }
      const caseKey = keys[0];
      const field = desc.fields.find(
        (f) => (f.n !== undefined ? f.n : String(f.i)) === caseKey
      );
      if (!field) {
        throw new Error("unknown variant case: " + caseKey);
      }
      const result = {};
      if (field.t.t === "null" || field.t.t === "reserved" || field.t.t === "empty") {
        result[caseKey] = null;
      } else {
        result[caseKey] = _toIdlValue(jsonVal[caseKey], field.t);
      }
      return result;
    }
    case "func":
    case "service":
      throw new Error("func/service in arg position not supported");
    default:
      throw new Error("unknown type descriptor for encode: " + desc.t);
  }
}

// ── agent-js decoded value → native JSON shape (for IDL.decode) ──────────────
// Mirrors native `idl_value_to_json` (`canister_client.rs:71-124`): normalizes
// agent-js's decoded values to the JSON shape native produces (BigInt → string,
// Principal → text, Opt unwrapped, Blob → "base64:...", etc.).
function _normalizeValue(value, desc) {
  switch (desc.t) {
    case "null":
    case "reserved":
    case "empty":
      return null;
    case "nat":
    case "int":
    case "nat64":
    case "int64":
      // agent-js returns BigInt → string (parity with native's to_string, avoids
      // JSON number precision loss).
      return value === null ? null : value.toString();
    case "nat8": case "nat16": case "nat32":
    case "int8": case "int16": case "int32":
    case "float32": case "float64":
    case "bool":
      return value;
    case "text":
      return value;
    case "principal":
      // agent-js returns a Principal object → toText().
      return value && typeof value.toText === "function" ? value.toText() : String(value);
    case "service":
      return value && typeof value.toText === "function" ? value.toText() : String(value);
    case "opt":
      // agent-js: None → [], Some(v) → [v]. Native: None → null, Some(v) → v.
      if (!Array.isArray(value) || value.length === 0) return null;
      return _normalizeValue(value[0], desc.inner);
    case "vec":
      // blob (vec nat8): native returns "base64:...".
      if (desc.inner.t === "nat8") {
        const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
        return "base64:" + _toB64(bytes);
      }
      return value.map((v) => _normalizeValue(v, desc.inner));
    case "record": {
      const obj = {};
      for (const f of desc.fields) {
        const key = f.n !== undefined ? f.n : f.i;
        obj[String(key)] = _normalizeValue(value[key], f.t);
      }
      return obj;
    }
    case "variant": {
      // agent-js returns { caseName: value }.
      const keys = Object.keys(value);
      if (keys.length !== 1) return value;
      const caseKey = keys[0];
      const field = desc.fields.find(
        (f) => (f.n !== undefined ? f.n : String(f.i)) === caseKey
      );
      const caseType = field ? field.t : { t: "null" };
      const result = {};
      result[caseKey] = _normalizeValue(value[caseKey], caseType);
      return result;
    }
    case "func":
      // agent-js returns [principal, method] → native {principal, method}.
      if (Array.isArray(value) && value.length === 2) {
        return {
          principal: value[0] && typeof value[0].toText === "function"
            ? value[0].toText() : String(value[0]),
          method: String(value[1]),
        };
      }
      return value;
    default:
      return value;
  }
}

// Mirrors native `idl_args_to_json` (`canister_client.rs:126-133`):
// 0 args → null; 1 arg → unwrapped; >1 args → array.
function _normalizeArgs(values, retDescs) {
  if (values.length === 0) return null;
  if (values.length === 1) return _normalizeValue(values[0], retDescs[0]);
  return values.map((v, i) => _normalizeValue(v, retDescs[i]));
}

// ── base64 + hex helpers (browser btoa/atob) ───────────────────────────────
function _toHex(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i++) {
    s += bytes[i].toString(16).padStart(2, "0");
  }
  return s;
}

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
