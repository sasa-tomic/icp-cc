// Path-B TS/QuickJS app bundle: read the ICP token metadata from the LIVE
// mainnet ledger — a real public canister every user can reach out of the box
// (no local replica, no setup, no signing).
//
// Proves the dual-path model against a REAL canister (HUMAN_EXPECTATIONS §3)
// using read-only (anonymous) `icp_call` query effects. It is the always-working
// counterpart to the local-replica "On-chain Polls" developer example.
//
// The canister id + host flow in via arg.backend_id / arg.host (set by the
// runner from the descriptor defaults — the real mainnet ledger id + ic0.app).
// Captured JSON shapes the host delivers back as effect/result:
//   symbol()   → msg.data = {"ok":true,"result":{"symbol":"ICP"}}
//   name()     → msg.data = {"ok":true,"result":{"name":"Internet Computer"}}
//   decimals() → msg.data = {"ok":true,"result":{"decimals":8}}
"use strict";
(() => {
  function init(arg) {
    var a = arg || {};
    var state = {
      backend_id: a.backend_id || "",
      host: a.host || "",
      symbol: "",
      name: "",
      decimals: "",
      error: "",
      loading: false,
      loaded: false,
    };
    // Auto-load on mount: emit the three read-only queries so the example opens
    // to real data instead of an empty screen + a forced manual Refresh.
    return { state: state, effects: refreshEffects(state) };
  }

  function view(state) {
    var kids = [];
    kids.push({
      type: "text",
      props: { text: "ICP Ledger — live on mainnet (read-only)" },
    });
    kids.push({
      type: "button",
      props: {
        label: state.loading ? "Querying mainnet…" : "Refresh from ledger",
        on_press: { type: "refresh" },
      },
    });
    if (state.error && state.error.length > 0) {
      kids.push({ type: "text", props: { text: "Error: " + state.error } });
    }
    if (state.loaded) {
      kids.push({
        type: "section",
        props: { title: "Token metadata" },
        children: [
          { type: "text", props: { text: "Symbol: " + (state.symbol || "?") } },
          { type: "text", props: { text: "Name: " + (state.name || "?") } },
          {
            type: "text",
            props: { text: "Decimals: " + (state.decimals || "?") },
          },
        ],
      });
    }
    return { type: "column", children: kids };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";

    if (t === "refresh") {
      return {
        state: setStateShallow(state, { loading: true, error: "" }),
        effects: refreshEffects(state),
      };
    }

    if (t === "effect/result") {
      return handleResult(msg, state);
    }

    return { state: state, effects: [] };
  }

  // A single read-only icp_call effect with flat fields the host reads.
  function callEffect(id, method, state) {
    return {
      kind: "icp_call",
      id: id,
      mode: 0, // query
      canister_id: state.backend_id,
      method: method,
      args: "()",
      host: state.host,
      authenticated: false, // read-only — no signing, works without a profile
    };
  }

  function refreshEffects(state) {
    return [
      callEffect("symbol", "symbol", state),
      callEffect("name", "name", state),
      callEffect("decimals", "decimals", state),
    ];
  }

  function handleResult(msg, state) {
    var id = msg.id || "";
    var parsed = readEffect(msg);
    if (!parsed.ok) {
      return setState(state, { loading: false, error: id + ": " + parsed.error });
    }
    var value = parsed.value;
    // Each method returns a one-field record, but be defensive: a bare scalar
    // value (text/number) is tolerated too.
    var patch = { loaded: true };
    if (id === "symbol") {
      patch.symbol = readField(value, "symbol");
    }
    if (id === "name") {
      patch.name = readField(value, "name");
    }
    if (id === "decimals") {
      patch.decimals = readField(value, "decimals");
    }
    return setState(state, patch);
  }

  // Pull a field out of the decoded result: `value.field` for a record, else
  // the bare value (some interfaces return text/nat directly). Coerced to text.
  function readField(value, field) {
    if (value && typeof value === "object") {
      var v = value[field];
      return v != null ? String(v) : "";
    }
    return value != null ? String(value) : "";
  }

  // Normalize a delivered effect/result into {ok, value|error}. Mirrors the
  // 06_icp_poll bundle's reader: the host wraps host-level failures as
  // {ok:false,error}, success as {ok:true,data}; the bridge further wraps
  // payloads as {ok:true,result} / {ok:false,error}.
  function readEffect(msg) {
    if (msg.ok === false) {
      return { ok: false, error: String(msg.error || "effect failed") };
    }
    var data = msg.data;
    if (data && typeof data === "object" && data.ok === false) {
      return { ok: false, error: String(data.error || "canister call failed") };
    }
    return { ok: true, value: data ? data.result : undefined };
  }

  function setState(state, patch) {
    return { state: Object.assign({}, state, patch), effects: [] };
  }

  // Like setState but for update() branches that return their own effects.
  function setStateShallow(state, patch) {
    return Object.assign({}, state, patch);
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
