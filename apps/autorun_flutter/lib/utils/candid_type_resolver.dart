/// Very small Candid type alias resolver for UI rendering.
///
/// - Extracts `type Name = <type>;` aliases from the provided Candid text
/// - Resolves method arg types by expanding aliases and common wrappers
///   like `opt T` and `vec T`
/// - For records, it also resolves field types recursively and reconstructs
///   a `record { name : T; ... }` string with resolved types
class CandidTypeResolver {
  CandidTypeResolver(String candidSource) : _aliases = _extractAliases(candidSource);

  final Map<String, String> _aliases;

  /// Resolve a list of arg type strings using aliases from Candid.
  List<String> resolveArgTypes(List<String> args) {
    return args.map(resolveType).toList(growable: false);
  }

  String resolveType(String type) {
    final String t = type.trim();
    final String lower = t.toLowerCase();

    if (lower.startsWith('opt')) {
      final String inner = _extractAngleOrTail(t, 'opt');
      final String resolvedInner = resolveType(inner);
      return 'opt $resolvedInner';
    }
    if (lower.startsWith('vec')) {
      final String inner = _extractAngleOrTail(t, 'vec');
      final String resolvedInner = resolveType(inner);
      return 'vec $resolvedInner';
    }
    if (lower.startsWith('record')) {
      return _resolveRecord(t);
    }

    // Plain alias or scalar
    final String? alias = _aliases[t];
    if (alias != null) {
      // Resolve recursively in case alias refers to alias
      return resolveType(alias);
    }
    return t;
  }

  String _resolveRecord(String recordType) {
    // Attempt to rewrite record with resolved field types
    final String s = recordType.trim();
    final int lbrace = s.indexOf('{');
    final int rbrace = s.lastIndexOf('}');
    if (lbrace < 0 || rbrace <= lbrace) return s;
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
      final String resolved = resolveType(ty);
      fields.add('$name : $resolved');
    }
    return 'record { ${fields.join('; ')} }';
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

  static Map<String, String> _extractAliases(String src) {
    final String noComments = _stripComments(src);
    final Map<String, String> out = <String, String>{};
    int i = 0;
    while (true) {
      final int pos = noComments.indexOf('type', i);
      if (pos < 0) break;
      int j = pos + 4;
      // Ensure it's a standalone keyword (preceded/followed by non-identifier)
      if (pos > 0 && _isIdentChar(noComments.codeUnitAt(pos - 1))) {
        i = j;
        continue;
      }
      // Skip whitespace
      while (j < noComments.length && _isWhitespace(noComments.codeUnitAt(j))) {
        j++;
      }
      // Parse identifier
      final int startName = j;
      while (j < noComments.length && _isIdentChar(noComments.codeUnitAt(j))) {
        j++;
      }
      if (j == startName) {
        i = j;
        continue;
      }
      final String name = noComments.substring(startName, j);
      // Skip spaces to '='
      while (j < noComments.length && _isWhitespace(noComments.codeUnitAt(j))) {
        j++;
      }
      if (j >= noComments.length || noComments[j] != '=') {
        i = j;
        continue;
      }
      j++; // after '='
      // Skip spaces after '='
      while (j < noComments.length && _isWhitespace(noComments.codeUnitAt(j))) {
        j++;
      }
      // Read until semicolon at top-level (balanced braces/parens/angles)
      final int startExpr = j;
      int depthCurl = 0, depthParen = 0, depthAngle = 0;
      while (j < noComments.length) {
        final String ch = noComments[j];
        if (ch == '{') depthCurl++;
        if (ch == '}') depthCurl--;
        if (ch == '(') depthParen++;
        if (ch == ')') depthParen--;
        if (ch == '<') depthAngle++;
        if (ch == '>') depthAngle--;
        if (ch == ';' && depthCurl == 0 && depthParen == 0 && depthAngle == 0) {
          break;
        }
        j++;
      }
      if (j >= noComments.length) break;
      final String expr = noComments.substring(startExpr, j).trim();
      if (name.isNotEmpty && expr.isNotEmpty) {
        out[name] = expr;
      }
      i = j + 1;
    }
    return out;
  }

  static String _stripComments(String src) {
    // Remove // line comments
    final String noLine = src.replaceAll(RegExp(r'//.*'), '');
    // Remove /* */ block comments
    return noLine.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  }

  static bool _isWhitespace(int c) => c == 32 || c == 9 || c == 10 || c == 13;
  static bool _isIdentChar(int c) {
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 39; // letters, digits, _, '
  }
}
