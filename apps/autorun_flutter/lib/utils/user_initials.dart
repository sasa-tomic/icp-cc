/// Computes display initials for a profile [name].
///
/// For a multi-word name the result is the first letter of the first word
/// plus the first letter of the last word ("Wave Seven" → "WS",
/// "John Ronald Reuel Tolkien" → "JT"). For a single-word name only the
/// first letter is used ("Alice" → "A"). Whitespace is collapsed and the
/// result is upper-cased. An empty/whitespace-only name falls back to "?".
String computeInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words[0][0].toUpperCase();
  return (words.first[0] + words.last[0]).toUpperCase();
}
