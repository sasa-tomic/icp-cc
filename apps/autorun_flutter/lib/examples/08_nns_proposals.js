// Path-B TS/QuickJS app bundle: browse LIVE NNS governance proposals on mainnet.
//
// A headliner demo of what icp-cc can do against a REAL public canister, with
// zero user setup (no profile, no signing, no neuron). Calls NNS Governance
// `list_proposals` (read-only query) — the same canister ALPHA-Vote / CO.DELTA
// automate in Rust (see third_party/ALPHA-Vote). This bundle is the readable,
// pedagogical JavaScript port: a curious user can read every line.
//
// Canister id + host flow in via arg.backend_id / arg.host (the descriptor
// defaults — NNS Governance rrkah-fqaaa-aaaaa-aaaaq-cai + ic0.app).
//
// Candid args (verified live via dfx; every field is MANDATORY):
//   list_proposals: (record {
//     limit = N : nat32;
//     exclude_topic = vec {};
//     include_reward_status = vec {};
//     include_status = vec {};
//     omit_large_fields = opt true;       ← opt bool, must be `opt true`
//   })
//
// Decoded JSON shape (Rust bridge: IDLArgs::from_bytes + idl_args_to_json):
//   { proposal_info: [
//     { id: [{ id: 12345 }],               ← opt record → 1-elem array
//       status: 4, topic: 12,              ← bare int32
//       deadline_timestamp_seconds: [1234567890],   ← opt nat64
//       latest_tally: [{ yes, no, total, timestamp_seconds }],
//       proposal: [{ title: ["..."], summary: "...", url: ["..."], action: [{...}] }],
//       proposer: [{ id: 7 }],
//       reward_status: 1 }, ... ] }
//
// opt T becomes [T] (empty array when null). unwrapOpt() normalises.
"use strict";
(() => {
  // ───────────────────────── Constants (single source) ────────────────────
  var PAGE_SIZE = 10;

  // NNS GovernanceProposal status enum (Governance Rust + observed live).
  var STATUS = {
    0: "Unknown",
    1: "Open",
    2: "Rejected",
    3: "Adopted",
    4: "Executed",
    5: "Failed",
  };

  // NNS topic enum (Governance Rust + observed live). Only the values a user
  // is likely to filter by get a human label; unknown ints fall back to
  // "Topic #N".
  var TOPIC = {
    0: "Unspecified",
    1: "TopicExchange",
    4: "SNS Launch",
    5: "SNS & Community Fund",
    6: "NodeAdmin",
    7: "NetworkEconomics",
    8: "Governance",
    10: "NetworkCanisterBase",
    11: "SubnetManagement",
    12: "ReplicaVersionManagement",
  };

  // Each status filter is sent as include_status = vec { int }; "all" sends
  // an empty vec (server returns every status).
  var STATUS_FILTER_VALUE = {
    all: "",
    open: "1",
    rejected: "2",
    adopted: "3",
    executed: "4",
  };

  // ───────────────────────── Lifecycle ────────────────────────────────────
  function init(arg) {
    var a = arg || {};
    var state = {
      backend_id: a.backend_id || "",
      host: a.host || "",
      status_filter: "open", // open is the actionable default
      topic_filter: "all",
      page: 0,
      page_size: PAGE_SIZE,
      cursor_history: [], // cursor_history[N] = min proposal id from page N-1
      loading: false,
      loaded: false,
      error: "",
      proposals: [], // last fetched page of decoded records
      has_more: false, // server returned a full page
    };
    // AUTO-LOAD on mount so the tab opens to real data (UXR-6).
    return { state: state, effects: [listProposalsEffect(state)] };
  }

  function view(state) {
    var kids = [];

    kids.push({
      type: "text",
      props: { text: "NNS Proposals — live on mainnet (read-only)" },
    });

    // Filter row: status select + topic select + Refresh.
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
          type: "select",
          props: {
            label: "Topic",
            value: state.topic_filter,
            options: topicOptions(),
            on_change: { type: "set_topic" },
          },
        },
        {
          type: "button",
          props: {
            label: state.loading ? "Querying mainnet…" : "Refresh",
            on_press: { type: "refresh" },
            disabled: state.loading,
          },
        },
      ],
    });

    if (state.error && state.error.length > 0) {
      kids.push({ type: "text", props: { text: "Error: " + state.error } });
    }

    if (state.loading && state.proposals.length === 0) {
      kids.push({ type: "text", props: { text: "Loading proposals…" } });
    } else if (state.loaded && state.proposals.length === 0) {
      kids.push({
        type: "text",
        props: {
          text:
            "No proposals match this filter. " +
            '(NNS has quiet periods — try "all" to see recent history.)',
        },
      });
    } else {
      for (var i = 0; i < state.proposals.length; i++) {
        kids.push(proposalCard(state.proposals[i]));
      }
    }

    // Pagination row.
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
          {
            type: "text",
            props: { text: "Page " + (state.page + 1) },
          },
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

    return { type: "column", children: kids };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";

    if (t === "refresh") {
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

    if (t === "set_topic") {
      var nextTopic = Object.assign({}, state, {
        topic_filter: String(msg.value || "all"),
        loading: true,
        error: "",
        page: 0,
        cursor_history: [],
      });
      return { state: nextTopic, effects: [listProposalsEffect(nextTopic, 0)] };
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
    var topicVec = buildTopicVec(state.topic_filter);
    var history = state.cursor_history || [];
    var cursor = history[page] != null ? history[page] : null;
    var beforeProposal = cursor != null
        ? "before_proposal = opt record { id = " + cursor + " : nat64 }"
        : "before_proposal = null";
    var args =
      "(record { limit = " +
      state.page_size +
      " : nat32; " +
      beforeProposal +
      "; exclude_topic = " +
      topicVec +
      "; include_reward_status = vec {}; include_status = " +
      statusVec +
      "; omit_large_fields = opt true; })";
    return {
      kind: "icp_call",
      id: "list_proposals",
      mode: 0, // query
      canister_id: state.backend_id,
      method: "list_proposals",
      args: args,
      host: state.host,
      authenticated: false, // read-only — works without a profile
    };
  }

  // `status_filter` is one of STATUS_FILTER_VALUE's keys; the empty-string
  // value means "all" → emit an empty vec.
  function buildStatusVec(filterKey) {
    var v = STATUS_FILTER_VALUE[filterKey];
    if (!v || v.length === 0) {
      return "vec {}";
    }
    return "vec { " + v + " : int32 }";
  }

  function buildTopicVec(topicKey) {
    if (topicKey === "all" || topicKey == null) {
      return "vec {}";
    }
    // exclude_topic takes topic ints to EXCLUDE; we want a positive filter,
    // so we don't use it — we filter client-side in handleResult to keep the
    // server query simple and predictable. Empty vec = no exclusions.
    return "vec {}";
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
    var info = envelope.proposal_info;
    if (!Array.isArray(info)) {
      return setState(state, {
        loading: false,
        error: "list_proposals: malformed reply (proposal_info not an array)",
      });
    }
    var filtered = filterByTopic(info, state.topic_filter);
    var decoded = filtered.map(decodeProposal);
    var newHistory = (state.cursor_history || []).slice();
    if (info.length >= state.page_size) {
      var minId = null;
      for (var i = 0; i < info.length; i++) {
        var pid = unwrapOptInt(unwrapOpt(info[i].id, {}).id, 0);
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
      has_more: info.length >= state.page_size,
      cursor_history: newHistory,
    });
  }

  // ───────────────────────── Decoding helpers ─────────────────────────────
  // The Rust bridge decodes `opt T` as `[T]` (1-elem array) when present, `[]`
  // when null. Bare (non-opt) fields arrive as the bare value. This helper
  // normalises BOTH shapes: arrays are unwrapped to their first element (or
  // fallback when empty), bare values pass through unchanged, null/undefined
  // → fallback.
  function unwrapOpt(v, fallback) {
    if (Array.isArray(v)) {
      return v.length > 0 ? v[0] : (fallback == null ? null : fallback);
    }
    return v == null ? (fallback == null ? null : fallback) : v;
  }

  function unwrapOptInt(v, fallback) {
    var x = unwrapOpt(v, fallback);
    if (x == null) return fallback == null ? 0 : fallback;
    // Numbers from JSON may arrive as numbers or strings depending on bridge.
    return typeof x === "number" ? x : Number(x) || (fallback == null ? 0 : fallback);
  }

  function decodeProposal(raw) {
    var idNode = unwrapOpt(raw.id, {}); // ProposalId record { id: nat64 }
    var proposalNode = unwrapOpt(raw.proposal, {});
    var tallyNode = unwrapOpt(raw.latest_tally, {});
    return {
      id: unwrapOptInt(idNode.id, 0),
      status: statusLabel(raw.status),
      topic: topicLabel(raw.topic),
      title: unwrapOpt(proposalNode.title, "(untitled proposal)"),
      summary: unwrapOpt(proposalNode.summary, ""),
      url: unwrapOpt(proposalNode.url, ""),
      deadline: unwrapOptInt(raw.deadline_timestamp_seconds, 0),
      yes: unwrapOptInt(tallyNode.yes, 0),
      no: unwrapOptInt(tallyNode.no, 0),
      total: unwrapOptInt(tallyNode.total, 0),
    };
  }

  function statusLabel(s) {
    var n = Number(s);
    return STATUS[n] || "Unknown (" + s + ")";
  }

  function topicLabel(t) {
    var n = Number(t);
    return TOPIC[n] || "Topic #" + t;
  }

  function filterByTopic(info, topicKey) {
    if (topicKey === "all" || topicKey == null) return info;
    var want = Number(topicKey);
    return info.filter(function (p) {
      return Number(p.topic) === want;
    });
  }

  function topicOptions() {
    var opts = [{ value: "all", label: "All topics" }];
    Object.keys(TOPIC).forEach(function (k) {
      opts.push({ value: k, label: TOPIC[k] });
    });
    return opts;
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
      props: { text: "Deadline: " + formatDeadline(p.deadline) },
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
    // Voting power is in e8s-like units; group with commas for readability.
    return Number(n || 0).toLocaleString("en-US");
  }

  function formatDeadline(epochSeconds) {
    var n = Number(epochSeconds || 0);
    if (n === 0) return "—";
    var nowSec = Math.floor(Date.now() / 1000);
    var delta = n - nowSec;
    if (delta <= 0) return "closed";
    var days = Math.floor(delta / 86400);
    var hours = Math.floor((delta % 86400) / 3600);
    var mins = Math.floor((delta % 3600) / 60);
    if (days > 0) return days + "d " + hours + "h";
    if (hours > 0) return hours + "h " + mins + "m";
    return mins + "m";
  }

  // ───────────────────────── Generic helpers ──────────────────────────────
  // Normalize a delivered effect/result into {ok, value|error}. Mirrors the
  // 06 / 07 bundles' reader: host wraps host-level failures as
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
