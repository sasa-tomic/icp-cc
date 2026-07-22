// Path-B TS/QuickJS app bundle: browse LIVE SNS DAO governance proposals.
//
// A headliner demo of what icp-cc can do — same UI shape as 08_nns_proposals
// but pointed at any SNS DAO governance canister. Defaults to OpenChat SNS
// (verified live 2026-07-21). The user can paste a different SNS governance
// canister id to switch DAOs in-flight. Demonstrates the theme knob added in
// Unit 2: the bundle paints its own page/card/accent colours so each DAO can
// ship its own branded experience.
//
// Canister id + host flow in via arg.backend_id / arg.host (the descriptor
// defaults — OpenChat SNS governance 2jvtu-yqaaa-aaaaq-aaama-cai + ic0.app).
// The user can override at runtime via the text field.
//
// Candid args (verified live via dfx against 2jvtu-yqaaa-aaaaq-aaama-cai;
// every field is MANDATORY):
//   list_proposals: (record {
//     limit = N : nat32;
//     exclude_type = vec {};              ← SNS uses 'exclude_TYPE' (vec nat64),
//                                          NOT NNS's 'exclude_topic' (int32)
//     include_reward_status = vec {};
//     include_status = vec {};            ← int32 status enum, same values as NNS
//   })
//
// NOTE: SNS has no `omit_large_fields` (always returns full summaries) and no
// typed `include_topics` selector in the common path; we leave both off.
//
// Decoded JSON shape (Rust bridge: IDLArgs::from_bytes + idl_args_to_json):
//   { proposals: [
//     { id: [{ id: 2313 }],               ← opt record → 1-elem array
//       topic: [{ DappCanisterManagement: null }],   ← opt Topic variant
//       proposal: [{ title, summary, url, action: [{...}] }],
//       latest_tally: [{ yes, no, total, timestamp_seconds }],
//       proposer: [{ id: "..." }],        ← id is a blob here (vs NNS nat64)
//       decided_timestamp_seconds: 1783696546,        ← bare nat64
//       executed_timestamp_seconds: 1783696549,       ← bare nat64
//       failed_timestamp_seconds: 0,
//       wait_for_quiet_state: [{ current_deadline_timestamp_seconds: ... }],
//       action: 10000,                    ← bare nat64 action id
//       ... },
//   ] }
//
// STATUS IS NOT A FIELD on SNS ProposalData — it must be INFERRED from
// timestamps (see inferStatus). deadline_timestamp_seconds is also absent;
// use wait_for_quiet_state.current_deadline_timestamp_seconds for OPEN ones.
//
// opt T becomes [T] (empty array when null). unwrapOpt() normalises.
"use strict";
(() => {
  // ───────────────────────── Constants (single source) ────────────────────
  var PAGE_SIZE = 10;

  // SNS GovernanceProposalStatus enum (sns-governance Rust canister). Same
  // integers as NNS — "Open"=1 etc. — but it is NOT a field on ProposalData;
  // we infer it client-side from the timestamp fields (see inferStatus).
  var STATUS = {
    0: "Unknown",
    1: "Open",
    2: "Rejected",
    3: "Adopted",
    4: "Executed",
    5: "Failed",
  };

  // Status filter values sent as include_status = vec { int }; "all" sends an
  // empty vec (server returns every status).
  var STATUS_FILTER_VALUE = {
    all: "",
    open: "1",
    rejected: "2",
    adopted: "3",
    executed: "4",
  };

  // Per-DAO branded theme (OpenChat-ish indigo). All five keys are hex
  // strings; the host's _wrapWithTheme turns them into a ColoredBox +
  // Theme() override. A bundle that omits the theme prop renders with the
  // app's default colours.
  var THEME = {
    background: "#0e0b1f", // deep indigo page
    card_background: "#1b1538", // panel
    accent: "#7c5cff", // OpenChat-ish purple
    text: "#f2eefb", // near-white
    text_muted: "#a89fd6", // dimmed lavender
  };

  // ───────────────────────── Lifecycle ────────────────────────────────────
  function init(arg) {
    var a = arg || {};
    var state = {
      backend_id: a.backend_id || "",
      host: a.host || "",
      status_filter: "open",
      page: 0,
      page_size: PAGE_SIZE,
      cursor_history: [],
      loading: false,
      loaded: false,
      error: "",
      proposals: [],
      has_more: false,
    };
    // AUTO-LOAD on mount so the tab opens to real data (UXR-6) — but only if
    // we have a canister to query. If the descriptor is blank, the UI shows
    // the canister-id prompt and waits for the user.
    var effects = state.backend_id ? [listProposalsEffect(state)] : [];
    return { state: state, effects: effects };
  }

  function view(state) {
    var kids = [];

    kids.push({
      type: "text",
      props: { text: "SNS DAO Proposals — live on mainnet (read-only)" },
    });

    // Canister-id field: user can paste any SNS governance canister id. This
    // is the SNS bundle's distinctive feature vs. 08_nns_proposals.
    kids.push({
      type: "text_field",
      props: {
        label: "SNS governance canister id",
        value: state.backend_id,
        placeholder: "e.g. 2jvtu-yqaaa-aaaaq-aaama-cai (OpenChat)",
        enabled: !state.loading,
        on_submit: { type: "set_canister" },
      },
    });

    // Filter row: status select + Refresh.
    kids.push({
      type: "row",
      children: [
        {
          type: "select",
          props: {
            label: "Status",
            value: state.status_filter,
            options: Object.keys(STATUS_FILTER_VALUE).map(function (k) {
              return {
                value: k,
                label: k.charAt(0).toUpperCase() + k.slice(1),
              };
            }),
            on_change: { type: "set_status" },
          },
        },
        {
          type: "button",
          props: {
            label: state.loading ? "Querying mainnet…" : "Refresh",
            on_press: { type: "refresh" },
            disabled: state.loading || !state.backend_id,
          },
        },
      ],
    });

    if (state.error && state.error.length > 0) {
      kids.push({ type: "text", props: { text: "Error: " + state.error } });
    }

    if (!state.backend_id) {
      kids.push({
        type: "text",
        props: {
          text:
            "Paste an SNS governance canister id above and press Enter to " +
            "load its proposals. (Default is OpenChat — clear the field to " +
            "try another DAO.)",
        },
      });
    } else if (state.loading && state.proposals.length === 0) {
      kids.push({ type: "text", props: { text: "Loading proposals…" } });
    } else if (state.loaded && state.proposals.length === 0) {
      kids.push({
        type: "text",
        props: {
          text:
            "No proposals match this filter. " +
            '(SNS DAOs have quiet periods — try "all" to see recent history.)',
        },
      });
    } else {
      for (var i = 0; i < state.proposals.length; i++) {
        kids.push(proposalCard(state.proposals[i]));
      }
    }

    if (state.proposals.length > 0) {
      kids.push({
        type: "row",
        children: [
          {
            type: "button",
            props: {
              label: "‹ Prev",
              on_press: { type: "page", delta: -1 },
              disabled: state.page === 0 || state.loading,
            },
          },
          { type: "text", props: { text: "Page " + (state.page + 1) } },
          {
            type: "button",
            props: {
              label: "Next ›",
              on_press: { type: "page", delta: 1 },
              disabled: !state.has_more || state.loading,
            },
          },
        ],
      });
    }

    return { type: "column", theme: THEME, children: kids };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";

    if (t === "refresh") {
      if (!state.backend_id) return { state: state, effects: [] };
      var refreshed = setStateShallow(
          state, {loading: true, error: "", page: 0, cursor_history: []});
      return { state: refreshed, effects: [listProposalsEffect(refreshed, 0)] };
    }

    if (t === "set_status") {
      var next = Object.assign({}, state, {
        status_filter: String(msg.value || "all"),
        loading: true,
        error: "",
        page: 0,
        cursor_history: [],
      });
      return { state: next, effects: [listProposalsEffect(next, 0)] };
    }

    if (t === "set_canister") {
      var raw = String(msg.value || "").trim();
      if (raw.length === 0) {
        return setState(state, {
          backend_id: "",
          proposals: [],
          loaded: false,
          error: "",
          cursor_history: [],
        });
      }
      var swapped = Object.assign({}, state, {
        backend_id: raw,
        loading: true,
        error: "",
        page: 0,
        proposals: [],
        loaded: false,
        cursor_history: [],
      });
      return { state: swapped, effects: [listProposalsEffect(swapped, 0)] };
    }

    if (t === "page") {
      var delta = Number(msg.delta || 0);
      var targetPage = Math.max(0, state.page + delta);
      if (targetPage === state.page) {
        return { state: state, effects: [] };
      }
      var paged = Object.assign({}, state, {
        page: targetPage,
        loading: true,
        error: "",
      });
      return { state: paged, effects: [listProposalsEffect(paged, targetPage)] };
    }

    if (t === "effect/result") {
      return handleResult(msg, state);
    }

    return { state: state, effects: [] };
  }

  // ───────────────────────── Effects ──────────────────────────────────────
  function listProposalsEffect(state, pageOverride) {
    var page = pageOverride != null ? pageOverride : state.page;
    var statusVec = buildStatusVec(state.status_filter);
    var history = state.cursor_history || [];
    var cursor = history[page] != null ? history[page] : null;
    var beforeProposal = cursor != null
        ? "before_proposal = opt record { id = " + cursor + " : nat64 }"
        : "before_proposal = null";
    // SNS args — verified live. NOTE the 'exclude_TYPE' (not 'exclude_topic')
    // and NO omit_large_fields. See header docstring.
    var args =
      "(record { limit = " +
      state.page_size +
      " : nat32; " +
      beforeProposal +
      "; exclude_type = vec {}; include_reward_status = vec {}; include_status = " +
      statusVec +
      "; })";
    return {
      kind: "icp_call",
      id: "list_proposals",
      mode: 0,
      canister_id: state.backend_id,
      method: "list_proposals",
      args: args,
      host: state.host,
      authenticated: false,
    };
  }

  function buildStatusVec(filterKey) {
    var v = STATUS_FILTER_VALUE[filterKey];
    if (!v || v.length === 0) {
      return "vec {}";
    }
    return "vec { " + v + " : int32 }";
  }

  function handleResult(msg, state) {
    var parsed = readEffect(msg);
    if (!parsed.ok) {
      return setState(state, {
        loading: false,
        error: "list_proposals: " + parsed.error,
      });
    }
    var envelope = parsed.value || {};
    var arr = envelope.proposals;
    if (!Array.isArray(arr)) {
      return setState(state, {
        loading: false,
        error: "list_proposals: malformed reply (proposals not an array)",
      });
    }
    var decoded = arr.map(decodeProposal);
    var newHistory = (state.cursor_history || []).slice();
    if (arr.length >= state.page_size) {
      var minId = null;
      for (var i = 0; i < decoded.length; i++) {
        var pid = decoded[i].id;
        if (pid && (minId === null || pid < minId)) minId = pid;
      }
      if (minId !== null) {
        newHistory[(state.page || 0) + 1] = minId;
      }
    }
    return setState(state, {
      loading: false,
      loaded: true,
      error: "",
      proposals: decoded,
      has_more: arr.length >= state.page_size,
      cursor_history: newHistory,
    });
  }

  // ───────────────────────── Decoding helpers ─────────────────────────────
  function unwrapOpt(v, fallback) {
    if (Array.isArray(v)) {
      return v.length > 0 ? v[0] : (fallback == null ? null : fallback);
    }
    return v == null ? (fallback == null ? null : fallback) : v;
  }

  function unwrapOptInt(v, fallback) {
    var x = unwrapOpt(v, fallback);
    if (x == null) return fallback == null ? 0 : fallback;
    return typeof x === "number" ? x : Number(x) || (fallback == null ? 0 : fallback);
  }

  // Map a raw SNS ProposalData record → flat display record. The contract
  // differs from NNS in three painful ways:
  //   1. NO `status` field — INFER it from the timestamp fields.
  //   2. NO `deadline_timestamp_seconds` — read wait_for_quiet_state instead.
  //   3. `topic` is an opt VARIANT, decoded by the bridge as
  //      `{ VariantTag: null }`. Extract the tag key as the human label.
  function decodeProposal(raw) {
    var idNode = unwrapOpt(raw.id, {});
    var proposalNode = unwrapOpt(raw.proposal, {});
    var tallyNode = unwrapOpt(raw.latest_tally, {});
    var wfq = unwrapOpt(raw.wait_for_quiet_state, {});
    return {
      id: unwrapOptInt(idNode.id, 0),
      status: inferStatus(raw),
      topic: topicLabel(raw.topic),
      title: unwrapOpt(proposalNode.title, "(untitled proposal)"),
      summary: unwrapOpt(proposalNode.summary, ""),
      url: unwrapOpt(proposalNode.url, ""),
      deadline: unwrapOptInt(wfq.current_deadline_timestamp_seconds, 0),
      yes: unwrapOptInt(tallyNode.yes, 0),
      no: unwrapOptInt(tallyNode.no, 0),
      total: unwrapOptInt(tallyNode.total, 0),
    };
  }

  // SNS status inference (see header). Executed > Failed > Decided > Open.
  // When decided, distinguish adopted vs rejected by tally (yes >= no → Adopted).
  function inferStatus(raw) {
    if (unwrapOptInt(raw.executed_timestamp_seconds, 0) !== 0) return STATUS[4];
    if (unwrapOptInt(raw.failed_timestamp_seconds, 0) !== 0) return STATUS[5];
    if (unwrapOptInt(raw.decided_timestamp_seconds, 0) !== 0) {
      var tallyNode = unwrapOpt(raw.latest_tally, {});
      var yes = unwrapOptInt(tallyNode.yes, 0);
      var no = unwrapOptInt(tallyNode.no, 0);
      return yes >= no ? STATUS[3] : STATUS[2];
    }
    return STATUS[1]; // Open
  }

  // SNS Topic is a variant; the JSON bridge decodes variants as
  // `{ TagName: null }`. Return the tag name (or "Unknown" if missing).
  function topicLabel(t) {
    var node = unwrapOpt(t, null);
    if (node && typeof node === "object") {
      var keys = Object.keys(node);
      if (keys.length > 0) return keys[0];
    }
    return "Unknown";
  }

  // ───────────────────────── View helpers ─────────────────────────────────
  function proposalCard(p) {
    var tallyTotal = p.total || (p.yes + p.no);
    var yesPct = tallyTotal > 0 ? Math.round((p.yes / tallyTotal) * 100) : 0;
    var noPct = tallyTotal > 0 ? Math.round((p.no / tallyTotal) * 100) : 0;
    var kids = [];

    kids.push({
      type: "text",
      props: { text: "#" + p.id + " — " + truncate(p.title, 100) },
    });
    kids.push({
      type: "text",
      props: { text: "Topic: " + p.topic + " · Status: " + p.status },
    });
    kids.push({
      type: "text",
      props: { text: "Deadline: " + formatDeadline(p.deadline, p.status) },
    });
    kids.push({
      type: "text",
      props: {
        text:
          "Tally — Yes: " +
          formatBig(p.yes) +
          " (" +
          yesPct +
          "%) · No: " +
          formatBig(p.no) +
          " (" +
          noPct +
          "%)",
      },
    });
    if (p.summary && p.summary.length > 0) {
      kids.push({
        type: "text",
        props: { text: "Summary: " + truncate(p.summary, 240) },
      });
    }
    if (p.url && p.url.length > 0) {
      kids.push({
        type: "text",
        props: { text: p.url, copy: true, copy_label: "Copy URL" },
      });
    }

    return {
      type: "section",
      props: { title: "Proposal #" + p.id },
      children: kids,
    };
  }

  function truncate(s, n) {
    if (s == null) return "";
    s = String(s);
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
  }

  function formatBig(n) {
    return Number(n || 0).toLocaleString("en-US");
  }

  // SNS-specific: for non-Open proposals the wait_for_quiet_state deadline is
  // stale/0, so we show the status name instead of a meaningless countdown.
  function formatDeadline(epochSeconds, status) {
    if (status !== STATUS[1]) return "closed (" + status + ")";
    var n = Number(epochSeconds || 0);
    if (n === 0) return "—";
    var nowSec = Math.floor(Date.now() / 1000);
    var delta = n - nowSec;
    if (delta <= 0) return "closing";
    var days = Math.floor(delta / 86400);
    var hours = Math.floor((delta % 86400) / 3600);
    var mins = Math.floor((delta % 3600) / 60);
    if (days > 0) return days + "d " + hours + "h";
    if (hours > 0) return hours + "h " + mins + "m";
    return mins + "m";
  }

  // ───────────────────────── Generic helpers ──────────────────────────────
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

  function setStateShallow(state, patch) {
    return Object.assign({}, state, patch);
  }

  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
