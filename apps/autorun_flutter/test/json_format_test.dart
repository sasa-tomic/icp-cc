import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/json_format.dart';

void main() {
  test('formats valid JSON with indentation', () {
    const raw = '{"a":1,"b":[{"c":true}]}';
    final pretty = formatJsonIfPossible(raw);
    expect(pretty, '{\n  "a": 1,\n  "b": [\n    {\n      "c": true\n    }\n  ]\n}');
  });

  test('returns input when not JSON', () {
    const raw = 'not json';
    expect(formatJsonIfPossible(raw), raw);
  });
}
