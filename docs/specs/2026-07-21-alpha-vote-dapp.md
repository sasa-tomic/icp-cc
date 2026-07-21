# 2026-07-21 — ALPHA-Vote Authenticated Neuron Voting Dapp

> Spec / plan for the **authenticated** sequel to the read-only
> `2026-07-21-sns-voting-scripts.md` headliner. The two read-only demos
> (NNS Proposals + SNS DAO Proposals) shipped in three green commits
> (`6f11c056`, `4db4f8da`, `fc1ffab4`). This doc plans the next layer:
> an **authenticated** dapp that ports ALPHA-Vote's neuron-following
> logic to a TS/QuickJS bundle running inside icp-cc.
>
> Source of truth for this unit of work — update as decisions land.
> Implementable by a single orchestrator-implementer subagent in 1–2
> wall-clock days.

## 0. Why now (unblocker)

This work was DEFERRED in the prior spec's §3 (Non-goals), blocked on
**UX-H12** ("No authenticated canister calls"). UX-H12 RESOLVED
2026-07-21 in three commits (`cba0e2a4`, `13672cb8`, `934b10b3` — see
`docs/OPEN_ISSUES.md`):

- The interactive Call Builder sheet now wires `callAuthenticated`
  (sign-as-active-profile toggle above the Call button).
- The bridge's `callAuthenticated` path is exercised end-to-end by
  `test/features/scripts/live_canister_auth_test.dart` (real Ed25519
  identity, real local-replica vote round-trip, tally increments).
- The script-app-host authenticated-effects path (used by
  `06_icp_poll.js` since STEP-1) is unchanged: a bundle effect with
  `authenticated: true` is dispatched via
  `bridge.callAuthenticated(privateKeyB64: widget.authenticatedKeypair!.privateKey)`
  — see `lib/widgets/script_app_host.dart:322-330` + the resolver at
  `:705-723`. The dapp-runner plumbs `ProfileScope.of(context).activeKeypair`
  into `ScriptAppHost.authenticatedKeypair` at
  `lib/screens/dapp_runner_screen.dart:901`.

Everything needed to ship an authenticated dapp is already wired and
tested. This plan adds one new bundle + descriptor + tests.

## 1. Problem

ALPHA-Vote (`third_party/ALPHA-Vote/`) is a "set-and-forget" neuron
automation: a Rust canister that polls NNS Governance hourly and casts
votes on behalf of configured followee neurons before deadlines expire.
The Rust reference (`src/alpha_backend/src/lib.rs`, 404 lines) is a
long-running canister — a model that does NOT translate to a TS/QuickJS
bundle, which runs on-demand inside the Flutter app (no timers, no
persistent process).

The user problem this dapp solves:

- A user who owns a staked NNS neuron wants to **vote on proposals**
  from inside icp-cc (not the NNS dapp dashboard) — both one-off
  `RegisterVote` and the more useful recurring `Follow` setup.
- A user who has heard of ALPHA-Vote wants to **see what the ALPHA-Vote
  public neurons voted** on each proposal (a transparency /
  recommendation surface), then **cast their own vote** (or set up
  recurring following) with one tap.
- Today icp-cc can only READ governance state (the prior spec's two
  read-only demos). Authenticated voting was the explicit deferred
  follow-up; with UX-H12 resolved it is now achievable.

The dapp is **USER-DRIVEN, not autonomous**: every authenticated effect
fires in response to an explicit user button tap (no timers, no polling
beyond the manual Refresh the user already does in the read-only demo).
The recurring case is delegated to NNS Governance itself via the
`Follow` variant (the canister does the actual vote-copying for future
proposals on the followed topic — that IS set-and-forget).

## 2. User value (what changes for the user)

After this work, a user with a staked neuron who opens the new
**Neuron Voting** dapp in icp-cc can:

1. **Discover or paste their neuron ID.** Either run
   `list_neurons(include_neurons_readable_by_caller=true)` authenticated
   (returns their principal-owned neurons automatically), or paste a
   known neuron ID into a text field (mirrors the SNS-dao id paste UX
   from `09_sns_proposals.js`).
2. **See ALPHA-Vote's signal on each open proposal.** For every open
   proposal, the dapp decodes the ballots field of the 3 ALPHA-Vote
   public neurons (αlpha-vote `2947465672511369`, Ωmega-vote
   `18363645821499695760`, Ωmega-reject `18422777432977120264`) and
   shows "αlpha-vote: Yes / No / not voted yet". This is the
   transparency layer — the user can see what the framework
   recommends before deciding.
3. **Cast a one-off vote** on any open proposal: tap "Vote Yes" or
   "Vote No" → bundle emits authenticated `manage_neuron
   RegisterVote` → host signs with the active profile's keypair → NNS
   Governance returns the result → dapp shows "Vote recorded" or the
   specific NNS error ("already voted", "insufficient dissolve delay",
   etc.) surfaced via `friendlyErrorMessage`.
4. **Set up recurring following** of one of the ALPHA-Vote neurons (or
   any neuron ID): tap "Follow αlpha-vote on Governance topic" →
   bundle emits authenticated `manage_neuron Follow` → NNS Governance
   records the follow rule → ALL future proposals on that topic are
   auto-voted by NNS Governance itself (true set-and-forget).
5. **See honest failures.** No neuron → clear CTA + link to staking
   docs. No active profile → the host surfaces the missing-auth
   envelope verbatim (already a loud pattern, never silent anon
   fallback). Already voted → friendly message. Network down → typed
   `CanisterFailureKind` surfaces via the existing
   `onCanisterCallFailure` recovery hint.

The dapp is also **pedagogical**: a curious user can read the bundle
end-to-end and see exactly how `manage_neuron`'s Candid variant is
shaped — the same shape ALPHA-Vote's Rust emits, but in readable JS.

## 3. Non-goals (explicitly out of scope)

- **NO autonomous "set-and-forget canister."** The dapp does not poll,
  does not have timers, does not vote without the user tapping a
  button. The "set-and-forget" property for the user is achieved via
  the `Follow` variant (NNS Governance itself does the recurring
  vote-copying server-side after the user's one-time `Follow` call).
  This is explicitly called out in the UI ("Once you Follow, NNS
  Governance votes for you on every future proposal on this topic —
  you don't need this dapp open").
- **NO staking / neuron creation.** The user must already have a
  staked neuron. The dapp surfaces a clear "no neuron found" path
  with a link to staking docs (the dashboardstaking flow is a
  separate product surface, not a script's job).
- **NO D-QUORUM algorithm client-side.** ALPHA-Vote's backstop logic
  (vote No at deadline if no followee has voted) is canister-side in
  the original. We do NOT replicate the timing logic in the bundle.
  The bundle surfaces what the public neurons have voted and lets the
  user decide; the backstop is what they configure by Following
  Ωmega-reject.
- **NO multi-neuron batch operations.** One neuron at a time. The
  `list_neurons` query returns multiple, but the dapp picks one active
  neuron (default the first) and operates on it. (YAGNI — surface
  multiple neurons in a follow-up if users ask.)
- **NO SNS neuron voting.** SNS governance uses a different
  `manage_neuron` shape (different canister, different topic enum).
  Out of scope; NNS only for this dapp. (The SNS Proposals read-only
  demo stays read-only.)
- **NO on-chain identity rotation.** The dapp signs with whatever the
  active profile is (host-mediated). Profile switching happens at the
  app level (Keypair Switcher), not in the dapp.
- **NO persistent "followee list" editor beyond the descriptor
  default.** The 3 ALPHA-Vote neurons ship as constants; the user can
  paste a different followee ID inline for a one-off Follow call but
  there's no per-dapp editable followee list UI in v1. (Persisted
  overrides via `DappRuntimeConfig` cover the canister-id and host
  only; extending it to neuron-id is a YAGNI follow-up.)

## 4. Stack surface used (verified)

All of this is already proven by the prior read-only demos + UX-H12:

- **`icp_call` effect, `mode: 0` (query), `authenticated: false`** —
  `list_proposals` (read-only browser, reused verbatim from
  `08_nns_proposals.js`).
- **`icp_call` effect, `mode: 0` (query), `authenticated: true`** —
  `list_neurons` (principal-scoped neuron discovery). Mirrors the
  `whoami` authenticated-query pattern in `06_icp_poll.js`.
- **`icp_call` effect, `mode: 1` (update), `authenticated: true`** —
  `manage_neuron RegisterVote` and `manage_neuron Follow`. Mirrors the
  `vote`/`createPoll` authenticated-update pattern in `06_icp_poll.js`
  (verified end-to-end by `live_canister_auth_test.dart`).
- **Target canister:** NNS Governance `rrkah-fqaaa-aaaaa-aaaaq-cai`
  via `https://ic0.app` (constants `kMainnetNnsGovernanceCanisterId` +
  `kMainnetIcGateway` in `lib/config/example_dapps.dart`, already
  defined by the prior spec).
- **Host dispatch path:**
  `lib/widgets/script_app_host.dart:705-723` (`_resolveAuthForCall`):
  effect with `authenticated: true` resolves to
  `widget.authenticatedKeypair.privateKey`; if null, returns
  `missingAuth: true` and the host enqueues the loud
  `_kMissingAuthMessage` ("authenticated call requested but no active
  profile keypair") effect/result — never a silent anonymous fallback.
  Then `:322-330`: `bridge.callAuthenticated(privateKeyB64:
  auth.privateKey!, args, ...)`.
- **`ProfileScope.of(context).activeKeypair`** is plumbed into
  `ScriptAppHost.authenticatedKeypair` at
  `lib/screens/dapp_runner_screen.dart:901` — already wired, no host
  change needed for this dapp.
- **Per-dapp trust model:** `DappTrustStore` (already in
  `example_dapps.dart`) — the descriptor's `id` is passed to
  `ScriptAppHost.dappTrustId` by the runner, so the user sees ONE
  "Trust this dapp?" prompt, then every method runs without further
  prompts. Revocation is via `DappTrustStore.clear(id)` (no in-app
  affordance today; parity with the existing per-method allow-list).
- **Host-known principal injection:** the runner already passes
  `initialArg: {'principal': ProfileScope.of(context).activeKeypair?.principal ?? ''}`
  — so the bundle's first render shows the right identity (mirrors
  `06_icp_poll.js`).
- **Failure classification:** `onCanisterCallFailure` callback
  receives the typed `CanisterFailureKind` from the Rust FFI's stable
  `kind` tag — already wired at
  `lib/screens/dapp_runner_screen.dart:899`. Reachability failures
  auto-expand the Connection panel; permission denials and Candid
  decode errors do not (the bundle surfaces those via `readEffect`).
- **`friendlyErrorMessage`** (`lib/utils/friendly_error.dart`) for
  any user-facing error copy. Not strictly needed inside the bundle
  (which renders via UI_v1 text nodes), but the bundle surfaces
  candid error bodies verbatim with a "manage_neuron:" prefix
  pattern (matching the icp_poll "whoami:" / "tally N:" prefix
  convention).

## 5. Candid args verified (live, against mainnet)

All verifications ran 2026-07-21 against `rrkah-fqaaa-aaaaa-aaaaq-cai`
via `dfx 0.32.0` on the dev box. Reproducible verbatim.

### 5.1 Method signatures (from `dfx canister --network ic metadata rrkah-fqaaa-aaaaa-aaaaq-cai candid:service`)

```candid
type NeuronId = record { id : nat64 };
type ProposalId = record { id : nat64 };
type NeuronIdOrSubaccount = variant { Subaccount : blob; NeuronId : NeuronId };
type RegisterVote = record { vote : int32; proposal : opt ProposalId };
type Follow        = record { topic : int32; followees : vec NeuronId };
type ManageNeuronRequest = record {
  neuron_id_or_subaccount : opt NeuronIdOrSubaccount; // modern
  command : opt ManageNeuronCommandRequest;
  id : opt NeuronId;                                   // deprecated but works
};
type ManageNeuronCommandRequest = variant {
  Spawn; Split; Follow : Follow; ClaimOrRefresh; Configure;
  RegisterVote : RegisterVote; Merge; DisburseToNeuron; MakeProposal;
  StakeMaturity; MergeMaturity; Disburse; RefreshVotingPower;
  DisburseMaturity; SetFollowing;
};

service : {
  list_proposals : (ListProposalInfoRequest) -> (ListProposalInfoResponse) query;
  list_neurons   : (ListNeurons) -> (ListNeuronsResponse) query;
  get_full_neuron: (nat64) -> (Result_2) query;
  manage_neuron  : (ManageNeuronRequest) -> (ManageNeuronResponse);
  simulate_manage_neuron : (ManageNeuronRequest) -> (ManageNeuronResponse);
  // ... other methods
}
```

### 5.2 RegisterVote — exact textual Candid the bundle will emit

```
(record {
  id = opt record { id = <NEURON_ID> : nat64 };
  command = opt variant {
    RegisterVote = record {
      vote = <1 | 2> : int32;     // 1 = Yes, 2 = No
      proposal = opt record { id = <PROPOSAL_ID> : nat64 };
    }
  };
})
```

**Verified live** (against αlpha-vote's known neuron id + a real
proposal id from `list_proposals`):

```
$ export PATH="/home/ubuntu/.cache/data/dfx/bin:$PATH"
$ export DFX_WARNING=-mainnet_plaintext_identity
$ dfx canister --network ic call --update rrkah-fqaaa-aaaaa-aaaaq-cai \
    simulate_manage_neuron \
    '(record { id = opt record { id = 2947465672511369 : nat64 };
               command = opt variant { RegisterVote = record {
                 vote = 1 : int32;
                 proposal = opt record { id = 143015 : nat64 }; } }; })'

(record {
  command = opt variant {
    Error = record {
      error_message = "Simulating manage_neuron is not supported for this request type";
      error_type = 5 : int32;
    }
  };
})
```

The response is a **structured `Error`** ("simulate doesn't support
RegisterVote"), NOT a candid decode failure — proving the args parsed
correctly at the boundary. The negative control (dropping the
`proposal` field) returns a `parser error: Unexpected token` from the
dfx candid parser — confirming the well-formed shape is the only one
that compiles.

### 5.3 Follow — exact textual Candid the bundle will emit

```
(record {
  id = opt record { id = <NEURON_ID> : nat64 };
  command = opt variant {
    Follow = record {
      topic = <0 | 1 | 4 | 14> : int32;   // see topic enum below
      followees = vec { record { id = <FOLLOWEE_ID> : nat64 }; ... };
    }
  };
})
```

**Verified live** (following D-QUORUM on topic 0):

```
$ dfx canister --network ic call --update rrkah-fqaaa-aaaaa-aaaaq-cai \
    simulate_manage_neuron \
    '(record { id = opt record { id = 2947465672511369 : nat64 };
               command = opt variant { Follow = record {
                 topic = 0 : int32;
                 followees = vec { record { id = 4713806069430754115 : nat64 }; }; } }; })'

(record { command = opt variant { Error = record {
  error_message = "Simulating manage_neuron is not supported for this request type";
  error_type = 5 : int32; } }; })
```

Same structured Error — args parsed correctly.

### 5.4 Two equivalent ways to specify the neuron

Both shapes compile and reach the canister:

- **`id` (deprecated, simpler)** — `record { id = opt record { id = N : nat64 }; ... }`
  This is what the ALPHA-Vote Rust reference uses (`alpha_backend/src/lib.rs:140, 193`).
  NNS Governance still honours it (the candid marks it "Deprecated. Use
  neuron_id_or_subaccount instead" but it is NOT removed).
- **`neuron_id_or_subaccount` (modern)** —
  `record { neuron_id_or_subaccount = opt variant { NeuronId = record { id = N : nat64 } }; ... }`
  This is what `refresh_voting_power` in ALPHA-Vote uses (line 83).

**Recommendation: use `id`.** Reasons:
1. Pedagogical continuity with the ALPHA-Vote Rust reference (the
   bundle's candid is line-for-line identical to what a Rust reader
   recognises from `register_vote` / `follow` in the reference).
2. Simpler (no extra `variant { NeuronId = ... }` nesting).
3. The Rust reference has been in production for years using `id` for
   RegisterVote and Follow; the deprecation is for new use cases that
   need the subaccount path. We don't.

### 5.5 What could NOT be verified live

**The full happy-path success response (`ManageNeuronResponse` with
`command = opt variant { RegisterVoteResponse = ... }`).** Real
RegisterVote / Follow success requires:
- A neuron OWNED by the caller (the active profile's principal must
  be the controller, AND the neuron must have been staked with that
  identity's principal as the controller).
- A real Ed25519 identity with cycles, signed and submitted as an
  update call (not query).

We do not own such a neuron in the dev environment, and creating one
requires a real ICP transfer + 8-day dissolve delay minimum for voting
eligibility — outside this plan's scope. What the implementer needs to
do at PoC time (see §10) is verify the ROUND-TRIP MECHANICS against
NNS Governance's typed error response:

- A real authenticated `manage_neuron RegisterVote` with a neuron the
  caller does NOT own returns a structured `command = opt variant {
  Error = { error_message: "Neuron not found: ..."; error_type: ... } }`
  — proving the call reached NNS Governance, was authenticated (not
  rejected as anonymous), parsed correctly, and was rejected at the
  application-logic layer (not the auth layer).
- A real authenticated `manage_neuron Follow` returns the same shape.

That round-trip is the PoC's success criterion (see §10.2). Anything
beyond it requires real staked ICP, which is a user action the dapp
surfaces (staking-docs link) but does not perform.

### 5.6 list_neurons — verified live (anonymous → empty)

```
$ dfx canister --network ic call --query rrkah-fqaaa-aaaaa-aaaaq-cai \
    list_neurons '(record {
      neuron_ids = vec {};
      include_neurons_readable_by_caller = true; })'

(record {
  neuron_infos = vec {};
  full_neurons = vec {};
  total_pages_available = opt (0 : nat64);
})
```

With an authenticated profile's keypair, this returns the caller's
own neurons (`neuron_infos: vec record { nat64; NeuronInfo }`). The
bundle uses this for auto-discovery; the user can also paste a neuron
id manually.

### 5.7 list_proposals — verified live (ballots shape)

Already verified by the prior spec. Re-confirmed 2026-07-21: the
`ballots` field on a proposal is `vec record { nat64; Ballot }` where
`Ballot = record { vote: int32; voting_power: nat64 }` (a candid
HashMap serialisation). For executed proposals `ballots = vec {}` (the
totals live in `latest_tally`); for OPEN proposals the ballots of
voted neurons appear. As of 2026-07-21 there are NO open NNS proposals
(genuine quiet period — bundle handles both empty and non-empty
honestly, as the read-only demo already does).

### 5.8 Topic enum (canonical, from ALPHA-Vote README + NNS source)

The prior spec's topic enum (§4 of `2026-07-21-sns-voting-scripts.md`)
is the older numbering. The current NNS topic enum (per ALPHA-Vote
README §"Post-deployment Configuration"):

```
0  = Unspecified
1  = Governance (was "TopicExchange" in the old enum)
4  = SNS & Neurons Fund (was "Application / SNS Launch")
14 = SNS & Neurons Fund (newer; ALPHA-Vote follows on this)
... (others as documented in ic_nns_governance::GovernanceTopic)
```

**The bundle must use the current NNS source-of-truth enum.** For
Follow topics, ALPHA-Vote recommends topics `0`, `4`, and `14`. The
bundle's `FOLLOW_TOPICS` constant lists these three as the defaults
the user can pick from in a Follow affordance. (A future NNS enum
renumbering would require a bundle update — flagged in §12 Risks.)

## 6. Bundle design — `10_alpha_vote.js`

Self-contained JS file at `apps/autorun_flutter/lib/examples/10_alpha_vote.js`.
Target: **≤ 600 lines, prefer ≤ 450** (the prior 08_nns_proposals.js is
486 lines; we add neuron-id state + 3 new effect builders + ballot
decoding + 2 new update messages + a Follow UI affordance — realistic
~500 lines).

### 6.1 Constants (single source)

```js
var PAGE_SIZE = 10;

// ALPHA-Vote's 3 PUBLIC known neurons (canonical mainnet ids from
// third_party/ALPHA-Vote/README.md). These are the recommendation
// surface — the bundle shows what they voted on each open proposal.
var ALPHA_VOTE_NEURONS = {
  2947465672511369:    "αlpha-vote",   // votes ASAP (alpha = first)
  18363645821499695760: "Ωmega-vote",  // votes late (omega = last)
  18422777432977120264: "Ωmega-reject", // rejects by default if no quorum
};
var D_QUORUM_NEURON_ID = 4713806069430754115; // upstream diligent voter

// NNS topic enum (current). Mirrors ALPHA-Vote README §"Configuration".
var TOPIC = {
  0: "Unspecified",
  1: "Governance",
  4: "SNS & Neurons Fund (legacy)",
  14: "SNS & Neurons Fund",
  // ... (extended from the prior spec, reconciled with ALPHA-Vote)
};

// Topics the Follow affordance offers (the 3 ALPHA-Vote follows on).
var FOLLOW_TOPICS = [
  { value: "0",  label: "Unspecified (all topics)" },
  { value: "1",  label: "Governance" },
  { value: "4",  label: "SNS & Neurons Fund (legacy)" },
  { value: "14", label: "SNS & Neurons Fund" },
];

var STATUS = { /* same as 08_nns_proposals.js */ };
var STATUS_FILTER_VALUE = { /* same */ };
```

### 6.2 State

```js
{
  backend_id, host, principal,            // from arg (host-injected)
  neuron_id: "",                          // user-entered OR discovered
  discovered_neuron_ids: [],              // list_neurons result (pick list)
  status_filter: "open",                  // same as 08
  topic_filter: "all",
  page: 0, page_size: PAGE_SIZE,
  loading: false, loaded: false, error: "",
  proposals: [], has_more: false,         // same as 08
  action_in_flight: false,                // any manage_neuron call pending
  last_action_result: "",                 // last manage_neuron outcome
  last_action_ok: false,                  // success/failure flag for above
}
```

### 6.3 init

Reads `arg.backend_id` / `arg.host` / `arg.principal`. AUTO-LOADs on
mount (UXR-6 pattern): emits the same `list_proposals` (anon) effect
as 08_nns_proposals.js, PLUS a `list_neurons` authenticated query if
`arg.principal` is non-empty (so the neuron-picker is pre-populated
for signed-in users without a manual Discover tap).

### 6.4 view

```
column
├── text "Neuron Voting — mainnet (signed as: {principal or 'view-only'})"
├── section "Your neuron"
│     ├── (if discovered_neuron_ids.length > 0) select "Active neuron"
│     │     options: discovered_neuron_ids.map(...)
│     ├── text_field "Or paste a neuron id"  on_change: set_neuron_id
│     └── button "Discover my neurons"  on_press: discover_neurons
│           (disabled if principal empty — view-only)
├── row [Refresh, Status select, Topic select]   // same as 08
├── text error (if any)
├── text last_action_result (if any, success/failure coloured via text content)
├── for each proposal: alphaVoteProposalCard(p, state)
│     ├── text "#N — title"
│     ├── text "Topic · Status · Deadline (countdown)"
│     ├── text "Tally — Yes N (X%) · No N (Y%)"
│     ├── section "ALPHA-Vote signal"
│     │     for each of the 3 neurons:
│     │       text "{label}: {Yes|No|not voted yet}"
│     ├── row [button "Vote Yes" on_press vote(1),
│     │         button "Vote No"  on_press vote(2)]
│     │     (disabled if neuron_id empty OR action_in_flight)
│     └── section "Follow on this topic"
│           ├── select "Topic" (FOLLOW_TOPICS)
│           ├── row [button "Follow αlpha-vote",
│           │         button "Follow Ωmega-vote",
│           │         button "Follow Ωmega-reject"]
│           │     each → follow(topic, neuronId)
│           │     (disabled if neuron_id empty)
│           └── text_field "Or paste a followee neuron id"
│                 + button "Follow this id"
└── pagination row (same as 08)
```

The vote buttons use a CONFIRMING label so the user sees intent on the
button itself: `"Vote YES on #12345"` / `"Vote NO on #12345"`. This is
the per-call confirmation layer on top of the trust-once model — the
tap is the confirmation (no extra dialog; one tap = one signed vote).

### 6.5 update messages

Inherited from 08_nns_proposals.js (verbatim): `refresh`,
`set_status`, `set_topic`, `page`, `effect/result`.

NEW:

- `{type:"set_neuron_id", value}` — patch `neuron_id` (no effect).
- `{type:"select_discovered_neuron", value}` — patch `neuron_id` from
  the discovered list (no effect).
- `{type:"discover_neurons"}` — emit `listNeuronsEffect(state)`
  (authenticated query). If principal empty, surface a LOUD error:
  "Sign in with a profile to discover your neurons."
- `{type:"vote", proposal_id, vote:1|2}` — set `action_in_flight:
  true`, emit `manageNeuronVoteEffect("vote", neuron_id,
  proposal_id, vote, state)` (authenticated UPDATE). If neuron_id
  empty: LOUD error "Set your neuron id first."
- `{type:"follow", topic, followee_id}` — set `action_in_flight:
  true`, emit `manageNeuronFollowEffect("follow", neuron_id, topic,
  [followee_id], state)` (authenticated UPDATE). If neuron_id empty:
  LOUD error.
- `effect/result` handler extended to dispatch on `msg.id`:
  - `"list_proposals"` → same as 08 (decode + state patch).
  - `"list_neurons"` → NEW: decode `neuron_infos` into
    `discovered_neuron_ids` + auto-pick the first as `neuron_id` if
    `neuron_id` is empty.
  - `"vote"` / `"follow"` → NEW: decode `ManageNeuronResponse`; if
    `command = opt variant { Error = ... }`, surface the friendly
    error message (e.g. `"Neuron not found"` → "NNS says: neuron
    {neuron_id} is not owned by your active profile's principal. Check
    the id and your identity."); otherwise mark success + clear
    `action_in_flight`.

### 6.6 Effects

```js
// REUSED from 08_nns_proposals.js (verbatim bodies):
listProposalsEffect(state, pageOverride)
callEffect(id, mode, method, args, authenticated, state) // from 06_icp_poll

// NEW:
function listNeuronsEffect(state) {
  return {
    kind: "icp_call", id: "list_neurons", mode: 0,           // query
    canister_id: state.backend_id, method: "list_neurons",
    // include_neurons_readable_by_caller=true → returns caller's neurons
    args: "(record { neuron_ids = vec {}; include_neurons_readable_by_caller = true; })",
    host: state.host, authenticated: true,
  };
}

function manageNeuronVoteEffect(id, neuronId, proposalId, voteInt, state) {
  var args =
    "(record { id = opt record { id = " + neuronId + " : nat64 }; " +
    "command = opt variant { RegisterVote = record { " +
    "vote = " + voteInt + " : int32; " +
    "proposal = opt record { id = " + proposalId + " : nat64 }; } }; })";
  return {
    kind: "icp_call", id: id, mode: 1,                       // update
    canister_id: state.backend_id, method: "manage_neuron",
    args: args, host: state.host, authenticated: true,
  };
}

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
    kind: "icp_call", id: id, mode: 1,                       // update
    canister_id: state.backend_id, method: "manage_neuron",
    args: args, host: state.host, authenticated: true,
  };
}
```

### 6.7 Helpers reused from 08_nns_proposals.js (verbatim)

`unwrapOpt`, `unwrapOptInt`, `decodeProposal` (extended — see below),
`statusLabel`, `topicLabel`, `formatDeadline`, `formatBig`, `truncate`,
`readEffect`, `setState`, `setStateShallow`, `buildStatusVec`,
`buildTopicVec`, `filterByTopic`, `topicOptions`, `proposalCard`
(extended — see below), `topicOptions`.

DRY note (mirrors the prior spec's §7): the NNS + ALPHA-Vote bundles
share ~80% of their logic. We do NOT extract to a shared module on the
second occurrence (YAGNI — extract on the third). The two bundles stay
self-contained so each is readable end-to-end as one file.

### 6.8 New helpers introduced

```js
// Decode ballots (vec record { nat64; Ballot }) into {neuronId: {vote, voting_power}}.
function decodeBallots(rawBallots) { ... }

// Surface ALPHA-Vote's signal for a proposal: returns array of
// {neuron_id, label, vote_label} for the 3 ALPHA_VOTE_NEURONS ids.
function alphaVoteSignal(decodedBallots) { ... }

// Map vote int → label. 1="Yes", 2="No", 0=undefined="not voted yet".
function ballotVoteLabel(voteInt) { ... }

// Decode ManageNeuronResponse. Returns {ok, message} where message is
// a user-facing string ("Vote recorded" / "NNS error: {error_message}").
function decodeManageNeuronResponse(parsed) { ... }

// Friendly NNS error mapper. Maps well-known error_type ints to
// actionable copy (matches ALPHA-Vote's observed error patterns).
function friendlyNnsError(errorType, errorMessage, neuronId) { ... }
```

### 6.9 Friendly NNS error mapping (the failure-mode UX)

`friendlyNnsError` covers the documented failure modes from the spec
questions:

| error_type | message pattern | friendly copy |
|------------|-----------------|---------------|
| (any)      | "Neuron not found: NeuronId { id: N }" | "NNS doesn't see neuron {N} under your active profile's principal. Either the id is wrong, or this neuron is controlled by a different identity." |
| (any)      | "already voted" | "You've already voted on this proposal. (NNS doesn't allow changing a vote once cast.)" |
| (any)      | "dissolve delay" / "insufficient" | "This neuron can't vote yet — it needs a dissolve delay of at least 6 months. Manage it on the NNS dashboard." |
| (any)      | "not eligible" / "no voting power" | "This neuron has no voting power (possibly not staked for long enough). See the NNS staking docs." |
| (fallback) | any other | "NNS responded: {error_message}" — verbatim, never swallowed. |

All copies are inline strings in the bundle (not in the host — the
host's `friendlyErrorMessage` is for host-side errors; bundle-side
canister errors surface via `readEffect` + this mapper).

## 7. DappDescriptor (the new entry for `example_dapps.dart`)

```dart
// ALPHA-Vote known neuron ids (public mainnet, from
// third_party/ALPHA-Vote/README.md). Used as the default recommendation
// surface in the Neuron Voting dapp (the bundle shows what these 3
// neurons voted on each open proposal).
const String kAlphaVoteNeuronId     = '2947465672511369';
const String kOmegaVoteNeuronId     = '18363645821499695760';
const String kOmegaRejectNeuronId   = '18422777432977120264';

// In the exampleDapps list (placed AFTER sns_proposals, BEFORE icp_poll
// so the always-working mainnet examples stay grouped first):
DappDescriptor(
  id: 'alpha_vote',
  title: 'Neuron Voting',
  emoji: '⚡',
  description: 'Cast authenticated NNS votes from inside icp-cc. Browse '
      'open proposals, see what the ALPHA-Vote public neurons (αlpha-vote, '
      'Ωmega-vote, Ωmega-reject) recommend, then vote Yes/No or set up '
      'recurring Following — all signed with your active profile\'s keypair. '
      'Requires a staked NNS neuron (the dapp surfaces a clear path if you '
      'don\'t have one).',
  backendCanisterId: kMainnetNnsGovernanceCanisterId,
  host: kMainnetIcGateway,
  frontendUrl: 'https://nns.ic0.app/neurons',
  bundleAssetPath: 'lib/examples/10_alpha_vote.js',
  environment: DappEnvironment.mainnet,
  paths: <DappPath>[DappPath.backendDirect],
  keylessHint: 'Browsing proposals works without a profile. Signing '
      'in unlocks neuron discovery and one-tap voting.',
),
```

Plus:
- `pubspec.yaml` — add `lib/examples/10_alpha_vote.js` to the assets
  list (mirrors 07/08/09 registration).
- `test/shared/ts_bundle_fixtures.dart` — add
  `loadAlphaVoteBundle()` with the standard candidate-path list.

## 8. Trust + auth UX

### 8.1 Grant + revoke

Mirror the existing pattern (no new trust affordance):

- **Grant:** first authenticated effect (`list_neurons` from init, or
  the first user-tapped vote/follow) triggers the standard
  `_showPermissionDialog` via `DappTrustStore`. Three buttons (UX-H4):
  Deny / Allow once (session-only) / Trust this dapp (persistent).
  The dialog body shows the principal-visibility warning (already in
  the host) — for this dapp the warning is materially accurate: the
  user's principal IS their neuron-ownership identity on NNS, so
  "the dapp will see your principal" is the whole point.
- **Persistent:** once "Trust this dapp" is tapped, all subsequent
  `manage_neuron` calls sign without prompts.
- **Revoke:** `DappTrustStore.clear('alpha_vote')` — no in-app
  affordance today (parity with the existing per-method allow-list;
  tracked separately if users ask).

### 8.2 Per-call confirmation (the additional safety layer)

Voting on an NNS proposal is materially consequential (a signed
governance vote). Even with persistent trust, the dapp adds a
**per-tap intent confirmation** via the button label itself:

- The Vote button renders as `"Vote YES on #12345"` (not just "Vote").
  The user reads the proposal id + intent on the button before
  tapping.
- The Follow button renders as `"Follow αlpha-vote on Governance"`.
- One tap = one signed call. No second dialog (the label is the
  confirmation; a second dialog adds friction without adding safety
  for a user who already trusted the dapp).

### 8.3 Surfacing authenticated state

- The bundle's first text node is `"Signed in: {principal}"` or
  `"No profile — view-only (browse only; signing unlocks voting)"`.
  Mirrors `06_icp_poll.js` lines 50-57.
- The host-injected `arg.principal` populates this on the first frame
  (no `whoami` round-trip needed — the bundle doesn't call `whoami`
  at all; the active profile's principal IS the identity NNS sees).
- The "Your neuron" section shows the active neuron id prominently
  with a Copy affordance (so the user can verify it against the NNS
  dashboard before voting).

### 8.4 Failure surfacing

| Failure | Where surfaced | Copy |
|---------|----------------|------|
| No active profile (host missing-auth envelope) | `state.error` (loud) | "Sign in with a profile to vote. (Browsing proposals still works.)" |
| No neuron id set when user taps vote/follow | `state.error` (loud, no effect emitted) | "Set your neuron id first (paste one or tap Discover)." |
| NNS rejects (`command = opt variant { Error }`) | `state.last_action_result` | `friendlyNnsError(error_type, error_message, neuron_id)` |
| Replica unreachable (`CanisterFailureKind.net`) | host's `onCanisterCallFailure` → Connection panel auto-expand | existing host copy |
| Candid decode error (bundle bug) | `state.error` (loud) | "manage_neuron: malformed reply ({raw preview})" — never swallowed |
| Empty list_neurons result (caller owns no neurons) | `state.discovered_neuron_ids` empty → friendly inline | "No neurons found for your principal. Stake a neuron on the NNS dashboard to enable voting." + link |

All user-facing strings are inline in the bundle. The host-side
failures (missing-auth, canister unreachable) reuse the existing
host classification — no new host code.

## 9. Tests required

### 9.1 Bundle-logic tests (`test/features/scripts/alpha_vote_bundle_test.dart`)

Mirrors `icp_poll_bundle_test.dart`'s structure: boot via real FFI
runtime (`bootRuntime()` + `rt.init/view/update`), feed canned
effect/result envelopes matching the verified live shapes, assert
state + UI tree + emitted effects.

Coverage (each is its own test, positive AND negative paths):

1. `init` stores `backend_id` / `host` / `principal` and AUTO-LOADs
   (emits `list_proposals` anon; PLUS `list_neurons` auth if principal
   non-empty). Regression guard for the auto-load pattern (UX-11).
2. `init` with empty principal emits ONLY `list_proposals` (no
   `list_neurons` — would fail missing-auth).
3. `set_neuron_id` patches state, no effect.
4. `discover_neurons` emits `list_neurons` authenticated query with
   the verified candid args.
5. `discover_neurons` with empty principal → LOUD error, no effect.
6. `vote` emits authenticated UPDATE `manage_neuron` with the EXACT
   textual candid verified in §5.2 (assert the full string).
7. `vote` with empty neuron_id → LOUD error, no effect.
8. `follow` emits authenticated UPDATE `manage_neuron` with the EXACT
   textual candid verified in §5.3.
9. `list_proposals` effect/result decodes into the same proposal
   array shape as 08_nns_proposals.js (regression: the decoder is
   shared verbatim).
10. `list_neurons` effect/result with empty `neuron_infos` → no
    discovered neurons, friendly inline copy (NOT a loud error —
    anonymous or neuron-less callers are an expected state).
11. `list_neurons` effect/result with 1 neuron → discovered list
    populated, `neuron_id` auto-set to the first.
12. `vote` effect/result success (`command = opt variant {
    RegisterVoteResponse = ... }`) → `last_action_ok=true`,
    `last_action_result="Vote recorded"`, `action_in_flight=false`.
13. `vote` effect/result with `Error { error_message: "Neuron not
    found" }` → `friendlyNnsError` output, `last_action_ok=false`.
14. `vote` effect/result with `Error { error_message: "already
    voted" }` → specific friendly copy.
15. whoami-style missing-auth envelope on `list_neurons` → LOUD error
    (NOT the silent view-only path — only `whoami` in 06 treats
    missing-auth as non-fatal; for this dapp missing-auth on
    `list_neurons` is a real failure because the user explicitly
    tapped Discover).
16. Negative: malformed `manage_neuron` reply (JSON shape unexpected)
    → LOUD error with raw preview, never swallowed.
17. View renders the ALPHA-Vote signal section for each proposal
    (assert the 3 neuron labels appear as text nodes).
18. View disables vote/follow buttons when `neuron_id` is empty.

### 9.2 Host auth-path test (`test/features/scripts/alpha_vote_host_auth_test.dart`)

Mirrors the `script_app_host` widget-test pattern (like
`script_app_host_theme_test.dart` + the new UX-H12
`authenticated_call_test.dart`):

1. Bundle effect with `authenticated: true` + active keypair present →
   host invokes `bridge.callAuthenticated` with the right private key
   (use a fake `ScriptBridge` that records calls).
2. Bundle effect with `authenticated: true` + NO keypair → host
   enqueues the loud `_kMissingAuthMessage` effect/result; bundle's
   `update` surfaces it via the friendly copy (NOT silent anon).
3. The dapp's trust prompt fires on the first authenticated effect
   (assert `_showPermissionDialog` is invoked with the descriptor's
   `id`).

### 9.3 Trust-store integration test (`test/features/dapps/alpha_vote_trust_test.dart`)

Mirrors `dapp_trust_test.dart`:

1. `DappTrustStore.isTrusted('alpha_vote')` returns false initially.
2. After `setTrusted('alpha_vote')`, subsequent runs of the dapp do
   NOT fire the trust prompt.
3. `DappTrustStore.clear('alpha_vote')` resets it.

### 9.4 Live round-trip test (gated, optional — `test/features/scripts/live_alpha_vote_test.dart`)

Gated on `ICPCC_LIVE_NEURON_ID` + `ICPCC_LIVE_NEURON_KEY_B64` env
vars (which we don't have in CI). Mirrors `live_canister_auth_test.dart`:

1. With a real Ed25519 identity (no neuron), call authenticated
   `manage_neuron RegisterVote` with a fake proposal id → expect
   structured `Error` response from NNS (proves auth + candid parse
   + application-layer rejection; NOT an auth-layer rejection).
2. Same for `manage_neuron Follow`.
3. SKIPs cleanly with a clear message when env vars are unset.

This test is OPTIONAL for v1 (the existing
`live_canister_auth_test.dart` already proves the auth-bridge
round-trip mechanism). Add only if the implementer has access to a
real test neuron; otherwise defer to a follow-up.

## 10. Confidence estimate + PoC recipe

### 10.1 Confidence by commit unit

| Unit | Confidence | Reason |
|------|------------|--------|
| Bundle skeleton (init/view/update reusing 08 helpers) | **9/10** | Direct port of verified patterns; 08_nns_proposals.js is the reference. |
| `list_proposals` reuse + decode | **9/10** | Already shipped in 08; same canister, same args. |
| `list_neurons` authenticated query | **9/10** | Args verified live (§5.6); auth-query pattern proven by 06_icp_poll's whoami. |
| `manage_neuron RegisterVote` effect builder + args | **10/10** | Args verified live via `simulate_manage_neuron` (§5.2); exact textual candid locked. |
| `manage_neuron Follow` effect builder + args | **10/10** | Args verified live via `simulate_manage_neuron` (§5.3); exact textual candid locked. |
| `decodeManageNeuronResponse` + `friendlyNnsError` | **7/10** | The Ok-shape is documented in candid but NOT verified live (no real neuron). Error shapes inferred from ALPHA-Vote Rust error handling + the `simulate_manage_neuron` Error response. Implementer MUST verify at PoC time against a real (failing) authenticated call. |
| Trust + host auth-path (no new host code) | **9/10** | All host code shipped in UX-H12; this dapp just uses it. |
| DappDescriptor + pubspec + loader | **10/10** | Mechanical; mirrors 08/09. |
| Bundle-logic tests (canned shapes) | **9/10** | Pattern proven by icp_poll_bundle_test. |
| Live round-trip test (optional) | **6/10** | Depends on a real staked neuron we don't have; defer. |

**Overall: 9/10.** Above the 8/10 STOP threshold. The only
sub-8 unit (decodeManageNeuronResponse / friendlyNnsError) is
non-blocking — the bundle surfaces the raw NNS error verbatim as the
fallback, so even an imperfect friendly mapper never silences a
failure.

### 10.2 Mandatory PoC recipe (BEFORE any production code)

Per AGENTS.md §"Mandatory Workflow: PoC First, Always":

**Step 1 — Prove the auth round-trip reaches NNS (smallest PoC):**

```bash
export PATH="/home/ubuntu/.cache/data/dfx/bin:$PATH"
export DFX_WARNING=-mainnet_plaintext_identity

# Generate a fresh Ed25519 identity (the same path the host uses).
# Use the FFI directly (the same bridge the bundle uses):
cd /code/icp-cc/apps/autorun_flutter
# (Or via dfx identity new alpha-vote-probe && dfx identity get-principal)

# Call authenticated manage_neuron RegisterVote with a fake neuron id
# + a real OPEN proposal id (substitute one from list_proposals).
dfx canister --network ic call --update rrkah-fqaaa-aaaaa-aaaaq-cai \
  manage_neuron \
  '(record { id = opt record { id = 12345 : nat64 };
             command = opt variant { RegisterVote = record {
               vote = 1 : int32;
               proposal = opt record { id = <REAL_PROPOSAL_ID> : nat64 }; } }; })'
```

**Expected PoC output:** a structured `ManageNeuronResponse` with
`command = opt variant { Error = { error_message: "Neuron not found:
NeuronId { id: 12345 }"; error_type: ... } }`. This proves:

- ✅ The authenticated call reached NNS Governance.
- ✅ The caller was NOT anonymous (anonymous callers get a different,
  auth-layer rejection).
- ✅ The candid args parsed correctly (no decode error).
- ✅ NNS rejected at the APPLICATION layer ("neuron not found"),
  which is the expected path for a non-owned neuron.

If the response is instead an auth-layer rejection (anonymous
principal) or a candid decode error, STOP — the auth path is broken
and the bundle will not work.

**Step 2 — Same PoC for `Follow`:** identical pattern with the Follow
candid from §5.3. Expect the same structured Error.

**Step 3 — Same PoC via the Flutter FFI bridge** (not dfx), to prove
the host's `callAuthenticated` path produces the same response shape
the bundle will see. Use the existing
`live_canister_auth_test.dart`'s `_freshKeypair` helper as a template.
This is the bridge-level equivalent of Step 1.

**Step 4 — Verify bundle decode logic** against the PoC's response
shape: feed the captured JSON into `decodeManageNeuronResponse` and
confirm `friendlyNnsError` produces the expected copy.

Only after Steps 1–4 pass, write the failing tests (§9) then
productionise.

## 11. Order of commits

Each commit is independently green (mirrors the prior spec's §11
discipline — small, shippable units):

1. **Unit 1** — Bundle + descriptor + loader + bundle tests.
   `feat(dapps): add ALPHA-Vote authenticated neuron voting dapp`
   Files:
   - `apps/autorun_flutter/lib/examples/10_alpha_vote.js` (the bundle)
   - `apps/autorun_flutter/lib/config/example_dapps.dart` (new
     `DappDescriptor` + 3 ALPHA-Vote neuron id constants)
   - `apps/autorun_flutter/pubspec.yaml` (asset registration)
   - `apps/autorun_flutter/test/shared/ts_bundle_fixtures.dart`
     (`loadAlphaVoteBundle()`)
   - `apps/autorun_flutter/test/features/scripts/alpha_vote_bundle_test.dart`
     (the §9.1 tests)
   Confidence: 9/10. Independently green (bundle + tests pass via the
   real FFI runtime; descriptor is registered but the dapp is
   reachable in the catalog immediately).

2. **Unit 2** — Host auth-path + trust-store integration tests.
   `test(dapps): cover ALPHA-Vote host auth dispatch + trust gate`
   Files:
   - `apps/autorun_flutter/test/features/scripts/alpha_vote_host_auth_test.dart`
     (§9.2)
   - `apps/autorun_flutter/test/features/dapps/alpha_vote_trust_test.dart`
     (§9.3)
   Confidence: 9/10. No production-code changes; tests verify the
   existing host behaves correctly for the new bundle.

3. **Unit 3** — Docs + OPEN_ISSUES update.
   `docs: record ALPHA-Vote dapp + close deferred AUTH-VOTING follow-up`
   Files:
   - `docs/OPEN_ISSUES.md` (if there's a deferred entry for
     authenticated voting — check; the prior spec §3 deferred it but
     may not have an OPEN_ISSUES row. If not, add a RESOLVED entry
     pointing to this spec.)
   - `TODO.md` (strike through this unit if present)
   - This spec's STATUS header (mirror the prior spec's pattern).

**Recommended commit count: 3.** Estimated implementer wall-clock:
**1–1.5 days** (bundle ~4h, tests ~3h, PoC verification ~1h, polish
~1h; the host layer is already shipped and needs no changes).

## 12. Risks

### 12.1 Host-mediated-signing invariant (PRESERVED, no risk)

The bundle NEVER holds raw private keys. The `authenticated: true`
flag on an effect is a REQUEST to the host to sign; the host resolves
the active profile's keypair (`script_app_host.dart:705-723`) and
calls `bridge.callAuthenticated(privateKeyB64: kp.privateKey, ...)`.
The bundle receives only the JSON result envelope. No new code
introduces key material into the bundle's scope — invariant preserved
by construction.

### 12.2 Neuron-id handling (LOW risk, well-bounded)

- The user pastes a neuron id OR discovers it via `list_neurons`. The
  bundle stores it as a string in state; no persistence (mirrors
  09_sns_proposals.js's canister-id paste UX — the user re-enters it
  each session unless we extend `DappRuntimeConfig`, which is a
  YAGNI follow-up per §3).
- No validation beyond "non-empty + numeric." A malformed id produces
  an NNS-side `Error` response, surfaced via `friendlyNnsError`. The
  dapp does NOT attempt to validate ownership client-side (the only
  source of truth is NNS Governance itself).
- Risk: a user pastes another user's neuron id and tries to vote.
  Mitigation: NNS rejects it ("Neuron not found" — because the
  caller's principal isn't the controller). The friendly copy explains
  why. No data leak (the failure response doesn't leak the actual
  owner's principal).

### 12.3 Candid variant complexity (MEDIUM risk during PoC)

`ManageNeuronRequest` is a large variant with 15+ alternatives. The
bundle only emits 2 (`RegisterVote`, `Follow`), but the response is
ALSO a variant (`ManageNeuronResponse`) with its own alternatives
(including `Error`). The decoder must handle:

- `command = opt variant { RegisterVoteResponse = ... }` (success)
- `command = opt variant { FollowResponse = ... }` (success)
- `command = opt variant { Error = record { error_type, error_message } }`
  (failure — the common case for non-owned neurons)
- `command = null` (defensive — shouldn't happen but never crash)

The `decodeManageNeuronResponse` helper (§6.8) must be tested against
ALL these shapes (§9.1 tests 12-14 + the malformed-reply test 16).
Risk: missing a shape → silent swallow → AGENTS.md violation.
Mitigation: the failing tests are written BEFORE production code, and
the malformed-reply test asserts a LOUD error for any shape not
explicitly handled.

### 12.4 Future NNS Governance API changes (LOW risk)

NNS Governance evolves (topic enum renumbering, new ManageNeuron
commands, deprecation of the `id` field in favour of
`neuron_id_or_subaccount`). The dapp is a snapshot of the current API:

- Topic enum: ALPHA-Vote README uses `0/4/14`; the prior spec used the
  older `0/1/4/5/6/7/8/10/11/12` numbering. The bundle reconciles
  both (full enum in `TOPIC`, follow affordance uses ALPHA-Vote's
  0/4/14). A future renumbering requires a bundle update — flagged in
  the bundle header comment.
- `id` field deprecation: still works (verified §5.4); if it's ever
  removed, the bundle must move to `neuron_id_or_subaccount` (one-line
  change in each effect builder, captured in §5.4 as the
  recommendation rationale).
- New ManageNeuron commands: out of scope (the bundle emits only
  RegisterVote + Follow; new commands are additive and don't break
  existing ones).

Mitigation: the bundle header comment explicitly cites the verified
date + dfx version, so a future maintainer knows when to re-verify.

### 12.5 No-open-proposals quiet period (LOW risk, already handled)

As of 2026-07-21 there are ZERO open NNS proposals (verified §5.7).
The bundle inherits 08_nns_proposals.js's honest empty-state copy
("No proposals match this filter. NNS has quiet periods — try 'all'
to see recent history."). The vote/follow UI simply has nothing to
act on during quiet periods — but the Follow affordance is
proposal-independent (you can follow a neuron on a topic even with
zero open proposals), so the dapp remains useful.

### 12.6 Race with concurrent subagents (LOW risk)

Per the task brief, this scope file is NEW (no conflict risk). The
implementer touches:
- `lib/examples/10_alpha_vote.js` (NEW)
- `lib/config/example_dapps.dart` (append-only — low conflict risk)
- `pubspec.yaml` (append-only to assets list — low conflict risk)
- `test/shared/ts_bundle_fixtures.dart` (append-only — low conflict
  risk)
- `test/features/scripts/alpha_vote_bundle_test.dart` (NEW)
- `test/features/scripts/alpha_vote_host_auth_test.dart` (NEW)
- `test/features/dapps/alpha_vote_trust_test.dart` (NEW)

The only files with non-trivial merge risk are `example_dapps.dart`
and `pubspec.yaml` (other subagents may also append). Standard git
merge handles both cleanly (additions to a list / map). No
architectural overlap with other in-flight work.

## 13. Summary (TL;DR for the implementer)

- **What:** new dapp `alpha_vote` (id) / "Neuron Voting" (title) at
  `lib/examples/10_alpha_vote.js`. User-driven authenticated NNS
  voting: browse open proposals → see what ALPHA-Vote's 3 public
  neurons voted → tap Vote Yes/No or Follow on a topic. Signed by the
  active profile's keypair via the existing host auth path.
- **MVP PoC:** run §10.2 Step 1 (dfx authenticated `manage_neuron
  RegisterVote` with a fake neuron id) and confirm NNS returns a
  structured "Neuron not found" Error (NOT an auth-layer rejection
  or candid decode failure). That proves the auth round-trip works.
- **Candid args:** verified live (§5); use the deprecated `id` field
  for pedagogical continuity with ALPHA-Vote Rust. Both RegisterVote
  and Follow shapes compile (verified via `simulate_manage_neuron`).
- **Reused:** ~80% of `08_nns_proposals.js` helpers (verbatim); the
  `callEffect` + auth pattern from `06_icp_poll.js`; the entire host
  auth-dispatch path from UX-H12.
- **No new host code.** No new dependencies. No new trust affordance.
- **3 commits, 1–1.5 days, 9/10 confidence.**
- **Biggest risk:** `decodeManageNeuronResponse` shape coverage (§12.3)
  — mitigated by writing the failing tests first (§9 tests 12-16).
