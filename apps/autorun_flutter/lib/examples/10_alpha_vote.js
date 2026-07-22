// Path-B TS/QuickJS app bundle: AUTHENTICATED NNS neuron voting.
//
// The authenticated sequel to 08_nns_proposals (read-only). A user with a
// staked NNS neuron can, from inside icp-cc:
//   - browse open proposals (read-only, reused from 08);
//   - see what the 3 ALPHA-Vote public neurons (αlpha-vote, Ωmega-vote,
//     Ωmega-reject) voted on each open proposal (transparency surface);
//   - cast a one-off RegisterVote (Yes/No) on any open proposal;
//   - set up recurring Following of a neuron on a topic (NNS Governance itself
//     copies the followee's vote on every future proposal — true set-and-forget,
//     NOT a long-running canister).
//
// USER-DRIVEN, NOT AUTONOMOUS. Every authenticated effect fires in response to
// an explicit user button tap. The recurring case is delegated to NNS
// Governance via the Follow variant. (Spec: 2026-07-21-alpha-vote-dapp.md.)
//
// AUTH MODEL (mirror of 06_icp_poll.js): every manage_neuron / list_neurons
// effect carries `authenticated: true`; the host resolves the active profile's
// keypair and signs. The bundle NEVER touches raw private keys. If no profile
// is active, the host enqueues a loud missing-auth error — never a silent
// anonymous fallback.
//
// Candid args verified live 2026-07-21 via dfx 0.32.0 against
// rrkah-fqaaa-aaaaa-aaaaq-cai (spec §5 + §10.2 transcripts). A real
// authenticated manage_neuron with a neuron the caller doesn't own returns:
//   command = opt variant { Error = {
//     error_message: "Neuron not found: NeuronId { id: 12345 }";
//     error_type: 4 } }
// — proving the auth round-trip reaches NNS, is NOT anon-rejected, parses
// correctly, and is rejected at the application layer.
//
// Neuron-id uses the deprecated `id` field (NOT neuron_id_or_subaccount) for
// pedagogical continuity with ALPHA-Vote's Rust reference
// (third_party/ALPHA-Vote/.../lib.rs:140, 193). NNS still honours `id`.
"use strict";
(() => {
  // ───────────────────────── Constants ────────────────────────────────────
  var PAGE_SIZE = 10;

  // ALPHA-Vote's 3 PUBLIC known neurons (canonical mainnet ids). The bundle
  // shows what each voted on every open proposal — the recommendation surface.
  // The ids MUST be string keys (not numeric): the Ωmega ids exceed JS
  // Number.MAX_SAFE_INTEGER (2^53 ≈ 9.0e15) and would lose precision when
  // used as object keys (the lookup against the decoded ballots would miss).
  var ALPHA_VOTE_NEURONS = {
    "2947465672511369": "αlpha-vote",
    "18363645821499695760": "Ωmega-vote",
    "18422777432977120264": "Ωmega-reject",
  };
  // D-QUORUM upstream diligent voter. Surfaced as an extra Follow affordance.
  var D_QUORUM_NEURON_ID = "4713806069430754115";

  // NNS topic enum (current, per ALPHA-Vote README + NNS source). Unknown ints
  // fall back to "Topic #N".
  var TOPIC = {
    0: "Unspecified",
    1: "Governance",
    4: "SNS & Neurons Fund (legacy)",
    8: "Governance",
    11: "SubnetManagement",
    12: "ReplicaVersionManagement",
    14: "SNS & Neurons Fund",
  };
  // Topics the Follow affordance offers (the 3 ALPHA-Vote follows on).
  var FOLLOW_TOPICS = [
    { value: "0", label: "Unspecified (all topics)" },
    { value: "1", label: "Governance" },
    { value: "4", label: "SNS & Neurons Fund (legacy)" },
    { value: "14", label: "SNS & Neurons Fund" },
  ];

  var STATUS = {
    0: "Unknown", 1: "Open", 2: "Rejected",
    3: "Adopted", 4: "Executed", 5: "Failed",
  };
  // Each status filter sent as include_status = vec { int }; "all" → empty vec.
  var STATUS_FILTER_VALUE = {
    all: "", open: "1", rejected: "2", adopted: "3", executed: "4",
  };

  // ───────────────────────── Lifecycle ────────────────────────────────────
  function init(arg) {
    var a = arg || {};
    var state = {
      backend_id: a.backend_id || "",
      host: a.host || "",
      principal: a.principal || "",
      neuron_id: "",
      discovered_neuron_ids: [],
      status_filter: "open",
      topic_filter: "all",
      page: 0,
      page_size: PAGE_SIZE,
      cursor_history: [],
      loading: false,
      loaded: false,
      error: "",
      proposals: [],
      has_more: false,
      action_in_flight: false,
      last_action_result: "",
      last_action_ok: false,
    };
    // AUTO-LOAD (UXR-6): list_proposals is anonymous (works for keyless users);
    // list_neurons is authenticated — only fires if principal is set, so a
    // keyless user gets browse-only without a missing-auth error on first frame.
    var effects = [listProposalsEffect(state)];
    if (state.principal && state.principal.length > 0) {
      effects.push(listNeuronsEffect(state));
    }
    return { state: state, effects: effects };
  }

  function view(state) {
    var kids = [];
    kids.push({
      type: "text",
      props: {
        text: state.principal
          ? "Neuron Voting — mainnet (signed as: " + state.principal + ")"
          : "Neuron Voting — mainnet (view-only: signing unlocks voting)",
      },
    });
    kids.push(yourNeuronSection(state));
    kids.push({
      type: "row",
      children: [
        selectNode("Status", state.status_filter,
            Object.keys(STATUS_FILTER_VALUE).map(function (k) {
              return { value: k, label: k.charAt(0).toUpperCase() + k.slice(1) };
            }),
            "set_status"),
        selectNode("Topic", state.topic_filter, topicOptionsMap(), "set_topic"),
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
    if (state.action_in_flight) {
      kids.push({ type: "text", props: { text: "Signing + sending vote…" } });
    } else if (state.last_action_result && state.last_action_result.length > 0) {
      var prefix = state.last_action_ok ? "✓ " : "✗ ";
      kids.push({ type: "text", props: { text: prefix + state.last_action_result } });
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
        kids.push(alphaVoteProposalCard(state, state.proposals[i]));
      }
    }

    if (state.proposals.length > 0) {
      kids.push({
        type: "row",
        children: [
          buttonNode("‹ Prev", { type: "page", delta: -1 },
              state.page === 0 || state.loading),
          { type: "text", props: { text: "Page " + (state.page + 1) } },
          buttonNode("Next ›", { type: "page", delta: 1 },
              !state.has_more || state.loading),
        ],
      });
    }

    return { type: "column", children: kids };
  }

  function update(msg, state) {
    var t = (msg && msg.type) || "";

    if (t === "refresh") {
      return {
        state: setStateShallow(state, {
            loading: true, error: "", page: 0, cursor_history: []}),
        effects: refreshEffects(state),
      };
    }
    if (t === "set_status") {
      var next = Object.assign({}, state, {
        status_filter: String(msg.value || "all"),
        loading: true, error: "", page: 0,
        cursor_history: [],
      });
      return { state: next, effects: [listProposalsEffect(next, 0)] };
    }
    if (t === "set_topic") {
      var nextTopic = Object.assign({}, state, {
        topic_filter: String(msg.value || "all"),
        loading: true, error: "", page: 0,
        cursor_history: [],
      });
      return { state: nextTopic, effects: [listProposalsEffect(nextTopic, 0)] };
    }
    if (t === "page") {
      var delta = Number(msg.delta || 0);
      var targetPage = Math.max(0, state.page + delta);
      if (targetPage === state.page) return { state: state, effects: [] };
      var paged = Object.assign({}, state, {
        page: targetPage, loading: true, error: "",
      });
      return { state: paged, effects: [listProposalsEffect(paged, targetPage)] };
    }

    if (t === "set_neuron_id" || t === "select_discovered_neuron") {
      return setState(state, { neuron_id: String(msg.value || "").trim() });
    }

    if (t === "discover_neurons") {
      if (!state.principal || state.principal.length === 0) {
        return setState(state, {
          error: "Sign in with a profile to discover your neurons.",
        });
      }
      return {
        state: setStateShallow(state, { error: "" }),
        effects: [listNeuronsEffect(state)],
      };
    }

    if (t === "vote") {
      return manageAction(state, "vote", {
        effectId: "vote",
        buildEffect: function (nid) {
          return manageNeuronVoteEffect(
              "vote", nid, msg.proposal_id, Number(msg.vote), state);
        },
      });
    }
    if (t === "follow") {
      var fid = String(msg.followee_id || "").trim();
      if (!fid) {
        return setState(state, { error: "Enter a followee neuron id to follow." });
      }
      return manageAction(state, "follow", {
        effectId: "follow",
        buildEffect: function (nid) {
          return manageNeuronFollowEffect(
              "follow", nid, String(msg.topic), [fid], state);
        },
      });
    }

    if (t === "effect/result") return handleResult(msg, state);

    return { state: state, effects: [] };
  }

  // Shared precondition + in-flight flagging for vote / follow.
  function manageAction(state, id, handlers) {
    var nid = state.neuron_id;
    if (!nid || nid.length === 0) {
      return setState(state, {
        error: "Set your neuron id first (paste one or tap Discover).",
      });
    }
    return {
      state: setStateShallow(state, {
        action_in_flight: true,
        error: "",
        last_action_result: "",
        last_action_ok: false,
      }),
      effects: [handlers.buildEffect(nid)],
    };
  }

  // ───────────────────────── Effects ──────────────────────────────────────
  function refreshEffects(state) {
    var fx = [listProposalsEffect(state)];
    if (state.principal && state.principal.length > 0) {
      fx.push(listNeuronsEffect(state));
    }
    return fx;
  }

  function listProposalsEffect(state, pageOverride) {
    var page = pageOverride != null ? pageOverride : state.page;
    var statusVec = buildStatusVec(state.status_filter);
    var history = state.cursor_history || [];
    var cursor = history[page] != null ? history[page] : null;
    var beforeProposal = cursor != null
        ? "before_proposal = opt record { id = " + cursor + " : nat64 }"
        : "before_proposal = null";
    var args =
      "(record { limit = " + state.page_size + " : nat32; " +
      beforeProposal + "; " +
      "exclude_topic = vec {}; include_reward_status = vec {}; " +
      "include_status = " + statusVec + "; omit_large_fields = opt true; })";
    return {
      kind: "icp_call", id: "list_proposals", mode: 0,
      canister_id: state.backend_id, method: "list_proposals",
      args: args, host: state.host, authenticated: false,
    };
  }

  function listNeuronsEffect(state) {
    return {
      kind: "icp_call", id: "list_neurons", mode: 0,
      canister_id: state.backend_id, method: "list_neurons",
      args: "(record { neuron_ids = vec {}; " +
            "include_neurons_readable_by_caller = true; })",
      host: state.host, authenticated: true,
    };
  }

  // Verified live via simulate_manage_neuron + real authenticated call.
  // See spec §5.2 + §10.2 PoC transcript.
  function manageNeuronVoteEffect(id, neuronId, proposalId, voteInt, state) {
    var args =
      "(record { id = opt record { id = " + neuronId + " : nat64 }; " +
      "command = opt variant { RegisterVote = record { " +
      "vote = " + voteInt + " : int32; " +
      "proposal = opt record { id = " + proposalId + " : nat64 }; } }; })";
    return {
      kind: "icp_call", id: id, mode: 1,
      canister_id: state.backend_id, method: "manage_neuron",
      args: args, host: state.host, authenticated: true,
    };
  }

  // Verified live via simulate_manage_neuron + real authenticated call.
  // See spec §5.3 + §10.2 PoC transcript.
  function manageNeuronFollowEffect(id, neuronId, topic, followeeIds, state) {
    var vec = followeeIds.map(function (fid) {
      return "record { id = " + fid + " : nat64 }";
    }).join("; ");
    var args =
      "(record { id = opt record { id = " + neuronId + " : nat64 }; " +
      "command = opt variant { Follow = record { " +
      "topic = " + topic + " : int32; " +
      "followees = vec { " + vec + " }; } }; })";
    return {
      kind: "icp_call", id: id, mode: 1,
      canister_id: state.backend_id, method: "manage_neuron",
      args: args, host: state.host, authenticated: true,
    };
  }

  function buildStatusVec(filterKey) {
    var v = STATUS_FILTER_VALUE[filterKey];
    if (!v || v.length === 0) return "vec {}";
    return "vec { " + v + " : int32 }";
  }

  // ───────────────────────── Result handling ──────────────────────────────
  function handleResult(msg, state) {
    var id = msg.id || "";
    if (id === "list_proposals") return handleListProposals(msg, state);
    if (id === "list_neurons") return handleListNeurons(msg, state);
    if (id === "vote" || id === "follow") return handleManageNeuron(id, msg, state);
    return setState(state, { error: "unknown effect id: " + id });
  }

  function handleListProposals(msg, state) {
    var parsed = readEffect(msg);
    if (!parsed.ok) {
      return setState(state, {
        loading: false, error: "list_proposals: " + parsed.error,
      });
    }
    var info = (parsed.value || {}).proposal_info;
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
      loading: false, loaded: true, error: "",
      proposals: decoded,
      has_more: info.length >= state.page_size,
      cursor_history: newHistory,
    });
  }

  function handleListNeurons(msg, state) {
    var parsed = readEffect(msg);
    if (!parsed.ok) {
      // Missing-auth on list_neurons is LOUD: the user explicitly tapped
      // Discover (unlike 06_icp_poll's auto-whoami, this is user-initiated).
      return setState(state, { error: "list_neurons: " + parsed.error });
    }
    // neuron_infos is `vec record { nat64; NeuronInfo }` — candid HashMap
    // serialisation. We only need the ids (first element of each pair).
    var infos = (parsed.value || {}).neuron_infos || [];
    var ids = [];
    for (var i = 0; i < infos.length; i++) {
      var pair = infos[i];
      if (Array.isArray(pair) && pair.length > 0) {
        ids.push(String(pair[0]));
      } else if (pair && typeof pair === "object" && pair.id != null) {
        ids.push(String(pair.id));
      }
    }
    // Auto-pick the first neuron if none is set yet.
    var patch = { discovered_neuron_ids: ids };
    if ((!state.neuron_id || state.neuron_id.length === 0) && ids.length > 0) {
      patch.neuron_id = ids[0];
    }
    return setState(state, patch);
  }

  function handleManageNeuron(id, msg, state) {
    var parsed = readEffect(msg);
    if (!parsed.ok) {
      // Host/bridge failure (replica unreachable, candid decode, ...).
      return setState(state, {
        action_in_flight: false,
        last_action_ok: false,
        last_action_result: id + ": " + parsed.error,
      });
    }
    var decoded = decodeManageNeuronResponse(parsed.value);
    return setState(state, {
      action_in_flight: false,
      last_action_ok: decoded.ok,
      last_action_result: decoded.message,
    });
  }

  // ───────────────────────── Decoding helpers ─────────────────────────────
  // unwrapOpt / unwrapOptInt / statusLabel / topicLabel / filterByTopic are
  // reused verbatim from 08_nns_proposals.js. decodeProposal is extended
  // (adds alpha_signal) and topicOptionsMap mirrors 08's topicOptions.
  function unwrapOpt(v, fallback) {
    if (Array.isArray(v)) {
      return v.length > 0 ? v[0] : (fallback == null ? null : fallback);
    }
    return v == null ? (fallback == null ? null : fallback) : v;
  }
  function unwrapOptInt(v, fallback) {
    var x = unwrapOpt(v, fallback);
    if (x == null) return fallback == null ? 0 : fallback;
    return typeof x === "number"
      ? x : Number(x) || (fallback == null ? 0 : fallback);
  }

  function decodeProposal(raw) {
    var idNode = unwrapOpt(raw.id, {});
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
      alpha_signal: alphaVoteSignal(decodeBallots(raw.ballots)),
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
    return info.filter(function (p) { return Number(p.topic) === want; });
  }
  function topicOptionsMap() {
    var opts = [{ value: "all", label: "All topics" }];
    Object.keys(TOPIC).forEach(function (k) {
      opts.push({ value: k, label: TOPIC[k] });
    });
    return opts;
  }

  // Decode ballots (vec record { nat64; Ballot }) into {neuronId: {vote,...}}.
  // The Rust bridge decodes each candid HashMap entry's positional record as
  // an object with string keys "0" (the nat64 id) + "1" (the Ballot record)
  // — see canister_client.rs label_to_string + IDLValue::Record. We also
  // accept a JS array shape defensively (some bridges serialise tuples as
  // arrays). Ballot = { vote: int32, voting_power: nat64 }.
  function decodeBallots(rawBallots) {
    var out = {};
    if (!Array.isArray(rawBallots)) return out;
    for (var i = 0; i < rawBallots.length; i++) {
      var pair = rawBallots[i];
      var neuronId = null, ballot = null;
      if (Array.isArray(pair) && pair.length >= 2) {
        neuronId = pair[0];
        ballot = pair[1];
      } else if (pair && typeof pair === "object") {
        // Positional record (vec record { nat64; Ballot }) arrives as
        // { "0": <nat64-string>, "1": { vote, voting_power } } via the Rust
        // bridge. Fall back to named fields defensively.
        neuronId = pair["0"] != null ? pair["0"] :
                   (pair.neuron_id != null ? pair.neuron_id : pair.id);
        ballot = pair["1"] != null ? pair["1"] : pair.ballot;
      }
      if (neuronId == null || ballot == null) continue;
      out[String(neuronId)] = {
        vote: unwrapOptInt(ballot.vote, 0),
        voting_power: unwrapOptInt(ballot.voting_power, 0),
      };
    }
    return out;
  }

  // Surface ALPHA-Vote's signal: array of {neuron_id, label, vote_label} for
  // the 3 ALPHA_VOTE_NEURONS ids.
  function alphaVoteSignal(decodedBallots) {
    var out = [];
    Object.keys(ALPHA_VOTE_NEURONS).forEach(function (nid) {
      var b = decodedBallots[nid];
      out.push({
        neuron_id: nid,
        label: ALPHA_VOTE_NEURONS[nid],
        vote_label: b ? ballotVoteLabel(b.vote) : "not voted yet",
      });
    });
    return out;
  }
  // Vote int → label. 1="Yes", 2="No", 0/undefined="not voted yet".
  function ballotVoteLabel(voteInt) {
    var n = Number(voteInt);
    if (n === 1) return "Yes";
    if (n === 2) return "No";
    return "not voted yet";
  }

  // Decode ManageNeuronResponse into {ok, message}. VERIFIED 2026-07-21: a
  // real authenticated manage_neuron with a neuron the caller doesn't own
  // returns command = opt variant {
  //   Error = { error_message: "Neuron not found: ..."; error_type: 4 } }.
  // Unknown variants surface verbatim — never silent (spec §6.8, §12.3).
  function decodeManageNeuronResponse(parsed) {
    if (parsed == null || typeof parsed !== "object") {
      return { ok: false, message: "manage_neuron: malformed reply (no record)" };
    }
    var command = unwrapOpt(parsed.command, null);
    if (command == null) {
      return {
        ok: false,
        message: "manage_neuron: malformed reply (command missing)",
      };
    }
    var keys = Object.keys(command);
    if (keys.length === 0) {
      return {
        ok: false,
        message: "manage_neuron: malformed reply (empty variant)",
      };
    }
    var variantName = keys[0];
    var payload = command[variantName];

    if (variantName === "Error") {
      var errMsg = (payload && payload.error_message) || "(no error message)";
      var errType = payload && payload.error_type != null ? payload.error_type : -1;
      return { ok: false, message: friendlyNnsError(errType, errMsg) };
    }
    if (variantName === "RegisterVoteResponse") {
      return { ok: true, message: "Vote recorded." };
    }
    if (variantName === "FollowResponse") {
      return {
        ok: true,
        message:
          "Follow recorded. NNS Governance will copy this neuron's votes on " +
          "every future proposal on this topic — you don't need this dapp open.",
      };
    }
    // Unknown variant (Configure, Spawn, Split, ...) — the bundle only emits
    // RegisterVote + Follow, so reaching here means NNS changed its response
    // shape: be loud, never silent.
    return {
      ok: false,
      message: "manage_neuron: unexpected variant " + variantName +
          " (" + JSON.stringify(payload).slice(0, 120) + ")",
    };
  }

  // Friendly NNS error mapper. Matches on error_message TEXT (the type ints
  // are not documented as stable; the message strings have been stable for
  // years). Spec §6.9. Fallback surfaces verbatim — never swallowed.
  function friendlyNnsError(errorType, errorMessage) {
    var msg = String(errorMessage || "");
    var lower = msg.toLowerCase();
    if (lower.indexOf("neuron not found") !== -1) {
      return "NNS doesn't see this neuron under your active profile's " +
          "principal. Either the id is wrong, or this neuron is controlled " +
          "by a different identity. (NNS said: \"" + msg + "\")";
    }
    if (lower.indexOf("already voted") !== -1) {
      return "You've already voted on this proposal. " +
          "(NNS doesn't allow changing a vote once cast.)";
    }
    if (lower.indexOf("dissolve delay") !== -1 ||
        lower.indexOf("insufficient") !== -1) {
      return "This neuron can't vote yet — it needs a dissolve delay of at " +
          "least 6 months. Manage it on the NNS dashboard. " +
          "(NNS said: \"" + msg + "\")";
    }
    if (lower.indexOf("not eligible") !== -1 ||
        lower.indexOf("no voting power") !== -1) {
      return "This neuron has no voting power (possibly not staked for long " +
          "enough). See the NNS staking docs. (NNS said: \"" + msg + "\")";
    }
    return "NNS responded (type " + errorType + "): " + msg;
  }

  // ───────────────────────── View helpers ─────────────────────────────────
  function yourNeuronSection(state) {
    var children = [];
    if (state.discovered_neuron_ids.length > 0) {
      children.push({
        type: "select",
        props: {
          label: "Active neuron",
          value: state.neuron_id,
          options: state.discovered_neuron_ids.map(function (nid) {
            return { value: nid, label: "#" + nid };
          }),
          on_change: { type: "select_discovered_neuron" },
        },
      });
    }
    children.push({
      type: "text_field",
      props: {
        label: "Or paste a neuron id",
        value: state.neuron_id,
        on_change: { type: "set_neuron_id" },
      },
    });
    children.push({
      type: "row",
      children: [
        {
          type: "button",
          props: {
            label: "Discover my neurons",
            on_press: { type: "discover_neurons" },
            // Disabled for keyless users — discover_neurons raises a loud
            // error if principal is empty, but disabling pre-empts the round-
            // trip (one fewer spinner + failed call for the user).
            disabled: !state.principal || state.principal.length === 0,
          },
        },
        {
          type: "text",
          props: {
            text: state.neuron_id ? "Active: #" + state.neuron_id : "(no neuron set)",
            copy: true, copy_label: "Copy active neuron id",
          },
        },
      ],
    });
    return { type: "section", props: { title: "Your neuron" }, children: children };
  }

  function alphaVoteProposalCard(state, p) {
    var tallyTotal = p.total || (p.yes + p.no);
    var yesPct = tallyTotal > 0 ? Math.round((p.yes / tallyTotal) * 100) : 0;
    var noPct = tallyTotal > 0 ? Math.round((p.no / tallyTotal) * 100) : 0;
    var kids = [];

    kids.push({ type: "text",
      props: { text: "#" + p.id + " — " + truncate(p.title, 100) } });
    kids.push({ type: "text",
      props: { text: "Topic: " + p.topic + " · Status: " + p.status } });
    kids.push({ type: "text",
      props: { text: "Deadline: " + formatDeadline(p.deadline) } });
    kids.push({ type: "text",
      props: {
        text: "Tally — Yes: " + formatBig(p.yes) + " (" + yesPct + "%) · " +
              "No: " + formatBig(p.no) + " (" + noPct + "%)" } });

    // ALPHA-Vote signal section (transparency / recommendation surface).
    var signalKids = p.alpha_signal.map(function (s) {
      return { type: "text", props: { text: s.label + ": " + s.vote_label } };
    });
    kids.push({
      type: "section",
      props: { title: "ALPHA-Vote signal" },
      children: signalKids,
    });

    // Vote buttons — the per-tap label IS the confirmation layer (the user
    // reads the proposal id + intent on the button before tapping).
    var canVote = state.neuron_id && state.neuron_id.length > 0 &&
        !state.action_in_flight;
    kids.push({
      type: "row",
      children: [
        buttonNode("Vote YES on #" + p.id,
            { type: "vote", proposal_id: p.id, vote: 1 }, !canVote),
        buttonNode("Vote NO on #" + p.id,
            { type: "vote", proposal_id: p.id, vote: 2 }, !canVote),
      ],
    });

    // Follow affordance: set-and-forget on this proposal's topic.
    kids.push(followSection(state, p));
    return {
      type: "section", props: { title: "Proposal #" + p.id }, children: kids,
    };
  }

  function followSection(state, p) {
    // Default the topic to the current proposal's topic int (parsed back from
    // the human label).
    var defaultTopic = FOLLOW_TOPICS[0].value;
    var parsedTopicInt = parseInt(String(p.topic).replace(/[^0-9].*$/, ""), 10);
    if (!isNaN(parsedTopicInt)) {
      var match = FOLLOW_TOPICS.find(function (t) {
        return Number(t.value) === parsedTopicInt;
      });
      if (match) defaultTopic = match.value;
    }
    var canFollow = state.neuron_id && state.neuron_id.length > 0 &&
        !state.action_in_flight;
    var quickFollowButtons = Object.keys(ALPHA_VOTE_NEURONS)
        .map(function (id) {
          return { id: id, label: ALPHA_VOTE_NEURONS[id] };
        })
        .concat([{ id: D_QUORUM_NEURON_ID, label: "D-QUORUM" }])
        .map(function (entry) {
      return buttonNode(
          "Follow " + entry.label + " on " + topicLabel(Number(defaultTopic)),
          { type: "follow", topic: defaultTopic, followee_id: entry.id },
          !canFollow);
    });
    return {
      type: "section",
      props: { title: "Follow on this topic (set-and-forget)" },
      children: [{ type: "row", children: quickFollowButtons }],
    };
  }

  // ───────────────────────── Generic helpers ──────────────────────────────
  // Compact node builders (DRY for the most-repeated view shapes).
  function buttonNode(label, onPress, disabled) {
    return {
      type: "button",
      props: { label: label, on_press: onPress, disabled: !!disabled },
    };
  }
  function selectNode(label, value, options, changeType) {
    return {
      type: "select",
      props: { label: label, value: value, options: options,
               on_change: { type: changeType } },
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
  function formatDeadline(epochSeconds) {
    var n = Number(epochSeconds || 0);
    if (n === 0) return "—";
    var delta = n - Math.floor(Date.now() / 1000);
    if (delta <= 0) return "closed";
    var days = Math.floor(delta / 86400);
    var hours = Math.floor((delta % 86400) / 3600);
    var mins = Math.floor((delta % 3600) / 60);
    if (days > 0) return days + "d " + hours + "h";
    if (hours > 0) return hours + "h " + mins + "m";
    return mins + "m";
  }

  // readEffect / setState / setStateShallow reused verbatim from
  // 08_nns_proposals.js.
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
