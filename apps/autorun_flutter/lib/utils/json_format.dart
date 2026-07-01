import 'dart:convert';

import 'package:flutter/foundation.dart';

String formatJsonIfPossible(String input) {
  final String trimmed = input.trim();
  if (trimmed.isEmpty) return input;
  try {
    final dynamic decoded = json.decode(trimmed);
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(decoded);
  } on FormatException catch (e) {
    debugPrint('formatJsonIfPossible: not JSON, returning as-is: $e');
    return input;
  }
}
