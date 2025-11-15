import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/candid_form_model.dart';

void main() {
  group('CandidFormModel', () {
    test('zero args -> empty string', () {
      const model = CandidFormModel(<String>[]);
      expect(model.buildJson(<dynamic>[]), '');
    });

    test('single scalar text', () {
      const model = CandidFormModel(<String>['text']);
      expect(model.buildJson(<dynamic>['hello']), '"hello"');
    });

    test('multiple args -> array', () {
      const model = CandidFormModel(<String>['text', 'nat8']);
      expect(model.buildJson(<dynamic>['ICP', 5]), '["ICP",5]');
    });

    test('big nat as string', () {
      const model = CandidFormModel(<String>['nat']);
      final json = model.buildJson(<dynamic>['340282366920938463463374607431768211455']);
      expect(json.startsWith('"') && json.endsWith('"'), true);
    });

    test('record map shape', () {
      const model = CandidFormModel(<String>['record { start : nat64; length : nat64 }']);
      final json = model.buildJson(<dynamic>[
        <String, dynamic>{'start': '1', 'length': '2'}
      ]);
      expect(json, '{"start":1,"length":2}');
    });
  });
}
