// Path-B TS/QuickJS app bundle: an on-chain poll dapp UI.
//
// Demonstrates authenticated app-lifecycle effects: the bundle never touches
// raw private keys — it sets `authenticated: true` on effects that must sign as
// the active profile, and the host (script_app_host.dart) resolves the key.
//
// Example backend canister id (local): uxrrr-q7777-77774-qaaaq-cai.
// The LIVE id is NOT hardcoded here — it flows in via arg.backend_id/arg.host,
// set by the caller. Captured JSON shapes the bundle parses:
//   listPolls → msg.data = {"ok":true,"result":[{"id":"3","question":"...",
//                   "options":["A","B"],"creator":"<principal-STRING>"}]}
//   getTally  → msg.data = {"ok":true,"result":["1","0","0"]}   // vec nat
//   whoami    → msg.data = {"ok":true,"result":"<principal-STRING>"}
"use strict";
(() => {
  function init(arg) {
    var a = arg || {};
    return {
      state: {
        backend_id: a.backend_id || "",
        host: a.host || "",
        principal: "",
        polls: [],
        tallies: {},
        error: "",
        loading: false,
        newQuestion: "",
        newOptions: "",
      },
      effects: [],
    };
  }

  function view(state) {
    var kids = [];
    kids.push({
      type: "text",
      props: {
        text: state.principal
          ? "Signed in: " + state.principal
          : "No profile — view-only",
      },
    });
    kids.push({
      type: "button",
      props: {
        label: state.loading ? "Loading..." : "Refresh",
        on_press: { type: "refresh" },
      },
    });
    if (state.error && state.error.length > 0) {
      kids.push({ type: "text", props: { text: "Error: " + state.error } });
    }
    kids.push({
      type: "text",
      props: { text: "Polls (" + state.polls.length + ")" },
    });
    for (var i = 0; i < state.polls.length; i++) {
      kids.push(pollCard(state, state.polls[i]));
    }
    kids.push(createForm(state));
    return { type: "column", children: kids };
  }

  function pollCard(state, poll) {
    var children = [];
    children.push({ type: "text", props: { text: poll.question } });
    var tally = state.tallies[poll.id] || [];
    for (var i = 0; i < poll.options.length; i++) {
      var count = tally[i] != null ? tally[i] : "-";
      children.push({
        type: "row",
        children: [
          {
            type: "button",
            props: {
              label: poll.options[i],
              on_press: {
                type: "vote",
                pollId: poll.id,
                optionIndex: i,
              },
            },
          },
          { type: "text", props: { text: String(count) } },
        ],
      });
    }
    return {
      type: "section",
      props: { title: "Poll " + poll.id },
      children: children,
    };
  }

  function createForm(state) {
    return {
      type: "section",
      props: { title: "Create a poll" },
      children: [
        {
          type: "text_field",
          props: {
            label: "Question",
            value: state.newQuestion,
            on_change: { type: "set_question" },
          },
        },
        {
          type: "text_field",
          props: {
            label: "Options (comma-separated)",
            value: state.newOptions,
            on_change: { type: "set_options" },
          },
        },
        {
          type: "button",
          props: { label: "Create poll", on_press: { type: "create" } },
        },
      ],
    };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";

    if (t === "set_question") {
      return setState(state, { newQuestion: String(msg.value || "") });
    }
    if (t === "set_options") {
      return setState(state, { newOptions: String(msg.value || "") });
    }

    if (t === "refresh") {
      return {
        state: setStateShallow(state, { loading: true, error: "" }),
        effects: refreshEffects(state),
      };
    }

    if (t === "vote") {
      // args = textual Candid; `: nat` is required by the canister (else it
      // rejects with "unexpected IDL type when parsing Nat").
      var voteArgs = '("' + msg.pollId + '", ' + msg.optionIndex + " : nat)";
      return {
        state: setStateShallow(state, { error: "" }),
        effects: [callEffect("vote", 1, "vote", voteArgs, true, state)],
      };
    }

    if (t === "create") {
      var q = (state.newQuestion || "").trim();
      var opts = parseOptions(state.newOptions);
      if (q.length === 0) {
        return setState(state, { error: "Question must not be empty" });
      }
      if (opts.length < 2) {
        return setState(state, {
          error: "Provide at least 2 options (comma-separated)",
        });
      }
      return {
        state: setStateShallow(state, {
          error: "",
          newQuestion: "",
          newOptions: "",
        }),
        effects: [
          callEffect("create", 1, "createPoll", candidCreateArgs(q, opts), true, state),
        ],
      };
    }

    if (t === "effect/result") {
      return handleResult(msg, state);
    }

    return { state: state, effects: [] };
  }

  // Build a single icp_call effect with flat fields the host reads.
  // args may be textual Candid (e.g. '("3", 0 : nat)') or JSON.
  function callEffect(id, mode, method, args, authenticated, state) {
    return {
      kind: "icp_call",
      id: id,
      mode: mode,
      canister_id: state.backend_id,
      method: method,
      args: args,
      host: state.host,
      authenticated: !!authenticated,
    };
  }

  function refreshEffects(state) {
    return [
      callEffect("whoami", 0, "whoami", "()", true, state),
      callEffect("listPolls", 0, "listPolls", "()", false, state),
    ];
  }

  // Textual Candid for createPoll: ("Q?", vec {"A"; "B"})
  function candidCreateArgs(question, options) {
    var quoted = options
      .map(function (o) {
        return '"' + esc(o) + '"';
      })
      .join("; ");
    return '("' + esc(question) + '", vec { ' + quoted + " })";
  }

  function parseOptions(raw) {
    if (!raw) return [];
    return raw
      .split(",")
      .map(function (s) {
        return s.trim();
      })
      .filter(function (s) {
        return s.length > 0;
      });
  }

  function esc(s) {
    return String(s)
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"');
  }

  function handleResult(msg, state) {
    var id = msg.id || "";
    var parsed = readEffect(msg);

    if (id === "whoami") {
      // Auth unavailable (no profile) is non-fatal: principal stays empty and
      // the view renders "view-only". Other whoami errors are surfaced.
      if (!parsed.ok) {
        return setState(state, { principal: "" });
      }
      return setState(state, { principal: String(parsed.value || "") });
    }

    if (id === "listPolls") {
      if (!parsed.ok) {
        return setState(state, { loading: false, error: parsed.error });
      }
      var polls = parsed.value || [];
      var tallyFx = [];
      for (var i = 0; i < polls.length; i++) {
        var pid = polls[i].id;
        tallyFx.push(
          callEffect("tally:" + pid, 0, "getTally", '("' + pid + '")', false, state)
        );
      }
      return {
        state: setStateShallow(state, { polls: polls, tallies: {} }),
        effects: tallyFx,
      };
    }

    if (id.indexOf("tally:") === 0) {
      var pollId = id.substring("tally:".length);
      if (!parsed.ok) {
        return { state: state, effects: [] };
      }
      var tallies = Object.assign({}, state.tallies);
      tallies[pollId] = (parsed.value || []).map(function (n) {
        return Number(n);
      });
      return setState(state, { tallies: tallies });
    }

    if (id === "vote" || id === "create") {
      if (!parsed.ok) {
        return setState(state, { error: parsed.error });
      }
      // State changed on the canister — refresh to reflect it.
      return { state: state, effects: refreshEffects(state) };
    }

    return { state: state, effects: [] };
  }

  // Normalize a delivered effect/result into {ok, value|error}. The host wraps
  // host-level failures as {ok:false,error}, success as {ok:true,data}; the
  // bridge further wraps payloads as {ok:true,result} / {ok:false,error}.
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
