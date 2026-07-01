import 'dart:convert';

import 'package:http/http.dart' as http;

/// Throws an [Exception] that includes HTTP status information and,
/// when available, the JSON payload from the response body. This guarantees
/// tests surface server-side diagnostics without having to duplicate logic.
Never throwDetailedHttpException({
  required String operation,
  required http.Response response,
}) {
  final buffer = StringBuffer()
    ..write('$operation failed: status ${response.statusCode}');

  if (response.body.isNotEmpty) {
    final body = _tryPrettyJson(response.body);
    buffer.write(' body $body');
  }

  throw Exception(buffer.toString());
}

/// Ensures that the given [response] has a status code contained in
/// [allowedStatusCodes]. Otherwise a detailed exception is thrown.
void ensureSuccessStatus({
  required http.Response response,
  required String operation,
  List<int> allowedStatusCodes = const [200, 201],
}) {
  if (!allowedStatusCodes.contains(response.statusCode)) {
    throwDetailedHttpException(operation: operation, response: response);
  }
}

String _tryPrettyJson(String body) {
  try {
    final dynamic decoded = json.decode(body);
    if (decoded is Map || decoded is List) {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    }
  } catch (_) {
    // Fall through to return raw body
  }
  return body;
}
