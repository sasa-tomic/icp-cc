import 'dart:convert';

/// Utility class for transforming and formatting canister call results
class DataTransformer {
  /// Format numbers with locale-appropriate formatting
  static String formatNumber(dynamic value, {int? decimals}) {
    if (value == null) return 'null';

    if (value is num) {
      if (decimals != null) {
        return value.toStringAsFixed(decimals);
      }
      return value.toString();
    }

    // Try to parse as number
    try {
      final String valueStr = value.toString();
      final num = double.parse(valueStr);

      if (decimals != null) {
        return num.toStringAsFixed(decimals);
      }

      // If the original string represents a whole number, return it without decimal
      if (num == num.toInt() && !valueStr.contains('.')) {
        return num.toInt().toString();
      }

      return num.toString();
    } catch (_) {
      return value.toString();
    }
  }

  /// Format currency values (ICP tokens)
  static String formatIcp(dynamic value, {int decimals = 8}) {
    if (value == null) return 'null';

    try {
      final num = double.parse(value.toString()) / pow10(decimals);
      return '${num.toStringAsFixed(decimals)} ICP';
    } catch (_) {
      return '$value ICP';
    }
  }

  /// Format timestamps
  static String formatTimestamp(dynamic value, {String format = 'iso'}) {
    if (value == null) return 'null';

    try {
      DateTime dateTime;

      if (value is int) {
        // Assume nanoseconds (ICP format) or milliseconds
        if (value > 1e15) {
          // Likely nanoseconds
          dateTime = DateTime.fromMillisecondsSinceEpoch(value ~/ 1000000);
        } else if (value > 1e12) {
          // Likely microseconds
          dateTime = DateTime.fromMillisecondsSinceEpoch(value ~/ 1000);
        } else {
          // Assume milliseconds
          dateTime = DateTime.fromMillisecondsSinceEpoch(value);
        }
      } else if (value is String) {
        dateTime = DateTime.parse(value);
      } else {
        return value.toString();
      }

      switch (format.toLowerCase()) {
        case 'iso':
          return dateTime.toIso8601String();
        case 'date':
          return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
        case 'time':
          return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
        case 'relative':
          final now = DateTime.now();
          final diff = now.difference(dateTime);
          if (diff.inDays > 0) {
            return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
          } else if (diff.inHours > 0) {
            return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
          } else if (diff.inMinutes > 0) {
            return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
          } else {
            return 'just now';
          }
        default:
          return dateTime.toString();
      }
    } catch (_) {
      return value.toString();
    }
  }

  /// Format percentages
  static String formatPercentage(dynamic value, {int decimals = 2}) {
    if (value == null) return 'null';

    try {
      final num = double.parse(value.toString()) * 100;
      return '${num.toStringAsFixed(decimals)}%';
    } catch (_) {
      return '$value%';
    }
  }

  /// Format file sizes
  static String formatFileSize(dynamic value) {
    if (value == null) return 'null';

    try {
      final bytes = double.parse(value.toString());
      if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } catch (_) {
      return '$value bytes';
    }
  }

  /// Truncate text with ellipsis
  static String truncateText(String text, {int maxLength = 50, String suffix = '…'}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - suffix.length)}$suffix';
  }

  /// Convert bytes to hex string
  static String bytesToHex(dynamic value) {
    if (value == null) return 'null';

    try {
      List<int> bytes;
      if (value is String) {
        bytes = utf8.encode(value);
      } else if (value is List) {
        bytes = value.cast<int>();
      } else {
        return value.toString();
      }

      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
    } catch (_) {
      return value.toString();
    }
  }

  /// Convert hex string to bytes
  static List<int> hexToBytes(String hex) {
    try {
      hex = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
      if (hex.length % 2 != 0) hex = '0$hex';

      final bytes = <int>[];
      for (int i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return bytes;
    } catch (_) {
      throw FormatException('Invalid hex string');
    }
  }

  /// Extract URLs from text
  static List<String> extractUrls(String text) {
    final urlPattern = RegExp(
      r'https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)',
      caseSensitive: false,
    );

    return urlPattern.allMatches(text).map((match) => match.group(0)!).toList();
  }

  /// Validate and format principal IDs
  static String formatPrincipal(String principal) {
    if (principal.isEmpty) return principal;

    // Basic validation - ICP principals are alphanumeric with hyphens
    if (RegExp(r'^[a-z0-9-]+$').hasMatch(principal)) {
      return principal.toLowerCase();
    }

    throw FormatException('Invalid principal format: $principal');
  }

  /// Filter and sort a list of items
  static List<Map<String, dynamic>> filterSortList(
    List<Map<String, dynamic>> items, {
    String? sortBy,
    bool ascending = true,
    String? filterBy,
    String? filterValue,
  }) {
    var filtered = items;

    // Apply filter
    if (filterBy != null && filterValue != null) {
      filtered = items.where((item) {
        final value = item[filterBy]?.toString().toLowerCase() ?? '';
        return value.contains(filterValue.toLowerCase());
      }).toList();
    }

    // Apply sort
    if (sortBy != null) {
      filtered.sort((a, b) {
        final aValue = a[sortBy]?.toString() ?? '';
        final bValue = b[sortBy]?.toString() ?? '';

        final comparison = aValue.compareTo(bValue);
        return ascending ? comparison : -comparison;
      });
    }

    return filtered;
  }

  /// Group items by a key
  static Map<String, List<Map<String, dynamic>>> groupBy(
    List<Map<String, dynamic>> items,
    String groupByField,
  ) {
    final groups = <String, List<Map<String, dynamic>>>{};

    for (final item in items) {
      final key = item[groupByField]?.toString() ?? 'unknown';
      groups.putIfAbsent(key, () => []).add(item);
    }

    return groups;
  }

  /// Calculate statistics for numeric data
  static Map<String, dynamic> calculateStats(List<dynamic> values) {
    if (values.isEmpty) return {'count': 0};

    final numValues = values
        .where((v) => v != null)
        .map((v) => double.parse(v.toString()))
        .toList();

    if (numValues.isEmpty) return {'count': 0};

    numValues.sort();
    final sum = numValues.reduce((a, b) => a + b);
    final mean = sum / numValues.length;
    final median = numValues.length % 2 == 0
        ? (numValues[numValues.length ~/ 2 - 1] + numValues[numValues.length ~/ 2]) / 2
        : numValues[numValues.length ~/ 2];

    return {
      'count': numValues.length,
      'sum': sum,
      'mean': mean,
      'median': median,
      'min': numValues.first,
      'max': numValues.last,
    };
  }

  /// Deep merge two maps
  static Map<String, dynamic> deepMerge(
    Map<String, dynamic> map1,
    Map<String, dynamic> map2,
  ) {
    final result = Map<String, dynamic>.from(map1);

    map2.forEach((key, value) {
      if (result.containsKey(key) && result[key] is Map && value is Map) {
        result[key] = deepMerge(result[key] as Map<String, dynamic>, value as Map<String, dynamic>);
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  /// Helper for power of 10 calculation
  static double pow10(int exponent) {
    double result = 1.0;
    for (int i = 0; i < exponent.abs(); i++) {
      result *= exponent >= 0 ? 10.0 : 0.1;
    }
    return result;
  }
}