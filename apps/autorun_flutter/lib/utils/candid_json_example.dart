/// Build a human-friendly JSON example string for a list of Candid arg types.
/// Types should be resolved (aliases expanded) before passing in.
String buildJsonExampleForArgs(List<String> argTypes) {
  if (argTypes.isEmpty) return '';
  if (argTypes.length == 1) {
    return _exampleForType(argTypes.first);
  }
  final List<String> items = <String>[];
  for (final t in argTypes) {
    items.add(_exampleForType(t));
  }
  return '[\n  ${items.join(',\n  ')}\n]';
}

String _exampleForType(String type) {
  final String t = type.trim().toLowerCase();
  if (t == 'text') return '"example"';
  if (t == 'bool') return 'true';
  if (t == 'float32' || t == 'float64') return '3.14';
  if (t == 'principal') return '"ryjl3-tyaaa-aaaaa-aaaba-cai"';
  if (t == 'nat') return '"100000000000000000000"'; // big nat as string
  if (t == 'int') return '"-100000000000000000000"'; // big int as string
  if (t.startsWith('nat')) return '0';
  if (t.startsWith('int')) return '-1';

  if (t.startsWith('opt')) {
    // Show as null by default; users may replace with the inner example
    return 'null';
  }
  if (t.startsWith('vec')) {
    final String inner = _extractAngleOrTail(type, 'vec');
    final String ex = _exampleForType(inner);
    return '[ $ex ]';
  }
  if (t.startsWith('record')) {
    return _exampleForRecord(type);
  }
  if (t.startsWith('variant')) {
    // Render first case as example: { "Case": <payload-or-null> }
    final List<VariantCase> cases = _parseVariantCases(type);
    if (cases.isEmpty) return '{ }';
    final VariantCase first = cases.first;
    final String payload = (first.type == null || first.type!.trim().isEmpty)
        ? 'null'
        : _exampleForType(first.type!);
    return '{ "${first.name}": $payload }';
  }
  // Fallback
  return '"<value for $type>"';
}

String _exampleForRecord(String recordType) {
  final String s = recordType.trim();
  final int lbrace = s.indexOf('{');
  final int rbrace = s.lastIndexOf('}');
  if (lbrace < 0 || rbrace <= lbrace) return '{ }';
  final String body = s.substring(lbrace + 1, rbrace);
  final List<String> parts = body
      .split(';')
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .toList(growable: false);
  final List<String> fields = <String>[];
  for (final String part in parts) {
    final int idx = part.indexOf(':');
    if (idx <= 0) continue;
    final String name = part.substring(0, idx).trim();
    final String ty = part.substring(idx + 1).trim();
    final String ex = _exampleForType(ty);
    fields.add('"$name": $ex');
  }
  return '{\n  ${fields.join(',\n  ')}\n}';
}

String _extractAngleOrTail(String original, String prefix) {
  final String s = original.trim();
  final int lt = s.indexOf('<');
  final int gt = s.lastIndexOf('>');
  if (lt >= 0 && gt > lt) {
    return s.substring(lt + 1, gt).trim();
  }
  final String lower = s.toLowerCase();
  final int idx = lower.indexOf(prefix) + prefix.length;
  return s.substring(idx).trim();
}

// Parse variant into list of cases
List<VariantCase> _parseVariantCases(String variantType) {
  final String s = variantType.trim();
  final int lbrace = s.indexOf('{');
  final int rbrace = s.lastIndexOf('}');
  if (lbrace < 0 || rbrace <= lbrace) return const <VariantCase>[];
  final String body = s.substring(lbrace + 1, rbrace);
  final List<String> parts = body
      .split(';')
      .map((x) => x.trim())
      .where((x) => x.isNotEmpty)
      .toList(growable: false);
  final List<VariantCase> out = <VariantCase>[];
  for (final String part in parts) {
    final int idx = part.indexOf(':');
    if (idx <= 0) {
      out.add(VariantCase(name: part, type: null));
    } else {
      final String name = part.substring(0, idx).trim();
      final String ty = part.substring(idx + 1).trim();
      out.add(VariantCase(name: name, type: ty));
    }
  }
  return out;
}

class VariantCase {
  const VariantCase({required this.name, this.type});
  final String name;
  final String? type;
}
