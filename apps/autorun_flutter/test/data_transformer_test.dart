import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/data_transformer.dart';

void main() {
  group('DataTransformer Tests', () {
    group('Number Formatting', () {
      test('formatNumber with integer values', () {
        expect(DataTransformer.formatNumber(42), equals('42'));
        expect(DataTransformer.formatNumber(0), equals('0'));
        expect(DataTransformer.formatNumber(-123), equals('-123'));
      });

      test('formatNumber with decimal values', () {
        expect(DataTransformer.formatNumber(3.14159), equals('3.14159'));
        expect(DataTransformer.formatNumber(42.0), equals('42.0'));
        expect(DataTransformer.formatNumber(-2.71828), equals('-2.71828'));
      });

      test('formatNumber with decimal places', () {
        expect(DataTransformer.formatNumber(3.14159, decimals: 2), equals('3.14'));
        expect(DataTransformer.formatNumber(42, decimals: 1), equals('42.0'));
        expect(DataTransformer.formatNumber(123.456, decimals: 0), equals('123'));
      });

      test('formatNumber with string inputs', () {
        expect(DataTransformer.formatNumber('42'), equals('42'));
        expect(DataTransformer.formatNumber('3.14'), equals('3.14'));
        expect(DataTransformer.formatNumber('invalid'), equals('invalid'));
      });

      test('formatNumber with null values', () {
        expect(DataTransformer.formatNumber(null), equals('null'));
      });
    });

    group('ICP Formatting', () {
      test('formatIcp with e8s values', () {
        expect(DataTransformer.formatIcp(100000000), equals('1.00000000 ICP'));
        expect(DataTransformer.formatIcp(50000000), equals('0.50000000 ICP'));
        expect(DataTransformer.formatIcp(1), equals('0.00000001 ICP'));
      });

      test('formatIcp with custom decimals', () {
        expect(DataTransformer.formatIcp(123456789, decimals: 4), equals('12.3456 ICP'));
        expect(DataTransformer.formatIcp(100000000, decimals: 2), equals('1.00 ICP'));
      });

      test('formatIcp with string inputs', () {
        expect(DataTransformer.formatIcp('100000000'), equals('1.00000000 ICP'));
        expect(DataTransformer.formatIcp('50000000'), equals('0.50000000 ICP'));
        expect(DataTransformer.formatIcp('invalid'), equals('invalid ICP'));
      });

      test('formatIcp with null values', () {
        expect(DataTransformer.formatIcp(null), equals('null'));
      });
    });

    group('Timestamp Formatting', () {
      test('formatTimestamp with nanosecond timestamps', () {
        // 2024-01-01 00:00:00 UTC in nanoseconds
        const nanoseconds = 1704067200000000000;
        final result = DataTransformer.formatTimestamp(nanoseconds, format: 'iso');
        expect(result, contains('2024-01-01'));
      });

      test('formatTimestamp with millisecond timestamps', () {
        // 2024-01-01 00:00:00 UTC in milliseconds
        const milliseconds = 1704067200000;
        final result = DataTransformer.formatTimestamp(milliseconds, format: 'iso');
        expect(result, contains('2024-01-01'));
      });

      test('formatTimestamp with different formats', () {
        const timestamp = 1704067200000000000;

        expect(DataTransformer.formatTimestamp(timestamp, format: 'date'), equals('2024-01-01'));
        expect(DataTransformer.formatTimestamp(timestamp, format: 'time'), contains('00:00:00'));
        expect(DataTransformer.formatTimestamp(timestamp, format: 'relative'), isA<String>());
      });

      test('formatTimestamp with string inputs', () {
        expect(DataTransformer.formatTimestamp('1704067200000000000'), contains('2024'));
        expect(DataTransformer.formatTimestamp('invalid'), equals('invalid'));
      });

      test('formatTimestamp with null values', () {
        expect(DataTransformer.formatTimestamp(null), equals('null'));
      });
    });

    group('File Size Formatting', () {
      test('formatFileSize with bytes', () {
        expect(DataTransformer.formatFileSize(512), equals('512 B'));
        expect(DataTransformer.formatFileSize(1024), equals('1.0 KB'));
        expect(DataTransformer.formatFileSize(1536), equals('1.5 KB'));
      });

      test('formatFileSize with megabytes', () {
        expect(DataTransformer.formatFileSize(1048576), equals('1.0 MB'));
        expect(DataTransformer.formatFileSize(2097152), equals('2.0 MB'));
      });

      test('formatFileSize with gigabytes', () {
        expect(DataTransformer.formatFileSize(1073741824), equals('1.0 GB'));
        expect(DataTransformer.formatFileSize(2147483648), equals('2.0 GB'));
      });

      test('formatFileSize with string inputs', () {
        expect(DataTransformer.formatFileSize('1024'), equals('1.0 KB'));
        expect(DataTransformer.formatFileSize('invalid'), equals('invalid bytes'));
      });

      test('formatFileSize with null values', () {
        expect(DataTransformer.formatFileSize(null), equals('null'));
      });
    });

    group('Text Processing', () {
      test('truncateText with short text', () {
        expect(DataTransformer.truncateText('Hello', maxLength: 10), equals('Hello'));
        expect(DataTransformer.truncateText('Short', maxLength: 10), equals('Short'));
      });

      test('truncateText with long text', () {
        expect(DataTransformer.truncateText('This is a very long text', maxLength: 10), equals('This is a…'));
        expect(DataTransformer.truncateText('Hello World', maxLength: 8), equals('Hello W…'));
      });

      test('truncateText with default maxLength', () {
        final longText = 'A' * 100;
        final result = DataTransformer.truncateText(longText);
        expect(result.length, lessThanOrEqualTo(51));
        expect(result, endsWith('…'));
      });
    });

    group('Hex Conversion', () {
      test('bytesToHex with simple bytes', () {
        expect(DataTransformer.bytesToHex([0, 1, 255]), equals('0001ff'));
        expect(DataTransformer.bytesToHex([16, 32, 48]), equals('102030'));
      });

      test('bytesToHex with string input', () {
        expect(DataTransformer.bytesToHex('Hi'), equals('4869'));
        expect(DataTransformer.bytesToHex('ABC'), equals('414243'));
      });

      test('bytesToHex with list input', () {
        expect(DataTransformer.bytesToHex([0x48, 0x69]), equals('4869'));
      });

      test('bytesToHex with null values', () {
        expect(DataTransformer.bytesToHex(null), equals('null'));
      });

      test('hexToBytes with valid hex', () {
        expect(DataTransformer.hexToBytes('4869'), equals([72, 105]));
        expect(DataTransformer.hexToBytes('0001ff'), equals([0, 1, 255]));
      });

      test('hexToBytes with formatted hex', () {
        expect(DataTransformer.hexToBytes('48 69'), equals([72, 105]));
        expect(DataTransformer.hexToBytes('0x4869'), equals([72, 105]));
      });

      test('hexToBytes with odd length', () {
        expect(DataTransformer.hexToBytes('f'), equals([15]));
        expect(DataTransformer.hexToBytes('123'), equals([1, 35]));
      });

      test('hexToBytes throws on invalid hex', () {
        expect(() => DataTransformer.hexToBytes('xyz'), throwsFormatException);
        expect(() => DataTransformer.hexToBytes('gg'), throwsFormatException);
      });
    });

    group('URL Extraction', () {
      test('extractUrls with multiple URLs', () {
        final text = 'Visit https://example.com and also http://test.org for more info';
        final urls = DataTransformer.extractUrls(text);
        expect(urls, contains('https://example.com'));
        expect(urls, contains('http://test.org'));
        expect(urls.length, equals(2));
      });

      test('extractUrls with no URLs', () {
        final text = 'This text has no URLs at all';
        final urls = DataTransformer.extractUrls(text);
        expect(urls, isEmpty);
      });

      test('extractUrls with query parameters', () {
        final text = 'Check https://example.com/path?param=value&other=test';
        final urls = DataTransformer.extractUrls(text);
        expect(urls, contains('https://example.com/path?param=value&other=test'));
      });
    });

    group('Principal Formatting', () {
      test('formatPrincipal with valid principal', () {
        expect(DataTransformer.formatPrincipal('aaaaa-aa'), equals('aaaaa-aa'));
        expect(DataTransformer.formatPrincipal('RRKAH-FQAAA-AAAAA-AAAAQ-CAI'), equals('rrkah-fqaaa-aaaaa-aaaaq-cai'));
      });

      test('formatPrincipal with empty string', () {
        expect(DataTransformer.formatPrincipal(''), equals(''));
      });

      test('formatPrincipal throws on invalid format', () {
        expect(() => DataTransformer.formatPrincipal('invalid@principal'), throwsFormatException);
        expect(() => DataTransformer.formatPrincipal('ABC123'), throwsFormatException);
      });
    });

    group('Data Processing', () {
      final sampleItems = [
        {'title': 'Item 1', 'type': 'transfer', 'amount': 100000000, 'timestamp': 1704067200000000000},
        {'title': 'Item 2', 'type': 'stake', 'amount': 50000000, 'timestamp': 1704067200000000001},
        {'title': 'Item 3', 'type': 'transfer', 'amount': 200000000, 'timestamp': 1704067200000000002},
      ];

      test('filterSortItems with filter only', () {
        final filtered = DataTransformer.filterSortList(sampleItems, filterBy: 'type', filterValue: 'transfer');
        expect(filtered.length, equals(2));
        expect(filtered.every((item) => item['type'] == 'transfer'), isTrue);
      });

      test('filterSortItems with sort only (ascending)', () {
        final sorted = DataTransformer.filterSortList(sampleItems, sortBy: 'amount', ascending: true);
        expect(sorted.first['amount'], equals(50000000));
        expect(sorted.last['amount'], equals(200000000));
      });

      test('filterSortItems with sort only (descending)', () {
        final sorted = DataTransformer.filterSortList(sampleItems, sortBy: 'amount', ascending: false);
        expect(sorted.first['amount'], equals(200000000));
        expect(sorted.last['amount'], equals(50000000));
      });

      test('filterSortItems with both filter and sort', () {
        final result = DataTransformer.filterSortList(
          sampleItems,
          filterBy: 'type',
          filterValue: 'transfer',
          sortBy: 'amount',
          ascending: true
        );
        expect(result.length, equals(2));
        expect(result.first['amount'], equals(100000000));
        expect(result.last['amount'], equals(200000000));
      });

      test('groupBy with string field', () {
        final groups = DataTransformer.groupBy(sampleItems, 'type');
        expect(groups.length, equals(2));
        expect(groups.containsKey('transfer'), isTrue);
        expect(groups.containsKey('stake'), isTrue);
        expect(groups['transfer']!.length, equals(2));
        expect(groups['stake']!.length, equals(1));
      });

      test('groupBy with missing field', () {
        final groups = DataTransformer.groupBy(sampleItems, 'nonexistent');
        expect(groups.length, equals(1));
        expect(groups.containsKey('unknown'), isTrue);
        expect(groups['unknown']!.length, equals(3));
      });
    });

    group('Statistics Calculation', () {
      test('calculateStats with numeric values', () {
        final values = [1, 2, 3, 4, 5];
        final stats = DataTransformer.calculateStats(values);

        expect(stats['count'], equals(5));
        expect(stats['sum'], equals(15));
        expect(stats['mean'], equals(3.0));
        expect(stats['min'], equals(1));
        expect(stats['max'], equals(5));
        expect(stats['median'], equals(3));
      });

      test('calculateStats with even number of values', () {
        final values = [1, 2, 3, 4];
        final stats = DataTransformer.calculateStats(values);

        expect(stats['count'], equals(4));
        expect(stats['sum'], equals(10));
        expect(stats['mean'], equals(2.5));
        expect(stats['median'], equals(2.5));
      });

      test('calculateStats with single value', () {
        final values = [42];
        final stats = DataTransformer.calculateStats(values);

        expect(stats['count'], equals(1));
        expect(stats['sum'], equals(42));
        expect(stats['min'], equals(42));
        expect(stats['max'], equals(42));
        expect(stats['median'], equals(42));
      });

      test('calculateStats with empty list', () {
        final values = <int>[];
        final stats = DataTransformer.calculateStats(values);

        expect(stats['count'], equals(0));
      });

      test('calculateStats with mixed types', () {
        final values = [1, '2', 3.5, null];
        final stats = DataTransformer.calculateStats(values);

        expect(stats['count'], equals(3)); // null is filtered out
        expect(stats['sum'], equals(6.5));
      });
    });

    group('Deep Merge', () {
      test('deepMerge with simple maps', () {
        final map1 = {'a': 1, 'b': 2};
        final map2 = {'b': 3, 'c': 4};
        final result = DataTransformer.deepMerge(map1, map2);

        expect(result, equals({'a': 1, 'b': 3, 'c': 4}));
      });

      test('deepMerge with nested maps', () {
        final map1 = {'a': {'x': 1, 'y': 2}};
        final map2 = {'a': {'y': 3, 'z': 4}, 'b': 5};
        final result = DataTransformer.deepMerge(map1, map2);

        expect(result, equals({
          'a': {'x': 1, 'y': 3, 'z': 4},
          'b': 5
        }));
      });

      test('deepMerge with non-conflicting maps', () {
        final map1 = {'a': 1};
        final map2 = {'b': 2};
        final result = DataTransformer.deepMerge(map1, map2);

        expect(result, equals({'a': 1, 'b': 2}));
      });
    });
  });
}