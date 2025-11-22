import 'dart:convert';

/// Base64 helpers with strict validation for cryptographic material.
class Base64Utils {
  const Base64Utils._();

  /// Decode base64 and throw a descriptive [FormatException] on any issue.
  static List<int> requireBytes(String value, {required String fieldName}) {
    try {
      final bytes = base64Decode(value);
      if (bytes.isEmpty) {
        throw const FormatException('decoded bytes are empty');
      }
      return bytes;
    } on FormatException catch (e) {
      throw FormatException('$fieldName must be valid base64: ${e.message}');
    }
  }
}
