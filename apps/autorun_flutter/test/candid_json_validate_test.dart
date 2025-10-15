import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/candid_json_validate.dart';

void main() {
  group('validateJsonArgs', () {
    test('accepts empty for zero-arg', () {
      final r = validateJsonArgs(resolvedArgTypes: const <String>[], jsonText: '');
      expect(r.ok, true);
    });

    test('rejects invalid JSON', () {
      final r = validateJsonArgs(resolvedArgTypes: const <String>['text'], jsonText: '{');
      expect(r.ok, false);
      expect(r.errors.first.contains('Invalid JSON'), true);
    });

    test('big nat/int accept strings', () {
      final rn = validateJsonArgs(resolvedArgTypes: const <String>['nat'], jsonText: '"100000000000000000000"');
      final ri = validateJsonArgs(resolvedArgTypes: const <String>['int'], jsonText: '"-100000000000000000000"');
      expect(rn.ok, true);
      expect(ri.ok, true);
    });

    test('optionals may be null or omitted', () {
      final r1 = validateJsonArgs(resolvedArgTypes: const <String>['opt text'], jsonText: 'null');
      expect(r1.ok, true);
      final r2 = validateJsonArgs(resolvedArgTypes: const <String>['record { a : opt text }'], jsonText: '{"a": null}');
      expect(r2.ok, true);
      final r3 = validateJsonArgs(resolvedArgTypes: const <String>['record { a : opt text }'], jsonText: '{}');
      expect(r3.ok, true);
    });

    test('vectors require arrays', () {
      final r = validateJsonArgs(resolvedArgTypes: const <String>['vec nat8'], jsonText: '[1,2,3]');
      expect(r.ok, true);
      final rBad = validateJsonArgs(resolvedArgTypes: const <String>['vec nat8'], jsonText: '1');
      expect(rBad.ok, false);
    });

    test('records accept object or array by order', () {
      final t = 'record { a : nat8; b : text }';
      final rObj = validateJsonArgs(resolvedArgTypes: <String>[t], jsonText: '{"a": 1, "b": "x"}');
      expect(rObj.ok, true);
      final rArr = validateJsonArgs(resolvedArgTypes: <String>[t], jsonText: '[1, "x"]');
      expect(rArr.ok, true);
    });

    test('variant requires single-case object', () {
      final t = 'variant { A; B: text }';
      final r1 = validateJsonArgs(resolvedArgTypes: <String>[t], jsonText: '{"A": null}');
      expect(r1.ok, true);
      final r2 = validateJsonArgs(resolvedArgTypes: <String>[t], jsonText: '{"A": 1, "B": 2}');
      expect(r2.ok, false);
    });
  });
}
