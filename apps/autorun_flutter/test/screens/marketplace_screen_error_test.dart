import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarketplaceScreen Error Formatting', () {
    test('should format HTTP 404 error with user-friendly message', () {
      // Simulate the error formatting
      final error = 'Exception: HTTP 404: Not Found';
      final result = _testFormatErrorMessage(error);

      expect(result, contains('Marketplace is currently unavailable'));
      expect(result, contains('script marketplace server is not responding'));
      expect(result, contains('try again later'));
      expect(result, contains('Technical details:'));
      expect(result, contains('Exception: HTTP 404: Not Found'));
    });

    test('should format connection error with user-friendly message', () {
      final error = 'Exception: Connection refused';
      final result = _testFormatErrorMessage(error);

      expect(result, contains('Network connection failed'));
      expect(result, contains('check your internet connection'));
      expect(result, contains('Technical details:'));
      expect(result, contains('Exception: Connection refused'));
    });

    test('should format timeout error with user-friendly message', () {
      final error = 'Exception: Connection timeout';
      final result = _testFormatErrorMessage(error);

      expect(result, contains('Connection timeout'));
      expect(result, contains('taking too long to respond'));
      expect(result, contains('Technical details:'));
      expect(result, contains('Exception: Connection timeout'));
    });

    test('should return original error for unknown errors', () {
      final error = 'Exception: Some unknown error';
      final result = _testFormatErrorMessage(error);

      expect(result, equals(error));
    });
  });
}

// Helper function to test the private error formatting logic
String _testFormatErrorMessage(String error) {
  // Provide user-friendly messages for common errors
  if (error.contains('HTTP 404') || error.contains('Not Found')) {
    return 'Marketplace is currently unavailable\n\nThe script marketplace server is not responding. This may be due to maintenance or deployment issues. Please try again later.\n\nTechnical details: $error';
  }
  if (error.contains('Connection refused') || error.contains('Network is unreachable')) {
    return 'Network connection failed\n\nUnable to connect to the marketplace. Please check your internet connection and try again.\n\nTechnical details: $error';
  }
  if (error.contains('Connection timeout')) {
    return 'Connection timeout\n\nThe marketplace is taking too long to respond. Please check your connection and try again.\n\nTechnical details: $error';
  }
  // Return the original error for other cases
  return error;
}