# 2026-07-21 — SNS / NNS Voting Scripts (read-only mainnet demos)

> Spec / plan for adding headliner voting-governance scripts to the Dapps
> catalog. Demonstrates what icp-cc can do against **real** mainnet canisters
> (HUMAN_EXPECTATIONS §3) with zero user setup. Source of truth for this unit
> of work — update as decisions land.

## 1. Problem

The Dapps catalog ships exactly one always-working mainnet read-only demo
(`07_icp_ledger.js` — token metadata) and one local-replica demo
(`06_icp_poll.js`). Two examples is too thin to communicate the platform's
range. The most compelling ICP use case — **decentralised governance** — is
absent. Two cloned repos in `third_party/` (`CO.DELTA`, `ALPHA-Vote`) study
NNS neuron automation in Rust but never produce a *user-facing* demo.

## 2. User value (what changes for the user)

After this work, a brand-new user opening **Dapps** sees:

1. **NNS Proposals** (mainnet, read-only): browse live NNS governance proposals
   with status filter (open / adopted / rejected / executed / all), topic
   filter, pagination, deadline countdown, and a yes/no tally bar. Works the
   moment the app is installed — no profile, no signing, no neuron.
2. **SNS Proposals** (mainnet, read-only): same browser, but for any SNS DAO.
   Defaults to a well-known SNS; the user can paste a different SNS governance
   canister id and pick a per-DAO colour theme. Demonstrates how one bundle
   adapts to many DAOs via runtime config + theming.

Both scripts are pedagogical: a curious user can read the source and see how
`list_proposals` is called, how the host wraps the result, how the UI tree is
shaped — then graduate to writing their own.

## 3. Non-goals (deferred)

- **Authenticated voting** (ALPHA-Vote's `manage_neuron` RegisterVote logic).
  Requires the user to own a staked neuron + manage follow rules — too much
  setup for a headliner demo, and out of scope for "works the moment you open
  the app." The Rust reference stays in `third_party/ALPHA-Vote/` for a future
  "Neuron Voting" example once authenticated flows are pedagogically ready.
- **Writing/sending transactions** beyond what the platform already supports.
- **Persisting user themes** beyond the existing `DappRuntimeConfig` overrides
  (SNS theme is part of the descriptor default; per-DAO runtime overrides for
  theme are a follow-up if users ask).

## 4. Stack surface used (verified)

- `icp_call` effect, `mode: 0` (query), `authenticated: false`.
- Target canister: NNS Governance `rrkah-fqaaa-aaaaa-aaaaq-cai`. SNS variant:
  any SNS governance canister id (default a known DAO).
- Method: `list_proposals`. Required Candid args (verified live via dfx; every
  field is MANDATORY — a missing field → `record field X not found`):
  ```
  (record {
    limit = N : nat32;
    exclude_topic = vec {};
    include_reward_status = vec {};
    include_status = vec {};
    omit_large_fields = opt true;
  })
  ```
  `omit_large_fields` MUST be `opt true` (type is `opt bool`).
- Response shape (decoded to JSON by the Rust bridge via
  `IDLArgs::from_bytes` + `idl_args_to_json`):
  ```
  { "proposal_info": [ { "id": [{"id": 12345}], "status": 4, "topic": 12,
      "deadline_timestamp_seconds": [1234567890],
      "latest_tally": [{"yes": 1000, "no": 200, "total": 1200, "timestamp_seconds": 0}],
      "proposal": [{"url": ["..."], "title": ["..."], "summary": "...",
        "action": [{"...": {...}}]}],
      "proposer": [{"id": 123}], "reward_status": 1 }, ... ] }
  ```
  `opt T` becomes `[T]` (a 1-element array, or `[]` if null) in the JSON
  decode. The bundle must normalise via helper `unwrapOpt(v, default)`.
- Status enum (observed + NNS Governance Rust):
  0=Unknown, 1=Open, 2=Rejected, 3=Adopted, 4=Executed, 5=Failed.
- Topic enum (observed + NNS Governance Rust):
  0=GovernanceCanisterBase, 1=TopicExchange, 4=Application (SNS Launch),
  5=SnsAndCommunityFund, 6=NodeAdmin, 7=NetworkEconomics, 8=Governance,
  10=NetworkCanisterBase, 11=SubnetManagement, 12=TopicDynamic (replica
  version updates).
- As of 2026-07-21, querying `include_status = vec { 1:int32 }` (Open only)
  returned zero proposals — there are GENUINELY no open NNS proposals at this
  moment. The bundle must handle both empty and non-empty cases honestly.

## 5. Theme support (minimal, principled addition)

Today the UI_v1 renderer has no theme knobs — everything inherits
`Theme.of(context)`. For the SNS variant we want per-DAO colour branding. We
add **one** new convention:

- A bundle's `view()` root node MAY carry an optional `theme` prop:
  ```
  { type: "column", theme: {
      background: "#0a0e27",       // scrollable container background
      card_background: "#141a3a",  // Card surface tint
      accent: "#5b8cff",           // FilledButton / emphasised text
      text: "#e8ecff",             // body text
      text_muted: "#8a93b8"        // secondary text
    }, children: [...] }
  ```
- The host (`ScriptAppHost.build`) detects `_ui['theme']`. If present:
  - Wrap the existing `SingleChildScrollView` in a `ColoredBox(background)`.
  - Inject a `Theme` widget above the renderer overriding `colorScheme`
    (primary/accent, surface/card_background) and `textTheme` (body/label
    colours). Existing renderer widgets pick the new colours up automatically.
- Unknown / missing fields: fall back to `Theme.of(context)` colours (no crash,
  no silent failure — the section just renders with the app default).
- Invalid hex string: a loud friendly `_DappErrorView` at boot is overkill;
  instead, the host logs to the dev console and falls back. (Hex parse failure
  is recoverable; unlike a missing canister it doesn't block use of the dapp.)
- The renderer itself (`ui_v1_renderer.dart`) is unchanged. The convention is
  host-level — keeps the renderer pure (props in → widget out) and avoids
  leaking theme state into every node.

## 6. Files added / changed

### Added
- `apps/autorun_flutter/lib/examples/08_nns_proposals.js` — the bundle.
- `apps/autorun_flutter/lib/examples/09_sns_proposals.js` — the SNS variant
  with theme.
- `apps/autorun_flutter/test/features/scripts/nns_proposals_bundle_test.dart`
  — TDD bundle-logic test (canned mainnet `list_proposals` reply shapes).
- `apps/autorun_flutter/test/features/scripts/sns_proposals_bundle_test.dart`
  — TDD bundle-logic test for the themed variant.
- `apps/autorun_flutter/test/features/scripts/script_app_host_theme_test.dart`
  — TDD widget test for theme application (hex parse, fallback, child tree).

### Changed
- `apps/autorun_flutter/lib/widgets/script_app_host.dart` — read `_ui['theme']`
  in `build()`, wrap with `ColoredBox` + `Theme` override. Small (~40 lines).
- `apps/autorun_flutter/lib/config/example_dapps.dart` — add two
  `DappDescriptor`s to `exampleDapps` (nns_proposals mainnet, sns_proposals
  mainnet). New constant `kMainnetNnsGovernanceCanisterId`.
- `apps/autorun_flutter/test/shared/ts_bundle_fixtures.dart` — add
  `loadNnsProposalsBundle()` and `loadSnsProposalsBundle()`.
- `apps/autorun_flutter/pubspec.yaml` — add the two `.js` files to the assets
  list (mirrors `07_icp_ledger.js` registration).
- `docs/OPEN_ISSUES.md` — record the new examples + any new follow-ups.
- `TODO.md` — strike through this unit.

## 7. Bundle design — `08_nns_proposals.js`

State:
```
{
  backend_id, host,
  status_filter: "open" | "adopted" | "rejected" | "executed" | "all",
  topic_filter: "all" | int-as-string,
  page: 0, page_size: 10,
  loading, error, loaded,
  raw_proposals: [ ...raw decoded records... ],  // last fetch
}
```

init: read `arg.backend_id`/`arg.host`, defaults → auto-load first page.

view:
```
column
├── text "NNS Proposals — live on mainnet (read-only)"
├── row [Refresh button, Status select, Topic select]
├── text error (if any)
├── paginated_list raw_proposals page=state.page size=state.page_size
│     each row → section (title: "#{id} — {title}")
│                text "Topic: {label} · Status: {label}"
│                text "Deadline: {countdown or 'closed'}"
│                tally bar (row: text "Yes {n}" / text "No {n}")
│                text "Summary: {truncated}"
└── text "Showing {n} proposals" / empty state
```

update messages:
- `{type:"refresh"}` → reload page 0 with current filters.
- `{type:"set_status", value}` → patch filter, reload.
- `{type:"set_topic", value}` → patch filter, reload.
- `{type:"page", delta:+1|-1}` → patch page, NO reload (paginate cached).
- `{type:"effect/result", id:"list_proposals", ...}` → decode + patch state.

Helpers: `setState`, `setStateShallow`, `readEffect`, `callEffect`,
`unwrapOpt`, `statusLabel`, `topicLabel`, `formatCountdown`.

DRY: the NNS + SNS bundles share 90% of their logic. The two bundles stay
self-contained (each is readable end-to-end as one file) but use IDENTICAL
helper function names + bodies so a future extraction is mechanical. (YAGNI —
extract on the third occurrence.)

## 8. Bundle design — `09_sns_proposals.js`

Identical to §7 plus:
- `arg.backend_id` defaults to a known SNS governance canister id (the
  descriptor default; can be overridden via Connection field — already wired
  via `DappRuntimeConfig`).
- `view()` root carries a `theme` prop with the DAO's brand colours.
- A text field lets the user paste a different SNS governance canister id
  inline → `{type:"set_canister", value}` updates `backend_id` and reloads.
  (Faster than opening the Connection panel; reduces clicks per UX goal.)

## 9. Verification (PoC-first)

Per AGENTS.md mandatory workflow:

1. Write the two bundles.
2. Boot each in a Dart test using the REAL FFI runtime (`bootRuntime()` +
   `rt.init/view/update`), feed canned `list_proposals` replies matching the
   verified live shape, assert the decoded proposals reach the UI.
3. Add the widget test for theme application.
4. Open the Flutter app on Linux desktop, switch to Dapps, open each new tab,
   confirm the live NNS / SNS query succeeds and the UI renders (manual or
   e2e-desktop). Empty-result case (current NNS state) must show an honest
   "no open proposals right now" message, not a blank screen.
5. Run `just test-feature scripts` then `just e2e-desktop`. Both must PASS.

## 10. Confidence

- Bundle stack, Candid args, decoded shapes: **9/10** (verified live against
  mainnet via dfx; decoded by the same Rust bridge the bundle uses).
- Theme addition: **9/10** (small, surgical, falls back cleanly).
- SNS variant working out-of-box: **7/10** (depends on a default SNS
  governance canister id that actually exposes `list_proposals`; we'll verify
  the chosen default at PoC time and fall back to NNS-shape SNS if needed).
  → If at PoC we can't find a stable SNS default that works read-only, we ship
  the NNS bundle alone + add the SNS descriptor pointing at NNS with a clear
  "paste your SNS id" prompt (graceful degradation in *content*, not in
  correctness).

## 11. Order of commits

Each commit is independently green:

1. `08_nns_proposals.js` + loader + bundle test + `nns_proposals` DappDescriptor + pubspec asset. (NNS bundle works on its own — the headliner.)
2. Theme support in `ScriptAppHost` + widget test.
3. `09_sns_proposals.js` + loader + bundle test + `sns_proposals` DappDescriptor + pubspec asset. (Builds on #2.)
4. Docs (OPEN_ISSUES, TODO).
