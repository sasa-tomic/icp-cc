import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/base64_utils.dart';

void main() {
  test('requireBytes decodes non-empty base64', () {
    final input = base64Encode([1, 2, 3, 4]);
    final bytes = Base64Utils.requireBytes(input, fieldName: 'testField');
    expect(bytes, [1, 2, 3, 4]);
  });

  test('requireBytes rejects invalid base64', () {
    expect(
      () => Base64Utils.requireBytes('not-base64', fieldName: 'testField'),
      throwsFormatException,
    );
  });

  test('requireBytes rejects empty decoded bytes', () {
    expect(
      () => Base64Utils.requireBytes('', fieldName: 'emptyField'),
      throwsFormatException,
    );
  });
}
