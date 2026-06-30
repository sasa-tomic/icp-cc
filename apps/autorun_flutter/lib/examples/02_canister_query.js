// TypeScript/QuickJS bundle: query an ICP canister and format the result.
// Demonstrates the effect flow: update() emits an icp_call effect, the host
// executes the canister call, then delivers the result back via effect/result.
// Uses the host-provided icp_call / icp_format_icp / icp_message helpers.
"use strict";
(() => {
  var LEDGER = "ryjl3-tyaaa-aaaaa-aaaba-cai";

  function init() {
    return {
      state: { loading: false, balanceE8s: null, error: "" },
      effects: [],
    };
  }

  function view(state) {
    var children = [];
    children.push({
      type: "text",
      props: { text: "ICP Ledger balance lookup" },
    });
    children.push({
      type: "button",
      props: { label: state.loading ? "Loading..." : "Fetch balance", on_press: { type: "fetch" } },
    });

    if (state.error && state.error.length > 0) {
      children.push({ type: "text", props: { text: "Error: " + state.error } });
    }

    if (state.balanceE8s !== null && state.balanceE8s !== undefined) {
      // icp_format_icp is a host-provided helper (installed on globalThis).
      var formatted = icp_format_icp(state.balanceE8s, 8);
      children.push({
        type: "section",
        props: { title: "Balance", content: formatted + " ICP (" + state.balanceE8s + " e8s)" },
      });
    }

    return { type: "column", children: children };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";

    if (t === "fetch") {
      var effect = {
        kind: "icp_call",
        id: "balance",
        items: [
          {
            label: "balance",
            kind: 0,
            canister_id: LEDGER,
            method: "account_balance",
            args: '{"account":[]}',
          },
        ],
      };
      return { state: { ...state, loading: true, error: "" }, effects: [effect] };
    }

    if (t === "effect/result" && msg.id === "balance") {
      if (msg.ok) {
        var e8s = readE8s(msg.data);
        return {
          state: { loading: false, balanceE8s: e8s, error: "" },
          effects: [],
        };
      }
      return {
        state: { loading: false, balanceE8s: null, error: String(msg.error || "unknown error") },
        effects: [],
      };
    }

    return { state: state, effects: [] };
  }

  // Pull a numeric e8s value out of whatever shape the canister returned.
  function readE8s(data) {
    if (data === null || data === undefined) return 0;
    if (typeof data === "number") return data;
    if (typeof data === "object") {
      if (typeof data.e8s === "number") return data.e8s;
      if (Array.isArray(data)) return data.length;
    }
    return 0;
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
