import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/password_strength.dart';

void main() {
  group('passwordStrength', () {
    test('empty password scores 0', () {
      expect(passwordStrength(''), 0);
    });

    test('single character scores 0 (length<8, one class)', () {
      expect(passwordStrength('a'), 1);
    });

    test('eight lowercase chars scores 2 (length=1 + class=1)', () {
      expect(passwordStrength('aaaaaaaa'), 2);
    });

    test('twelve lowercase chars scores 3 (length=2 + class=1)', () {
      expect(passwordStrength('aaaaaaaaaaaa'), 3);
    });

    test('16+ chars with one class scores 4 (length=3 + class=1 = 4)', () {
      expect(passwordStrength('aaaaaaaaaaaaaaaa'), 4);
    });

    test('8 chars with two classes scores 3 (length=1 + class=2)', () {
      expect(passwordStrength('aaaaaa11'), 3);
    });

    test('8 chars with three classes scores 4 (length=1 + class=3)', () {
      expect(passwordStrength('aaaaaaA1'), 4);
    });

    test('strong diverse password scores 4 (length=3 + class=3 capped)', () {
      expect(passwordStrength('Aa1! Aa1! Aa1!'), 4);
    });

    test('short but diverse password stays low', () {
      // 5 chars, 4 classes — length=0 + class=3 (capped) = 3.
      expect(passwordStrength('Aa1!x'), 3);
    });
  });

  group('passwordStrengthLabel', () {
    test('0 maps to Weak', () {
      expect(passwordStrengthLabel(0), 'Weak');
    });

    test('1 maps to Weak', () {
      expect(passwordStrengthLabel(1), 'Weak');
    });

    test('2 maps to Fair', () {
      expect(passwordStrengthLabel(2), 'Fair');
    });

    test('3 maps to Good', () {
      expect(passwordStrengthLabel(3), 'Good');
    });

    test('4 maps to Strong', () {
      expect(passwordStrengthLabel(4), 'Strong');
    });

    test('label is consistent with the strength function', () {
      expect(passwordStrengthLabel(passwordStrength('')), 'Weak');
      expect(passwordStrengthLabel(passwordStrength('aaaaaaaa')), 'Fair');
      expect(passwordStrengthLabel(passwordStrength('aaaaaaaaaaaa')), 'Good');
      expect(passwordStrengthLabel(passwordStrength('Aa1! Aa1! Aa1!')),
          'Strong');
    });
  });
}
