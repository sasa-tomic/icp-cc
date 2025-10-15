import 'dart:convert';

import 'candid_args.dart';

/// Converts user-entered values into a JSON string accepted by the Rust client
/// according to Candid arg type strings (from MethodInfo.args).
class CandidFormModel {
  const CandidFormModel(this.argTypes);

  final List<String> argTypes;

  bool get isSupportedByForm {
    for (final String raw in argTypes) {
      final String t = raw.trim().toLowerCase();
      if (t.contains('variant') || t.contains('func') || t.contains('service')) {
        return false;
      }
    }
    return true;
  }

  /// Build the JSON string for the provided inputs.
  /// - 0 args: returns empty string (treated as null on Rust side)
  /// - 1 arg: returns a single JSON value
  /// - N>1 args: returns a JSON array
  String buildJson(List<dynamic> inputs) {
    if (argTypes.isEmpty) {
      return '';
    }
    if (inputs.length != argTypes.length) {
      throw ArgumentError('Expected ${argTypes.length} inputs, got ${inputs.length}');
    }
    if (argTypes.length == 1) {
      final dynamic single = _convertForType(argTypes.first, _preParse(inputs.first));
      return jsonEncode(single);
    }
    final List<dynamic> out = <dynamic>[];
    for (int i = 0; i < argTypes.length; i += 1) {
      out.add(_convertForType(argTypes[i], _preParse(inputs[i])));
    }
    return jsonEncode(out);
  }

  dynamic _preParse(dynamic value) {
    if (value is String) {
      final String s = value.trim();
      if ((s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']')) || s == 'null' || s == 'true' || s == 'false') {
        try {
          return json.decode(s);
        } catch (_) {
          // fall through; treat as plain string
        }
      }
    }
    return value;
  }

  dynamic _convertForType(String type, dynamic value) {
    final String t = type.trim().toLowerCase();
    if (t == 'text') return _asText(value);
    if (t == 'bool') return _asBool(value);
    if (t == 'float32' || t == 'float64') return _asDouble(value);
    if (t == 'principal') return _asText(value);

    if (t == 'nat' || t == 'int') {
      return _asNatOrIntPossiblyString(value);
    }
    if (_isNatOrIntBits(t)) {
      return _asInt(value);
    }

    if (t.startsWith('opt')) {
      final String inner = _extractAngleOrTail(type, 'opt');
      if (value == null) return null;
      return _convertForType(inner, value);
    }

    if (t.startsWith('vec')) {
      final String inner = _extractAngleOrTail(type, 'vec');
      if (value is! List) {
        throw ArgumentError('Expected List for vec type');
      }
      return value.map((e) => _convertForType(inner, e)).toList();
    }

    if (t.startsWith('record')) {
      final fields = parseRecordType(type);
      if (fields.isEmpty) {
        return <String, dynamic>{};
      }
      if (value is Map) {
        final Map<String, dynamic> out = <String, dynamic>{};
        for (final f in fields) {
          if (!value.containsKey(f.name)) {
            throw ArgumentError('Missing field ${f.name}');
          }
          out[f.name] = _convertForType(f.icType, value[f.name]);
        }
        return out;
      }
      if (value is List) {
        if (value.length != fields.length) {
          throw ArgumentError('Expected ${fields.length} items for record, got ${value.length}');
        }
        final Map<String, dynamic> out = <String, dynamic>{};
        for (int i = 0; i < fields.length; i += 1) {
          out[fields[i].name] = _convertForType(fields[i].icType, value[i]);
        }
        return out;
      }
      throw ArgumentError('Unsupported record input: ${value.runtimeType}');
    }

    // Fallback: pass-through
    return value;
  }

  static bool _isNatOrIntBits(String t) {
    return t.startsWith('nat8') ||
        t.startsWith('nat16') ||
        t.startsWith('nat32') ||
        t.startsWith('nat64') ||
        t.startsWith('int8') ||
        t.startsWith('int16') ||
        t.startsWith('int32') ||
        t.startsWith('int64');
  }

  static String _extractAngleOrTail(String original, String prefix) {
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

  static String _asText(dynamic v) {
    if (v == null) return '';
    return v.toString();
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    final String s = v.toString().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
    throw ArgumentError('Invalid bool: $v');
  }

  static num _asDouble(dynamic v) {
    if (v is num) return v;
    final String s = v.toString();
    final double? d = double.tryParse(s);
    if (d == null) throw ArgumentError('Invalid float: $v');
    return d;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final String s = v.toString();
    final int? i = int.tryParse(s);
    if (i == null) throw ArgumentError('Invalid integer: $v');
    return i;
  }

  static dynamic _asNatOrIntPossiblyString(dynamic v) {
    if (v == null) return '0';
    if (v is int) return v;
    final String s = v.toString();
    final RegExp digits = RegExp(r'^-?\d+$');
    if (!digits.hasMatch(s)) return s;
    if (s.startsWith('-')) {
      if (s.length > 19) return s; // beyond 64-bit signed
      final int? i = int.tryParse(s);
      return i ?? s;
    }
    if (s.length > 20) return s; // beyond 64-bit unsigned
    final int? i = int.tryParse(s);
    return i ?? s;
  }
}
