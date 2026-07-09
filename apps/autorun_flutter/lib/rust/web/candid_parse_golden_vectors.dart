// R-3b WU-2 — `parseCandid` golden vectors (the parity bar).
//
// Each vector is a (`.did` text, expected `{"methods":[…]}` JSON) pair captured
// from the NATIVE `canister_client::parse_candid_interface`
// (`crates/icp_core/src/canister_client.rs:161-201`) — the pure-Dart port
// (`candid_interface_parser.dart`) MUST produce byte-identical JSON for each.
//
// Two consumers (mirrors `js_validation_golden_vectors.dart`):
//  - `candid_parse_golden_vectors_test.dart` (VM) runs every vector through
//    `parseCandidInterface` and asserts exact JSON equality. Pure Dart → no
//    browser needed; this is the FULL parity bar (unlike the quickjs golden
//    vectors, which split static/runtime stages).
//  - The live Chrome probe (`just verify-ic-agent-web`) fetches a REAL canister
//    `.did` through the proxy and asserts `parseCandid` of it contains the
//    expected `symbol` method — the end-to-end proof against live metadata.
//
// The vectors were captured by running the native Rust
// `parse_candid_interface` on each input and serialising via
// `serde_json::to_string` (compact) — see the WU-2 commit message for the
// capture method. They pin: alphabetical method sort, `idl_hash` field sort,
// tuple vs named record rendering, `blob` sugar, variant null-case rendering,
// func-type rendering with modes, and the `kind` discriminator.

/// A single parity vector: a `.did` source and the exact compact JSON the
/// native `icp_parse_candid` FFI returns for it.
class CandidParseGoldenVector {
  const CandidParseGoldenVector({required this.name, required this.did, required this.expectedJson});
  final String name;
  final String did;
  final String expectedJson;
}

/// The full parity catalogue. Every vector's `expectedJson` was captured from
/// the native Rust `parse_candid_interface` (compact `serde_json::to_string`).
const List<CandidParseGoldenVector> candidParseGoldenVectors = [
  CandidParseGoldenVector(
    name: 'ledger_like_methods',
    did: r'''
      type Tokens = record { e8s : nat64 };
      type Account = variant { id : nat64; "principal" : principal };
      type Mode = opt nat8;
      service : {
        symbol : () -> (record { symbol : text }) query;
        name : () -> (record { name : text }) query;
        decimals : () -> (record { decimals : nat32 }) query;
        pair : (text, nat64) -> (record { 0 : text; 1 : nat64 });
        blobby : (vec nat8) -> (blob);
        opts : (opt text) -> (opt principal);
        v : () -> (variant { ok; err : text });
        f : (func (text) -> (nat) query) -> ();
        items : (vec Account, Mode) -> (Tokens);
        oneway_send : (Tokens) -> () oneway;
        composite : () -> () composite_query;
        icrc1_supported_standards : () -> (vec record { name : text; url : text }) query;
      }
    ''',
    // Captured from native: methods alphabetical; fields idl_hash-sorted
    // (`{name;url}` → `{url;name}`); tuple `{0:text;1:nat64}` → `{text;nat64}`;
    // `vec nat8` → `blob`; variant null-case `ok`; oneway → Update.
    expectedJson: r'''{"methods":[{"name":"blobby","kind":"Update","args":["blob"],"rets":["blob"]},{"name":"composite","kind":"CompositeQuery","args":[],"rets":[]},{"name":"decimals","kind":"Query","args":[],"rets":["record { decimals : nat32 }"]},{"name":"f","kind":"Update","args":["func (text) -> (nat) query"],"rets":[]},{"name":"icrc1_supported_standards","kind":"Query","args":[],"rets":["vec record { url : text; name : text }"]},{"name":"items","kind":"Update","args":["vec Account","Mode"],"rets":["Tokens"]},{"name":"name","kind":"Query","args":[],"rets":["record { name : text }"]},{"name":"oneway_send","kind":"Update","args":["Tokens"],"rets":[]},{"name":"opts","kind":"Update","args":["opt text"],"rets":["opt principal"]},{"name":"pair","kind":"Update","args":["text","nat64"],"rets":["record { text; nat64 }"]},{"name":"symbol","kind":"Query","args":[],"rets":["record { symbol : text }"]},{"name":"v","kind":"Update","args":[],"rets":["variant { ok; err : text }"]}]}''',
  ),
  CandidParseGoldenVector(
    name: 'list_neurons_alias',
    did: r'''
      type NeuronSubaccount = vec nat8;
      type ListNeurons = record {
        neuron_ids : vec nat64;
        include_neurons_readable_by_caller : bool;
        include_empty_neurons_readable_by_caller : opt bool;
        include_public_neurons_in_full_neurons : opt bool;
        page_number: opt nat64;
        page_size: opt nat64;
        neuron_subaccounts: opt vec NeuronSubaccount;
      };
      service : {
        list_neurons: (ListNeurons) -> ();
      }
    ''',
    // Vars render as their alias name (NOT inlined) — parity with native
    // (`parse_candid_interface` keeps method arg types as-declared).
    expectedJson: r'''{"methods":[{"name":"list_neurons","kind":"Update","args":["ListNeurons"],"rets":[]}]}''',
  ),
  CandidParseGoldenVector(
    name: 'empty_and_named_service',
    did: r'''
      service : {
        empty_query : () -> () query;
        empty_update : () -> ();
      }
    ''',
    expectedJson: r'''{"methods":[{"name":"empty_query","kind":"Query","args":[],"rets":[]},{"name":"empty_update","kind":"Update","args":[],"rets":[]}]}''',
  ),
  CandidParseGoldenVector(
    name: 'class_service_constructor',
    did: r'''
      type InitArgs = record { controllers : vec principal };
      service : (InitArgs) -> {
        whoami : () -> (principal) query;
      }
    ''',
    // The class form `(InitArgs) -> { ... }` resolves to the inner service
    // (`as_service` on a Class) — init args are NOT methods.
    expectedJson: r'''{"methods":[{"name":"whoami","kind":"Query","args":[],"rets":["principal"]}]}''',
  ),
  CandidParseGoldenVector(
    name: 'quoted_keyword_field_name',
    did: r'''
      service : {
        meta : () -> (record { "type" : text; "service" : text }) query;
      }
    ''',
    // Keyword field names (`type`, `service`) are valid as QUOTED labels and
    // render quoted (`ident_string`). `idl_hash` sorts them.
    expectedJson: r'''{"methods":[{"name":"meta","kind":"Query","args":[],"rets":["record { \"service\" : text; \"type\" : text }"]}]}''',
  ),
  CandidParseGoldenVector(
    name: 'var_method_skipped',
    did: r'''
      type T = func () -> ();
      service : {
        inline : () -> () query;
        aliased : T;
      }
    ''',
    // `aliased : T` has a Var type → `parse_candid_interface`'s
    // `if let TypeInner::Func(f)` skips it. Only inline funcs are emitted.
    expectedJson: r'''{"methods":[{"name":"inline","kind":"Query","args":[],"rets":[]}]}''',
  ),
  CandidParseGoldenVector(
    name: 'numeric_and_tuple_variants',
    did: r'''
      service : {
        get : (nat) -> (variant { 0 : nat; 1 : text; err : text }) query;
        pair : () -> (record { nat8; text });
      }
    ''',
    // Mixed numeric + named variant fields sort by id (hash for `err`).
    // `record { nat8; text }` (bare tuple) → `record { nat8; text }`.
    expectedJson: r'''{"methods":[{"name":"get","kind":"Query","args":["nat"],"rets":["variant { 0 : nat; 1 : text; err : text }"]},{"name":"pair","kind":"Update","args":[],"rets":["record { nat8; text }"]}]}''',
  ),
];
