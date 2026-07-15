import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/user_initials.dart';

void main() {
  group('computeInitials', () {
    test('multi-word name → first letter of first and last word', () {
      expect(computeInitials('Wave Seven'), 'WS');
      expect(computeInitials('John Doe'), 'JD');
      expect(computeInitials('John Ronald Reuel Tolkien'), 'JT');
    });

    test('single-word name → first letter only', () {
      expect(computeInitials('Alice'), 'A');
      expect(computeInitials('Bob'), 'B');
      expect(computeInitials('A'), 'A');
    });

    test('empty name → fallback question mark', () {
      expect(computeInitials(''), '?');
    });

    test('null-ish whitespace-only name → fallback question mark', () {
      expect(computeInitials('   '), '?');
      expect(computeInitials('\t\n'), '?');
    });

    test('leading and trailing whitespace is ignored', () {
      expect(computeInitials('  Wave Seven  '), 'WS');
      expect(computeInitials(' John '), 'J');
    });

    test('multiple spaces between words collapse', () {
      expect(computeInitials('Wave   Seven'), 'WS');
      expect(computeInitials('John\tDoe'), 'JD');
    });

    test('always uppercases the result', () {
      expect(computeInitials('wave seven'), 'WS');
      expect(computeInitials('alice'), 'A');
    });

    test('lowercase already handled', () {
      expect(computeInitials('john doe'), 'JD');
    });
  });
}
