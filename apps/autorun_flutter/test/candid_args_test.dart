import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/candid_args.dart';

void main() {
  test('composeCandidArgs builds tuple', () {
    expect(composeCandidArgs(<String>[]), '()');
    expect(composeCandidArgs(<String>['  ']), '()');
    expect(composeCandidArgs(<String>['42']), '(42)');
    expect(composeCandidArgs(<String>['42', '"hi"']), '(42, "hi")');
  });
}
