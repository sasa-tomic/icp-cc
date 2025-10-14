import 'dart:convert';

String formatJsonIfPossible(String input) {
  final String trimmed = input.trim();
  if (trimmed.isEmpty) return input;
  try {
    final dynamic decoded = json.decode(trimmed);
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(decoded);
  } catch (_) {
    // Not JSON, return as-is
    return input;
  }
}
