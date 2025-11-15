import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/candid_args.dart';

void main() {
  test('composeCandidArgs builds tuple', () {
    expect(composeCandidArgs(<String>[]), '()');
    expect(composeCandidArgs(<String>['  ']), '()');
    expect(composeCandidArgs(<String>['42']), '(42)');
    expect(composeCandidArgs(<String>['42', '"hi"']), '(42, "hi")');
  });

  test('parseRecordType handles simple record', () {
    final fields = parseRecordType('record { start: nat64; length : nat64 }');
    expect(fields.length, 2);
    expect(fields[0].name, 'start');
    expect(fields[0].icType.toLowerCase(), 'nat64');
    expect(fields[1].name, 'length');
    expect(fields[1].icType.toLowerCase(), 'nat64');
  });

  test('buildRecordLiteral builds typed record', () {
    final fields = <RecordFieldSpec>[
      const RecordFieldSpec(name: 'start', icType: 'nat64'),
      const RecordFieldSpec(name: 'length', icType: 'nat64'),
    ];
    final rec = buildRecordLiteral(fields: fields, rawValues: <String>['10', '25']);
    expect(rec.replaceAll(RegExp(r'\n|\r|\s+'), ' ').trim(),
        'record { start = 10 : nat64; length = 25 : nat64 }');
  });

  test('composeSingleRecordArg wraps record in tuple', () {
    final fields = <RecordFieldSpec>[
      const RecordFieldSpec(name: 'start', icType: 'nat64'),
      const RecordFieldSpec(name: 'length', icType: 'nat64'),
    ];
    final args = composeSingleRecordArg(fields: fields, rawValues: <String>['0', '100']);
    expect(args.contains('record'), true);
    expect(args.startsWith('(') && args.endsWith(')'), true);
  });

  test('buildRecordFromDynamic supports list and map', () {
    final fields = <RecordFieldSpec>[
      const RecordFieldSpec(name: 'start', icType: 'nat64'),
      const RecordFieldSpec(name: 'length', icType: 'nat64'),
    ];
    final rec1 = buildRecordFromDynamic(fields: fields, value: <int>[0, 10]);
    expect(rec1.contains('start') && rec1.contains('length'), true);
    final rec2 = buildRecordFromDynamic(fields: fields, value: <String, dynamic>{'start': 0, 'length': 10});
    expect(rec2.contains('start') && rec2.contains('length'), true);
    final rec3 = buildRecordFromDynamic(fields: fields, value: <String, dynamic>{'0': 0, '1': 10});
    expect(rec3.contains('start') && rec3.contains('length'), true);
  });
}
