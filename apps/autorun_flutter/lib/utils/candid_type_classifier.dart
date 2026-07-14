// W7-11 — single source of truth for Candid type classification.
//
// Replaces ~23 duplicated `startsWith` / `==` string heuristics that were
// scattered across `widgets/candid_smart_form.dart`, `widgets/candid_args_builder.dart`,
// and `widgets/canister_args_editor.dart`. Those sites were INTERNALLY
// INCONSISTENT — e.g. `nat` used `==` (exact) but `nat8` used `startsWith`
// (prefix), so `nat8foo` would classify as a fixed-width natural while
// `natural` would fall through to the default path.
//
// The robust technique: tokenise the LEADING identifier of the type string
// and match the FULL token against the Candid keyword set. Prefix-matching
// is eliminated entirely — `nat` and `nat8` are distinct kinds, and
// `nat8foo` / `natural` become [CandidTypeKind.unknown] rather than
// silently mis-classified.
//
// Robust to leading/trailing whitespace and case. Non-canonical UI aliases
// that appeared in exactly one historic site (`string`, `boolean`, `float`)
// are folded into their canonical kinds so call-sites no longer need to
// repeat those aliases.
//
// Scope: only the Candid type forms ACTUALLY consumed by the 3 refactored
// widgets. The full Candid grammar lives in
// `lib/rust/web/candid_interface_parser.dart`; this classifier is a deliberately
// small facade over the same keyword vocabulary.

/// The conceptual kind of a Candid type string, as consumed by the form /
/// argument-builder UI. Each kind corresponds to exactly one Candid keyword
/// (or the catch-all [unknown] for everything else, including `blob`,
/// `func`, `service`, type-alias names, and unparseable input).
///
/// The boolean kind is spelled [boolean] (not `bool`) to avoid shadowing
/// Dart's built-in `bool` type inside this enum's body.
enum CandidTypeKind {
  boolean,
  text,
  principal,
  nat,
  int,
  nat8,
  nat16,
  nat32,
  nat64,
  int8,
  int16,
  int32,
  int64,
  float32,
  float64,
  vec,
  record,
  variant,
  opt,
  unknown;

  /// True for any numeric scalar (integer or float).
  bool get isNumeric => isInteger || isFloat;

  /// True for Candid's unbounded integer types (`nat`, `int`) — the
  /// big-integer forms that may exceed 64-bit range and so require string
  /// pass-through at the encoding boundary.
  bool get isUnboundedInteger => this == nat || this == int;

  /// True for the fixed-width integer types
  /// (`nat8`/`nat16`/`nat32`/`nat64`, `int8`/`int16`/`int32`/`int64`).
  bool get isFixedWidthInteger =>
      this == nat8 ||
      this == nat16 ||
      this == nat32 ||
      this == nat64 ||
      this == int8 ||
      this == int16 ||
      this == int32 ||
      this == int64;

  /// True for any integer kind (unbounded or fixed-width).
  bool get isInteger => isUnboundedInteger || isFixedWidthInteger;

  /// True for floating-point types (`float32`, `float64`).
  bool get isFloat => this == float32 || this == float64;

  /// True for the aggregate types (`vec`, `record`, `variant`) — the kinds
  /// whose JSON shape is structural rather than scalar.
  bool get isAggregate => this == vec || this == record || this == variant;
}

/// Classify a Candid type string into a [CandidTypeKind].
///
/// Matches the FULL leading identifier token (so `nat` and `nat64` are
/// distinct, and `nat8foo` / `natural` are [CandidTypeKind.unknown] rather
/// than matching `nat8` / `nat` by prefix). Robust to leading/trailing
/// whitespace and case. Returns [CandidTypeKind.unknown] for empty input,
/// non-identifier leading characters, and any Candid keyword not consumed
/// by the UI (`blob`, `func`, `service`, `null`, `reserved`, `empty`).
CandidTypeKind classifyCandidType(String type) {
  final trimmed = type.trim();
  if (trimmed.isEmpty) return CandidTypeKind.unknown;
  final m = _leadingIdent.firstMatch(trimmed.toLowerCase());
  if (m == null) return CandidTypeKind.unknown;
  final kw = m.group(1)!;
  return _kinds[kw] ?? CandidTypeKind.unknown;
}

/// Extracts the leading `[a-z][a-z0-9_]*` token. Anything that is not a
/// valid Candid identifier start (punctuation, digits, etc.) yields
/// `null` → [CandidTypeKind.unknown].
final RegExp _leadingIdent = RegExp(r'^([a-z][a-z0-9_]*)');

/// The Candid keyword → kind table. Single source of truth — call sites
/// never repeat these literals. `string`, `boolean`, and `float` are the
/// non-canonical aliases historic UI code accepted; they are folded into
/// their canonical kinds here so consumers no longer need to know about
/// them.
const Map<String, CandidTypeKind> _kinds = <String, CandidTypeKind>{
  'bool': CandidTypeKind.boolean,
  'boolean': CandidTypeKind.boolean,
  'text': CandidTypeKind.text,
  'string': CandidTypeKind.text,
  'principal': CandidTypeKind.principal,
  'nat': CandidTypeKind.nat,
  'int': CandidTypeKind.int,
  'nat8': CandidTypeKind.nat8,
  'nat16': CandidTypeKind.nat16,
  'nat32': CandidTypeKind.nat32,
  'nat64': CandidTypeKind.nat64,
  'int8': CandidTypeKind.int8,
  'int16': CandidTypeKind.int16,
  'int32': CandidTypeKind.int32,
  'int64': CandidTypeKind.int64,
  'float32': CandidTypeKind.float32,
  'float64': CandidTypeKind.float64,
  'float': CandidTypeKind.float64,
  'vec': CandidTypeKind.vec,
  'record': CandidTypeKind.record,
  'variant': CandidTypeKind.variant,
  'opt': CandidTypeKind.opt,
};
