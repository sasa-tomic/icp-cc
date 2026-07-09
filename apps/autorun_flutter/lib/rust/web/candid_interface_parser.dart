// R-3b WU-2 — pure-Dart Candid `.did` interface parser (option (α), plan §7.5).
//
// Ports `crates/icp_core/src/canister_client.rs:161-201` (`parse_candid_interface`)
// to pure Dart so it runs unchanged on the VM (unit-testable, mirrors the
// `js_validation_golden_vectors` pattern) AND ships to the browser with NO
// `dart:js_interop` / `dart:io` dependency. This is the Web mirror of the native
// FFI `icp_parse_candid`: it takes raw Candid text and returns the
// `{"methods":[{"name","kind","args","rets"}]}` JSON the canister-call builder UI
// consumes (`widgets/canister_client_sheet.dart:206-230`).
//
// ## Why pure Dart (not a JS dep)
// `@dfinity/candid@3.4.3` ships only the `IDL` encode/decode runtime — NO `.did`
// text parser (`candid/index.ts`; confirmed empirically during WU-2). The
// `@dfinity/*` ecosystem has no browser-bundleable runtime candid grammar parser
// (candid-ui renders from an IDL factory, not from text). Native gets this from
// the Rust `candid_parser` (lalrpop). The plan (§7.5 option (α), §7.7 WU-2)
// mandates a pure-Dart port for parity + VM-testability + zero new JS deps. This
// is that port.
//
// ## Parity contract (byte-identical to native where it matters)
// Mirrors `candid_parser`'s grammar (`src/grammar.lalrpop`) + the candid
// pretty-printer (`candid::pretty::candid::pp_ty`, line width 80) EXACTLY:
//   - Service methods are sorted ALPHABETICALLY by name (`grammar.lalrpop:241`
//     sorts `Binding.id` which is a `String` → lexicographic). Only methods with
//     an INLINE `func` type are emitted (`parse_candid_interface`'s
//     `if let TypeInner::Func(f)`); methods aliased to a bare type name are
//     skipped (parity with native, which does the same).
//   - Record/variant fields are sorted by `Label::get_id()` = `idl_hash(name)`
//     for named labels, the numeric id for `Id`/`Unnamed` labels
//     (`grammar.lalrpop:179,185`).
//   - `idl_hash` = `wrapping_mul(223).wrapping_add(byte)` per byte
//     (`candid::idl_hash`, `lib.rs:310`).
//   - Tuple records (fields with sequential ids 0..n-1) render as
//     `record { t0; t1; ... }`; named records as `record { l0 : t0; l1 : t1 }`.
//   - `vec nat8` renders as `blob`; variant cases with `null` type render as
//     just the label.
//   - Method `kind` serialises as `"Query"` / `"Update"` / `"CompositeQuery"`
//     (serde enum variant names): `query` → Query, `composite_query` →
//     CompositeQuery, no mode / `oneway` → Update.
//   - The output is COMPACT JSON (`serde_json::to_string`, not pretty) with keys
//     in declaration order: `name`, `kind`, `args`, `rets`.
// Returns `null` on any parse error — parity with the native FFI
// (`icp_parse_candid` maps `Err` → `null_c_string`, `ffi.rs:243-247`).
//
// ## Honest deviations (documented, not silent)
//   - No full type-CHECKING (`check_prog`'s alias resolution / duplicate-field
//     detection beyond sort-order). Valid canister interfaces parse identically;
//     an interface with an unbound type reference renders the reference as its
//     name (native would error → `null`). Sufficient for the `parseCandid`
//     contract (method enumeration) on real canister metadata, which is always
//     valid.
//   - `escape_debug`-quoting of unusual identifiers (non-ascii / control chars)
//     is a best-effort port; realistic dids use plain ascii identifiers, so this
//     path is effectively unreachable for canister metadata.
library;

import 'dart:convert';

/// Parse a Candid `.did` interface into the `{"methods":[...]}` JSON the native
/// FFI `icp_parse_candid` returns. Pure, synchronous, no network. Returns
/// `null` on any parse error (parity with native's `null_c_string` on `Err`).
///
/// Mirrors `canister_client::parse_candid_interface` (`canister_client.rs:161`).
String? parseCandidInterface(String candidText) {
  try {
    final tokens = _CandidLexer(candidText).tokenize();
    final prog = _Parser(tokens).parseProgram();
    if (prog == null) return null;
    // `parse_candid_interface` only emits methods with an inline Func type
    // (`if let TypeInner::Func(f)`); alias-referenced methods are skipped.
    final methods = <_Method>[];
    for (final m in prog) {
      if (m.type is _FuncType) {
        methods.add(m);
      }
    }
    // `grammar.lalrpop:241`: service bindings sort by `Binding.id` (a String) →
    // lexicographic (alphabetical) by method name.
    methods.sort((a, b) => a.name.compareTo(b.name));
    return jsonEncode(<String, dynamic>{
      'methods': methods
          .map((m) {
            final f = m.type as _FuncType;
            return <String, dynamic>{
              'name': m.name,
              'kind': _methodKind(f.modes),
              'args': f.args.map(_renderType).toList(growable: false),
              'rets': f.rets.map(_renderType).toList(growable: false),
            };
          })
          .toList(growable: false),
    });
  } on _CandidParseException {
    return null; // parity: native returns null_c_string on Err
  }
}

/// Render a candid type to its `Display` string — a faithful port of
/// `candid::pretty::candid::pp_ty` (flat, line width 80). Every type a method
/// arg/ret can be is covered.
String _renderType(_CandType t) {
  switch (t) {
    case _PrimType(:final name):
      return name;
    case _VarType(:final name):
      return _identString(name);
    case _OptType(:final inner):
      return 'opt ${_renderType(inner)}';
    case _VecType(:final inner):
      // `vec nat8` renders as `blob` (`pp_ty_inner`, Vec(Nat8) special case).
      if (inner is _PrimType && inner.name == 'nat8') return 'blob';
      return 'vec ${_renderType(inner)}';
    case _RecordType(:final fields):
      // `is_tuple`: all field ids are 0,1,...,n-1 (after sort) → tuple form.
      if (_isTuple(fields)) {
        if (fields.isEmpty) return 'record {}';
        final parts = fields.map((f) => _renderType(f.type)).join('; ');
        return 'record { $parts }';
      }
      if (fields.isEmpty) return 'record {}';
      final parts =
          fields.map((f) => '${_renderLabel(f.label)} : ${_renderType(f.type)}').join('; ');
      return 'record { $parts }';
    case _VariantType(:final fields):
      if (fields.isEmpty) return 'variant {}';
      final parts = fields.map((f) {
        // Variant case with `null` type renders as just the label.
        if (f.type is _PrimType && (f.type as _PrimType).name == 'null') {
          return _renderLabel(f.label);
        }
        return '${_renderLabel(f.label)} : ${_renderType(f.type)}';
      }).join('; ');
      return 'variant { $parts }';
    case _FuncType(:final args, :final rets, :final modes):
      final a = args.map(_renderType).join(', ');
      final r = rets.map(_renderType).join(', ');
      // `pp_function`: `(args) -> (rets)` + modes (each prefixed by a space).
      final modeStr = modes.isEmpty ? '' : modes.map((m) => ' $m').join();
      return 'func ($a) -> ($r)$modeStr';
    case _ServiceType(:final methods):
      if (methods.isEmpty) return 'service {}';
      final parts = methods
          .map((m) => '${_identString(m.name)} : ${_renderType(m.type)}')
          .join('; ');
      return 'service { $parts }';
    case _ClassType(:final args, :final service):
      final a = args.map(_renderType).join(', ');
      return '($a) -> ${_renderType(service)}';
  }
}

/// Render a field label — `pp_label_raw`: Named → `ident_string(name)` (quoted
/// if keyword/invalid); Id/Unnamed → the number.
String _renderLabel(_Label label) {
  if (label.named) return _identString(label.name);
  return label.id.toString();
}

/// `candid::idl_hash` (`lib.rs:310`): `s = s*223 + byte` (wrapping u32).
int _idlHash(String name) {
  var s = 0;
  for (final b in name.codeUnits) {
    s = (s * 223 + b) & 0xFFFFFFFF;
  }
  return s;
}

/// A record is a tuple iff its (sorted) field ids are exactly 0,1,...,n-1
/// (`TypeInner::is_tuple`, `candid::types::internal:220`).
bool _isTuple(List<_Field> fields) {
  for (var i = 0; i < fields.length; i++) {
    if (fields[i].label.named) return false; // named labels are never tuples
    if (fields[i].label.id != i) return false;
  }
  return true;
}

/// Method kind from func modes (`parse_candid_interface:181-185`):
/// `composite_query` → CompositeQuery; `query` → Query; else (none / `oneway`)
/// → Update. Serialised as the serde enum variant name.
String _methodKind(List<String> modes) {
  if (modes.contains('composite_query')) return 'CompositeQuery';
  if (modes.contains('query')) return 'Query';
  return 'Update';
}

/// The candid keyword set (`candid::pretty::candid::KEYWORDS`). An identifier
/// that matches one of these is rendered quoted.
const _keywords = <String>{
  'import', 'service', 'func', 'type', 'opt', 'vec', 'record', 'variant',
  'blob', 'principal', 'nat', 'nat8', 'nat16', 'nat32', 'nat64', 'int', 'int8',
  'int16', 'int32', 'int64', 'float32', 'float64', 'bool', 'text', 'null',
  'reserved', 'empty', 'oneway', 'query', 'composite_query',
};

/// The primitive type names (`PrimType` variants, lowercased). An `Id` matching
/// one of these is a primitive, not a Var (`PrimType::str_to_enum`).
const _primitives = <String>{
  'nat', 'nat8', 'nat16', 'nat32', 'nat64', 'int', 'int8', 'int16', 'int32',
  'int64', 'float32', 'float64', 'bool', 'text', 'null', 'reserved', 'empty',
};

/// `ident_string` (`candid::pretty::candid:64`): quote the identifier iff it is
/// not a valid ascii identifier or is a keyword. Escapes mirror Rust's
/// `escape_debug` for the common cases (quote, backslash, control chars).
String _identString(String id) {
  if (_isValidIdent(id) && !_keywords.contains(id)) return id;
  final buf = StringBuffer('"');
  for (final ch in id.runes) {
    if (ch == 0x22 || ch == 0x5C) {
      buf.writeCharCode(0x5C);
      buf.writeCharCode(ch);
    } else if (ch == 0x0A) {
      buf.write(r'\n');
    } else if (ch == 0x0D) {
      buf.write(r'\r');
    } else if (ch == 0x09) {
      buf.write(r'\t');
    } else if (ch < 0x20 || ch >= 0x7F) {
      buf.write('\\u{${ch.toRadixString(16)}}');
    } else {
      buf.writeCharCode(ch);
    }
  }
  buf.writeCharCode(0x22);
  return buf.toString();
}

bool _isValidIdent(String id) {
  if (id.isEmpty) return false;
  for (var i = 0; i < id.length; i++) {
    final c = id.codeUnitAt(i);
    final ok = i == 0
        ? (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F
        : (c >= 0x61 && c <= 0x7A) ||
            (c >= 0x41 && c <= 0x5A) ||
            (c >= 0x30 && c <= 0x39) ||
            c == 0x5F;
    if (!ok) return false;
  }
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// AST
// ─────────────────────────────────────────────────────────────────────────────

sealed class _CandType {}

class _PrimType extends _CandType {
  _PrimType(this.name);
  final String name;
}

class _VarType extends _CandType {
  _VarType(this.name);
  final String name;
}

class _OptType extends _CandType {
  _OptType(this.inner);
  final _CandType inner;
}

class _VecType extends _CandType {
  _VecType(this.inner);
  final _CandType inner;
}

class _RecordType extends _CandType {
  _RecordType(this.fields); // already sorted by label id
  final List<_Field> fields;
}

class _VariantType extends _CandType {
  _VariantType(this.fields); // already sorted by label id
  final List<_Field> fields;
}

class _FuncType extends _CandType {
  _FuncType(this.args, this.rets, this.modes);
  final List<_CandType> args;
  final List<_CandType> rets;
  final List<String> modes; // "query"|"oneway"|"composite_query"
}

class _ServiceType extends _CandType {
  _ServiceType(this.methods); // already sorted by name
  final List<_Method> methods;
}

class _ClassType extends _CandType {
  _ClassType(this.args, this.service);
  final List<_CandType> args;
  final _CandType service;
}

class _Field {
  _Field(this.label, this.type);
  final _Label label;
  final _CandType type;
}

class _Label {
  const _Label.named(this.name) : named = true, id = -1;
  const _Label.id(this.id) : named = false, name = '';
  final bool named;
  final String name;
  final int id;

  int get sortKey => named ? _idlHash(name) : id;
}

class _Method {
  _Method(this.name, this.type);
  final String name;
  final _CandType type;
}

// ─────────────────────────────────────────────────────────────────────────────
// Lexer — mirrors `candid_parser::token::Token` (logos regexes).
// ─────────────────────────────────────────────────────────────────────────────

class _CandidLexer {
  _CandidLexer(this.src);
  final String src;
  int _i = 0;

  List<_Tok> tokenize() {
    final out = <_Tok>[];
    while (_i < src.length) {
      final c = src[_i];
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        _i++;
        continue;
      }
      // Line comment `// ...`
      if (c == '/' && _i + 1 < src.length && src[_i + 1] == '/') {
        while (_i < src.length && src[_i] != '\n') {
          _i++;
        }
        continue;
      }
      // Block comment `/* ... */` (nestable per candid grammar trivia)
      if (c == '/' && _i + 1 < src.length && src[_i + 1] == '*') {
        _skipBlockComment();
        continue;
      }
      // String literal `"..."`
      if (c == '"') {
        out.add(_Tok(_TokKind.string, _readString()));
        continue;
      }
      // Punctuation / operators
      if (_match('->')) {
        out.add(const _Tok(_TokKind.arrow, '->'));
        continue;
      }
      if (_match('==')) {
        out.add(const _Tok(_TokKind.eqEq, '=='));
        continue;
      }
      if (_match('!=')) {
        out.add(const _Tok(_TokKind.notEq, '!='));
        continue;
      }
      if (_match('!:')) {
        out.add(const _Tok(_TokKind.notDecode, '!:'));
        continue;
      }
      const single = {
        '=': _TokKind.equals, '(': _TokKind.lParen, ')': _TokKind.rParen,
        '{': _TokKind.lBrace, '}': _TokKind.rBrace, ';': _TokKind.semi,
        ',': _TokKind.comma, '.': _TokKind.dot, ':': _TokKind.colon,
      };
      if (single.containsKey(c)) {
        out.add(_Tok(single[c]!, c));
        _i++;
        continue;
      }
      // Number: hex / decimal / float
      if (c == '0' && _i + 1 < src.length && (src[_i + 1] == 'x' || src[_i + 1] == 'X')) {
        out.add(_Tok(_TokKind.hexNumber, _readHex()));
        continue;
      }
      if (_isDigit(c)) {
        out.add(_Tok(_TokKind.number, _readNumber()));
        continue;
      }
      if ((c == '+' || c == '-') && _i + 1 < src.length && _isDigit(src[_i + 1])) {
        out.add(_Tok(_TokKind.number, _readNumber()));
        continue;
      }
      // Identifier `[a-zA-Z_][a-zA-Z0-9_]*`
      if (_isIdentStart(c)) {
        out.add(_Tok(_TokKind.ident, _readIdent()));
        continue;
      }
      throw _CandidParseException('unexpected character ${_describe(c)} at offset $_i');
    }
    out.add(const _Tok(_TokKind.eof, ''));
    return out;
  }

  void _skipBlockComment() {
    _i += 2; // skip /*
    var depth = 1;
    while (_i < src.length && depth > 0) {
      if (src[_i] == '/' && _i + 1 < src.length && src[_i + 1] == '*') {
        depth++;
        _i += 2;
      } else if (src[_i] == '*' && _i + 1 < src.length && src[_i + 1] == '/') {
        depth--;
        _i += 2;
      } else {
        _i++;
      }
    }
    if (depth > 0) {
      throw _CandidParseException('unterminated block comment');
    }
  }

  String _readString() {
    // Assumes src[_i] == '"'. Unescapes candid string escapes:
    //   \n \t \r \\ \" \'  \xNN (byte)  \u{...} (codepoint)
    _i++; // skip opening quote
    final buf = StringBuffer();
    while (_i < src.length) {
      final c = src[_i];
      if (c == '"') {
        _i++;
        return buf.toString();
      }
      if (c == r'\') {
        _i++;
        if (_i >= src.length) throw _CandidParseException('unterminated escape in string');
        final e = src[_i];
        switch (e) {
          case 'n':
            buf.writeCharCode(0x0A);
            _i++;
          case 't':
            buf.writeCharCode(0x09);
            _i++;
          case 'r':
            buf.writeCharCode(0x0D);
            _i++;
          case '\\':
            buf.writeCharCode(0x5C);
            _i++;
          case '"':
            buf.writeCharCode(0x22);
            _i++;
          case "'":
            buf.writeCharCode(0x27);
            _i++;
          case 'x':
            _i++;
            final hex = src.substring(_i, _i + 2);
            _i += 2;
            buf.writeCharCode(int.parse(hex, radix: 16));
          case 'u':
            _i++; // 'u'
            if (_i < src.length && src[_i] == '{') {
              _i++;
              final start = _i;
              while (_i < src.length && src[_i] != '}') {
                _i++;
              }
              final hex = src.substring(start, _i);
              _i++; // skip '}'
              buf.writeCharCode(int.parse(hex, radix: 16));
            } else {
              throw _CandidParseException('expected { after \\u');
            }
          default:
            throw _CandidParseException('unknown escape \\$e');
        }
      } else {
        buf.writeCharCode(c.codeUnitAt(0));
        _i++;
      }
    }
    throw _CandidParseException('unterminated string literal');
  }

  String _readHex() {
    final start = _i;
    _i += 2; // 0x
    while (_i < src.length && (_isHexDigit(src[_i]) || src[_i] == '_')) {
      _i++;
    }
    return src.substring(start + 2, _i).replaceAll('_', '');
  }

  String _readNumber() {
    final start = _i;
    if (src[_i] == '+' || src[_i] == '-') _i++;
    while (_i < src.length && (_isDigit(src[_i]) || src[_i] == '_')) {
      _i++;
    }
    // Float: `.digits` or exponent
    if (_i < src.length && src[_i] == '.') {
      _i++;
      while (_i < src.length && (_isDigit(src[_i]) || src[_i] == '_')) {
        _i++;
      }
    }
    if (_i < src.length && (src[_i] == 'e' || src[_i] == 'E')) {
      _i++;
      if (_i < src.length && (src[_i] == '+' || src[_i] == '-')) _i++;
      while (_i < src.length && (_isDigit(src[_i]) || src[_i] == '_')) {
        _i++;
      }
    }
    return src.substring(start, _i).replaceAll('_', '');
  }

  String _readIdent() {
    final start = _i;
    while (_i < src.length && _isIdentPart(src[_i])) {
      _i++;
    }
    return src.substring(start, _i);
  }

  bool _match(String s) {
    if (_i + s.length > src.length) return false;
    for (var j = 0; j < s.length; j++) {
      if (src[_i + j] != s[j]) return false;
    }
    _i += s.length;
    return true;
  }

  String _describe(String c) =>
      c.codeUnitAt(0) < 0x20 ? "'\\x${c.codeUnitAt(0).toRadixString(16).padLeft(2, '0')}'" : "'$c'";
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
bool _isHexDigit(String c) =>
    _isDigit(c) ||
    (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x66) || // a-f
    (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x46); // A-F
bool _isIdentStart(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x61 && u <= 0x7A) || (u >= 0x41 && u <= 0x5A) || u == 0x5F;
}

bool _isIdentPart(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 0x61 && u <= 0x7A) ||
      (u >= 0x41 && u <= 0x5A) ||
      (u >= 0x30 && u <= 0x39) ||
      u == 0x5F;
}

enum _TokKind {
  ident, string, number, hexNumber,
  equals, lParen, rParen, lBrace, rBrace, semi, comma, dot, colon,
  arrow, eqEq, notEq, notDecode,
  eof,
}

class _Tok {
  const _Tok(this.kind, this.value);
  final _TokKind kind;
  final String value;
  @override
  String toString() => '$kind($value)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Parser — recursive descent over `candid_parser::grammar.lalrpop`.
// ─────────────────────────────────────────────────────────────────────────────

class _CandidParseException implements Exception {
  _CandidParseException(this.message);
  final String message;
  @override
  String toString() => 'CandidParseException: $message';
}

class _Parser {
  _Parser(this._tokens);
  final List<_Tok> _tokens;
  int _i = 0;

  _Tok get _cur => _tokens[_i];
  _TokKind get _kind => _tokens[_i].kind;
  String get _val => _tokens[_i].value;

  void _expect(_TokKind k, [String? what]) {
    if (_kind != k) {
      throw _CandidParseException(
          'expected ${what ?? k.name} but found $_cur at token #$_i');
    }
    _i++;
  }

  bool _accept(_TokKind k) {
    if (_kind == k) {
      _i++;
      return true;
    }
    return false;
  }

  /// Parse the full program; returns the service methods (the actor's service).
  /// Returns `null` if there is no service/actor declaration.
  List<_Method>? parseProgram() {
    // Top-level: a sequence of `type X = ...;` / `import "...";` declarations,
    // followed by an optional `service : {...}` actor. Type decls are parsed
    // (and discarded — `parse_candid_interface` renders Vars as names, so the
    // env is not needed for the method-signature output).
    _ServiceType? service;
    while (_kind != _TokKind.eof) {
      if (_kind == _TokKind.ident) {
        if (_val == 'type') {
          _i++;
          _expect(_TokKind.ident, 'type name');
          _expect(_TokKind.equals);
          _parseType(); // parsed + discarded (Var names render as-is)
          _accept(_TokKind.semi);
          continue;
        }
        if (_val == 'import') {
          _i++;
          // import "path" ;  (path may be a string or an id)
          if (_kind == _TokKind.string) {
            _i++;
          } else if (_kind == _TokKind.ident) {
            _i++;
          }
          _accept(_TokKind.semi);
          continue;
        }
        if (_val == 'service') {
          service = _parseServiceDecl();
          break;
        }
      }
      throw _CandidParseException(
          'expected `type`, `import`, or `service` at top level but found $_cur');
    }
    // Trailing declarations after the service are not part of the candid grammar
    // (the actor is last); tolerate trailing whitespace/EOF only.
    if (_kind != _TokKind.eof) {
      throw _CandidParseException('unexpected trailing tokens after service: $_cur');
    }
    return service?.methods;
  }

  /// `service [: Name] : <ActorTyp>` — the candid actor declaration. The
  /// `ActorTyp` is either `{ bindings }` (a direct service) or
  /// `(init_args) -> { bindings }` (a service constructor / class).
  _ServiceType _parseServiceDecl() {
    _i++; // consume `service`
    // Optional named service: `service S : ...` (rare; the grammar allows it).
    if (_kind == _TokKind.ident && _val != 'service') {
      _i++; // service name (discarded — `as_service` ignores the name)
    }
    _expect(_TokKind.colon);
    final t = _parseActorType();
    if (t is _ServiceType) return t;
    if (t is _ClassType) {
      // `as_service` resolves a Class to its inner service.
      if (t.service is _ServiceType) return t.service as _ServiceType;
      // Class -> Var(service): rare; would need env resolution. Treat as empty.
      return _ServiceType(const []);
    }
    throw _CandidParseException('service actor is not a service/class type');
  }

  /// `<ActorTyp>` = `{ bindings }` OR `( types ) -> { bindings }`.
  _CandType _parseActorType() {
    if (_kind == _TokKind.lParen) {
      // Class form: `( init_args ) -> { bindings }`
      final args = _parseTupleType();
      _expect(_TokKind.arrow);
      final service = _parseServiceBody();
      return _ClassType(args, service);
    }
    return _parseServiceBody();
  }

  _ServiceType _parseServiceBody() {
    _expect(_TokKind.lBrace);
    final methods = <_Method>[];
    while (_kind != _TokKind.rBrace) {
      methods.add(_parseMethodBinding());
      if (!_accept(_TokKind.semi)) break;
    }
    _expect(_TokKind.rBrace);
    // `grammar.lalrpop:241`: sort by method name (String) → alphabetical.
    methods.sort((a, b) => a.name.compareTo(b.name));
    return _ServiceType(methods);
  }

  /// `Name : FuncType` | `Name : id` (a Var ref — skipped by
  /// `parse_candid_interface`, but still parsed).
  _Method _parseMethodBinding() {
    final name = _parseName();
    _expect(_TokKind.colon);
    // A bare identifier here is a type reference (Var); otherwise a func type.
    if (_kind == _TokKind.ident &&
        _val != 'func' &&
        !_primitives.contains(_val) &&
        !_keywords.contains(_val)) {
      final varName = _val;
      _i++;
      return _Method(name, _VarType(varName));
    }
    // `func (args) -> (rets) [mode]` OR an inline `(args) -> (rets) [mode]`
    // (candid allows omitting the `func` keyword in method position).
    final func = _parseFuncType(allowKeyword: true);
    return _Method(name, func);
  }

  /// Parse a type (`Typ` rule, `grammar.lalrpop:161`).
  _CandType _parseType() {
    if (_kind == _TokKind.ident) {
      switch (_val) {
        case 'opt':
          _i++;
          return _OptType(_parseType());
        case 'vec':
          _i++;
          return _VecType(_parseType());
        case 'blob':
          _i++;
          return _VecType(_PrimType('nat8'));
        case 'record':
          _i++;
          return _parseRecordOrVariant(isVariant: false);
        case 'variant':
          _i++;
          return _parseRecordOrVariant(isVariant: true);
        case 'func':
          _i++;
          return _parseFuncType(allowKeyword: false);
        case 'service':
          _i++;
          return _parseServiceBody();
        case 'principal':
          _i++;
          return _PrimType('principal');
        default:
          // `id` → primitive (if in the prim set) or a Var reference.
          final name = _val;
          _i++;
          if (_primitives.contains(name)) return _PrimType(name);
          return _VarType(name);
      }
    }
    if (_kind == _TokKind.string) {
      // A quoted identifier is a Var reference.
      final name = _val;
      _i++;
      return _VarType(name);
    }
    if (_kind == _TokKind.lParen) {
      // Parenthesised type (candid allows `(T)` for grouping in some contexts).
      _i++;
      final t = _parseType();
      _expect(_TokKind.rParen);
      return t;
    }
    throw _CandidParseException('expected a type but found $_cur');
  }

  _CandType _parseRecordOrVariant({required bool isVariant}) {
    _expect(_TokKind.lBrace);
    final fields = <_Field>[];
    var nextUnnamedId = 0;
    while (_kind != _TokKind.rBrace) {
      // Record vs variant bare-field semantics DIFFER (`grammar.lalrpop`):
      //  - record: `label : type` OR a bare `Typ` (tuple element, Unnamed id).
      //  - variant: `label : type` OR a bare `Name` (null-type case, the
      //    `VariantFieldTyp` rule `<n:Name> => TypeField{label, Null}`).
      if (isVariant) {
        if (_kind == _TokKind.ident || _kind == _TokKind.string) {
          final name = _parseName();
          if (_accept(_TokKind.colon)) {
            final type = _parseType();
            fields.add(_Field(_Label.named(name), type));
            nextUnnamedId = _idlHash(name) + 1;
          } else {
            // Bare Name → null-type variant case (e.g. `variant { ok; err : text }`).
            fields.add(_Field(_Label.named(name), _PrimType('null')));
            nextUnnamedId = _idlHash(name) + 1;
          }
        } else if (_kind == _TokKind.number || _kind == _TokKind.hexNumber) {
          final radix = _kind == _TokKind.hexNumber ? 16 : 10;
          final n = int.parse(_val, radix: radix);
          _i++;
          _expect(_TokKind.colon);
          final type = _parseType();
          fields.add(_Field(_Label.id(n), type));
          nextUnnamedId = n + 1;
        } else {
          throw _CandidParseException(
              'expected a variant case (Name or Name : Type) but found $_cur');
        }
      } else {
        // Record: `label : type` (label is Name/string/number followed by `:`)
        // or a bare `Typ` (tuple element).
        if (_isRecordFieldLabel()) {
          final label = _parseFieldLabel();
          _expect(_TokKind.colon);
          final type = _parseType();
          fields.add(_Field(label, type));
          nextUnnamedId =
              (label.named ? _idlHash(label.name) : label.id) + 1;
        } else {
          final type = _parseType();
          fields.add(_Field(_Label.id(nextUnnamedId), type));
          nextUnnamedId++;
        }
      }
      if (!_accept(_TokKind.semi)) break;
    }
    _expect(_TokKind.rBrace);
    // `grammar.lalrpop:179,185`: sort fields by label id.
    fields.sort((a, b) => a.label.sortKey.compareTo(b.label.sortKey));
    return isVariant ? _VariantType(fields) : _RecordType(fields);
  }

  /// A record field label is a Name/string/number that is followed by `:`.
  /// A bare type keyword (nat/record/…) is NOT a label even if followed by `:`
  /// (it starts a type). Disambiguates `record { name : text }` (named field)
  /// from `record { text }` (tuple element).
  bool _isRecordFieldLabel() {
    if (_kind == _TokKind.string) return _peekIsColon();
    if (_kind == _TokKind.number || _kind == _TokKind.hexNumber) return _peekIsColon();
    if (_kind == _TokKind.ident) {
      if (_primitives.contains(_val)) return false; // primitive starts a type
      if (_val == 'principal' ||
          _val == 'opt' ||
          _val == 'vec' ||
          _val == 'record' ||
          _val == 'variant' ||
          _val == 'func' ||
          _val == 'service' ||
          _val == 'blob') {
        return false; // type-construction keyword
      }
      return _peekIsColon();
    }
    return false;
  }

  _Label _parseFieldLabel() {
    if (_kind == _TokKind.string) {
      final s = _val;
      _i++;
      return _Label.named(s);
    }
    if (_kind == _TokKind.number || _kind == _TokKind.hexNumber) {
      final n = int.parse(_val, radix: _kind == _TokKind.hexNumber ? 16 : 10);
      _i++;
      return _Label.id(n);
    }
    if (_kind == _TokKind.ident) {
      final s = _val;
      _i++;
      return _Label.named(s);
    }
    throw _CandidParseException('expected a field label but found $_cur');
  }

  /// `FuncTyp`: `( args ) -> ( rets ) [mode]*` (`grammar.lalrpop:226`).
  /// `allowKeyword` lets a method-position func omit the `func` keyword.
  _FuncType _parseFuncType({required bool allowKeyword}) {
    if (allowKeyword && _kind == _TokKind.ident && _val == 'func') {
      _i++; // consume optional `func` keyword
    }
    final args = _parseTupleType();
    _expect(_TokKind.arrow);
    final rets = _parseTupleType();
    final modes = <String>[];
    while (_kind == _TokKind.ident &&
        (_val == 'query' || _val == 'oneway' || _val == 'composite_query')) {
      modes.add(_val);
      _i++;
    }
    return _FuncType(args, rets, modes);
  }

  /// `TupTyp`: `( type, type, ... )` (`grammar.lalrpop:222`).
  List<_CandType> _parseTupleType() {
    _expect(_TokKind.lParen);
    final types = <_CandType>[];
    while (_kind != _TokKind.rParen) {
      types.add(_parseArgType());
      if (!_accept(_TokKind.comma)) break;
    }
    _expect(_TokKind.rParen);
    return types;
  }

  /// `ArgTyp`: a type, optionally with an annotation `name : type` (ignored —
  /// candid arg names are not part of the wire type). We parse `id :` greedily
  /// only when it's a label-like name followed by a colon.
  _CandType _parseArgType() {
    // candid allows `name : type` in arg position (named args); the name is
    // cosmetic. Detect `ident :` and skip the name.
    if (_kind == _TokKind.ident &&
        !_primitives.contains(_val) &&
        _val != 'principal' &&
        _val != 'opt' &&
        _val != 'vec' &&
        _val != 'record' &&
        _val != 'variant' &&
        _val != 'func' &&
        _val != 'service' &&
        _val != 'blob' &&
        _peekIsColon()) {
      _i++; // skip the arg name
      _expect(_TokKind.colon);
    }
    return _parseType();
  }

  bool _peekIsColon() {
    return _i + 1 < _tokens.length && _tokens[_i + 1].kind == _TokKind.colon;
  }

  /// `Name`: an identifier or a quoted string (`grammar.lalrpop:302`).
  String _parseName() {
    if (_kind == _TokKind.ident) {
      final s = _val;
      _i++;
      return s;
    }
    if (_kind == _TokKind.string) {
      final s = _val;
      _i++;
      return s;
    }
    throw _CandidParseException('expected a name but found $_cur');
  }
}
