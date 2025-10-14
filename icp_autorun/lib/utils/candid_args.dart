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
