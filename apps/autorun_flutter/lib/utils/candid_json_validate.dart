import 'dart:convert';

import 'candid_args.dart';

class ValidationResult {
  const ValidationResult({required this.errors});
  final List<String> errors;
  bool get ok => errors.isEmpty;
}

ValidationResult validateJsonArgs({
  required List<String> resolvedArgTypes,
  required String jsonText,
}) {
  if (resolvedArgTypes.isEmpty) {
    // no-arg method: input should be empty or null
    if (jsonText.trim().isEmpty) return const ValidationResult(errors: <String>[]);
  }
  dynamic parsed;
  try {
    parsed = jsonText.trim().isEmpty ? null : json.decode(jsonText);
  } catch (e) {
    return ValidationResult(errors: <String>['Invalid JSON: $e']);
  }
  final List<String> errors = <String>[];
  if (resolvedArgTypes.length == 1) {
    _validateValueAgainstType(parsed, resolvedArgTypes.first, errors, path: '');
  } else {
    if (parsed is! List || parsed.length != resolvedArgTypes.length) {
      errors.add('Expected JSON array with ${resolvedArgTypes.length} items');
    } else {
      for (int i = 0; i < resolvedArgTypes.length; i += 1) {
        _validateValueAgainstType(parsed[i], resolvedArgTypes[i], errors, path: '[$i]');
      }
    }
  }
  return ValidationResult(errors: errors);
}

void _validateValueAgainstType(dynamic value, String type, List<String> errors, {required String path}) {
  final String t = type.trim().toLowerCase();
  final String p = path.isEmpty ? '(root)' : path;
  if (t == 'text') {
    if (value != null && value is! String) errors.add('$p expected string');
    return;
  }
  if (t == 'bool') {
    if (value is! bool) errors.add('$p expected boolean');
    return;
  }
  if (t == 'float32' || t == 'float64') {
    if (value is! num) errors.add('$p expected number');
    return;
  }
  if (t == 'principal') {
    if (value != null && value is! String) errors.add('$p expected principal text');
    return;
  }
  if (t == 'nat' || t == 'int') {
    if (!(value is num || value is String)) errors.add('$p expected number or numeric string');
    return;
  }
  if (_isNatOrIntBits(t)) {
    if (value is! num) errors.add('$p expected number');
    return;
  }
  if (t.startsWith('opt')) {
    if (value == null) return;
    final String inner = _extractAngleOrTail(type, 'opt');
    _validateValueAgainstType(value, inner, errors, path: p);
    return;
  }
  if (t.startsWith('vec')) {
    if (value is! List) {
      errors.add('$p expected array');
      return;
    }
    final String inner = _extractAngleOrTail(type, 'vec');
    for (int i = 0; i < value.length; i += 1) {
      _validateValueAgainstType(value[i], inner, errors, path: '$p[$i]');
    }
    return;
  }
  if (t.startsWith('record')) {
    if (value is! Map) {
      errors.add('$p expected object with named fields');
      return;
    }
    final fields = parseRecordType(type);
    for (final f in fields) {
      if (!value.containsKey(f.name)) {
        if (f.icType.trim().toLowerCase().startsWith('opt')) {
          continue; // optional may be omitted
        }
        errors.add('$p missing field ${f.name}');
        continue;
      }
      _validateValueAgainstType(value[f.name], f.icType, errors, path: '$p.${f.name}');
    }
    return;
  }
  if (t.startsWith('variant')) {
    if (value is! Map || value.length != 1) {
      final List<String> cases = _parseVariantCases(type);
      final String hint = cases.isEmpty ? 'a single case object' : 'one of: ${cases.join(', ')}';
      errors.add('$p expected variant as object with $hint');
      return;
    }
    // We cannot validate the case name without full type env; best-effort only
    return;
  }
}

bool _isNatOrIntBits(String t) {
  return t.startsWith('nat8') ||
      t.startsWith('nat16') ||
      t.startsWith('nat32') ||
      t.startsWith('nat64') ||
      t.startsWith('int8') ||
      t.startsWith('int16') ||
      t.startsWith('int32') ||
      t.startsWith('int64');
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

List<String> _parseVariantCases(String variantType) {
  final String s = variantType.trim();
  final int lbrace = s.indexOf('{');
  final int rbrace = s.lastIndexOf('}');
  if (lbrace < 0 || rbrace <= lbrace) return const <String>[];
  final String body = s.substring(lbrace + 1, rbrace);
  final List<String> parts = body.split(';').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  return parts.map((e) {
    final int idx = e.indexOf(':');
    return (idx > 0 ? e.substring(0, idx) : e).trim();
  }).toList(growable: false);
}
