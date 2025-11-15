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
