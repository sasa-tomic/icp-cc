String composeCandidArgs(List<String> rawValues) {
  final List<String> cleaned = rawValues
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (cleaned.isEmpty) {
    return '()';
  }
  return '(${cleaned.join(', ')})';
}

class RecordFieldSpec {
  const RecordFieldSpec({required this.name, required this.icType});
  final String name;
  final String icType; // e.g. "nat64", "text"
}

/// Parse a simple Candid record type string like:
///   "record { start : nat64; length : nat64 }"
/// Returns the ordered list of fields. This is a best-effort parser and
/// intentionally minimal to support common cases like the ledger's query_blocks.
List<RecordFieldSpec> parseRecordType(String type) {
  final String t = type.trim();
  final int open = t.indexOf('record');
  if (open < 0) return const <RecordFieldSpec>[];
  final int lbrace = t.indexOf('{', open);
  final int rbrace = t.lastIndexOf('}');
  if (lbrace < 0 || rbrace < 0 || rbrace <= lbrace) return const <RecordFieldSpec>[];
  final String body = t.substring(lbrace + 1, rbrace);
  final List<String> parts = body
      .split(';')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  final List<RecordFieldSpec> out = <RecordFieldSpec>[];
  for (final String part in parts) {
    // Expect "name : type"; tolerate missing spaces
    final int colon = part.indexOf(':');
    if (colon <= 0) continue;
    final String name = part.substring(0, colon).trim();
    final String icType = part.substring(colon + 1).trim();
    if (name.isEmpty || icType.isEmpty) continue;
    out.add(RecordFieldSpec(name: name, icType: icType));
  }
  return out;
}

/// Build a textual Candid record literal from field specs and user-entered values.
/// Values should be raw Candid literals for non-scalars; for scalars we assist lightly.
String buildRecordLiteral({
  required List<RecordFieldSpec> fields,
  required List<String> rawValues,
}) {
  assert(fields.length == rawValues.length,
      'fields and rawValues must have same length');
  final List<String> kvs = <String>[];
  for (int i = 0; i < fields.length; i += 1) {
    final RecordFieldSpec f = fields[i];
    final String vRaw = rawValues[i].trim();
    final String valueWithHint = _formatValueForType(vRaw, f.icType);
    kvs.add('${f.name} = $valueWithHint : ${f.icType}');
  }
  return 'record { ${kvs.join('; ')} }';
}

String _formatValueForType(String v, String icType) {
  // Very small helper to reduce user friction for common scalar types.
  final String t = icType.toLowerCase();
  if (t == 'text') {
    if (v.isEmpty) return '""';
    final bool quoted = (v.startsWith('"') && v.endsWith('"')) ||
        (v.startsWith("'") && v.endsWith("'"));
    return quoted ? v : '"${v.replaceAll('"', '\\"')}"';
  }
  // For nat*/int* types, if user provided plain digits, pass through.
  if (t.startsWith('nat') || t.startsWith('int')) {
    final RegExp numRe = RegExp(r'^-?\d+$');
    if (numRe.hasMatch(v)) return v;
    // Otherwise assume user provided a proper literal (e.g., "42 : nat32" or with suffix)
    return v;
  }
  // Default: return as-is, assuming user provided a proper Candid literal
  return v.isEmpty ? 'null' : v;
}

/// Compose tuple args when the single parameter is a record.
String composeSingleRecordArg({
  required List<RecordFieldSpec> fields,
  required List<String> rawValues,
}) {
  final String rec = buildRecordLiteral(fields: fields, rawValues: rawValues);
  return '($rec)';
}

/// Build a textual Candid record literal from a dynamic structure (list/object).
/// - When `value` is List, values are mapped to fields by order.
/// - When `value` is Map, first try by string key equals field name; then
///   try integer/parsable keys as positional indices.
String buildRecordFromDynamic({
  required List<RecordFieldSpec> fields,
  required dynamic value,
}) {
  final List<String> rawValues = <String>[];
  if (value is List) {
    if (value.length != fields.length) {
      throw ArgumentError('Expected ${fields.length} items, got ${value.length}');
    }
    for (int i = 0; i < fields.length; i += 1) {
      rawValues.add(_dynamicToRawLiteral(value[i], fields[i].icType));
    }
  } else if (value is Map) {
    // Try by name
    bool allByName = true;
    for (final f in fields) {
      if (!value.containsKey(f.name)) {
        allByName = false;
        break;
      }
    }
    if (allByName) {
      for (final f in fields) {
        rawValues.add(_dynamicToRawLiteral(value[f.name], f.icType));
      }
    } else {
      // Try by numeric indices "0","1" or 0,1 keys
      for (int i = 0; i < fields.length; i += 1) {
        final dynamic byInt = value[i] ?? value['$i'];
        if (byInt == null) {
          throw ArgumentError('Missing index $i in object for record fields');
        }
        rawValues.add(_dynamicToRawLiteral(byInt, fields[i].icType));
      }
    }
  } else {
    throw ArgumentError('Unsupported JSON shape for record: ${value.runtimeType}');
  }
  return buildRecordLiteral(fields: fields, rawValues: rawValues);
}

String _dynamicToRawLiteral(dynamic v, String icType) {
  final String t = icType.toLowerCase();
  if (v == null) return 'null';
  if (t == 'text') {
    final String s = v.toString();
    final bool quoted = (s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"));
    return quoted ? s : '"${s.replaceAll('"', '\\"')}"';
  }
  if (t.startsWith('nat') || t.startsWith('int')) {
    if (v is num) return v.toString();
    final String s = v.toString();
    final RegExp numRe = RegExp(r'^-?\d+$');
    if (numRe.hasMatch(s)) return s;
    return s; // Assume user-provided literal
  }
  if (t == 'bool') {
    if (v is bool) return v ? 'true' : 'false';
    final String s = v.toString().toLowerCase();
    if (s == 'true' || s == 'false') return s;
    throw ArgumentError('Invalid bool value: $v');
  }
  // Default: attempt stringification; caller may provide nested Candid literal
  return v.toString();
}

/// Parse a flexible record input string into a dynamic List/Map.
/// Accepts JSON, JS-like unquoted keys, or simple comma-separated values
/// optionally wrapped in [] or {}.
dynamic parseFlexibleRecordValue(String input) {
  final String s = input.trim();
  if (s.isEmpty) return null;
  // Try strict JSON first
  try {
    // ignore: avoid_dynamic_calls
    return _strictJsonDecode(s);
  } catch (_) {
    // fall through
  }
  String inner = s;
  if ((s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']'))) {
    inner = s.substring(1, s.length - 1).trim();
  }
  if (inner.contains(':')) {
    // Parse as key:value pairs separated by commas
    final Map<String, dynamic> m = <String, dynamic>{};
    for (final String part in inner.split(',')) {
      final int idx = part.indexOf(':');
      if (idx <= 0) continue;
      String key = part.substring(0, idx).trim();
      String val = part.substring(idx + 1).trim();
      if (key.startsWith('"') && key.endsWith('"')) {
        key = key.substring(1, key.length - 1);
      }
      if (key.startsWith("'") && key.endsWith("'")) {
        key = key.substring(1, key.length - 1);
      }
      m[key] = _looselyParseScalar(val);
    }
    return m;
  }
  // Otherwise, parse as list of scalars
  final List<dynamic> list = <dynamic>[];
  if (inner.isNotEmpty) {
    for (final String token in inner.split(',')) {
      final String t = token.trim();
      if (t.isEmpty) continue;
      list.add(_looselyParseScalar(t));
    }
  }
  return list;
}

dynamic _strictJsonDecode(String s) {
  // Late import to avoid requiring json in pure utils; caller uses dart:convert
  // Expect caller to catch exceptions.
  // We will use jsonDecode via a Function from dart:convert at call site.
  // This function is a placeholder to enable try/catch structure here; actual
  // decoding is done in UI.
  throw UnsupportedError('Use caller-side JSON decode');
}

dynamic _looselyParseScalar(String s) {
  final String t = s.trim();
  if (t.isEmpty) return '';
  if (t == 'true') return true;
  if (t == 'false') return false;
  final int? asInt = int.tryParse(t);
  if (asInt != null) return asInt;
  final double? asDouble = double.tryParse(t);
  if (asDouble != null) return asDouble;
  // Strip quotes if present
  if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
    return t.substring(1, t.length - 1);
  }
  return t;
}
