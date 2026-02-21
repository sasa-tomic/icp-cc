import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/error_display.dart';
import 'package:icp_autorun/utils/error_categories.dart';

void main() {
  group('ErrorCategory', () {
    group('categorization', () {
      test('categorizes network connection errors', () {
        final category = categorizeError('SocketException: Connection refused');
        expect(category, equals(ErrorCategoryType.network));
      });

      test('categorizes timeout errors as network', () {
        final category = categorizeError('TimeoutException after 30s');
        expect(category, equals(ErrorCategoryType.network));
      });

      test('categorizes 401 unauthorized as authentication', () {
        final category = categorizeError('HTTP 401: Unauthorized');
        expect(category, equals(ErrorCategoryType.authentication));
      });

      test('categorizes authentication failed message', () {
        final category = categorizeError('Authentication failed for user');
        expect(category, equals(ErrorCategoryType.authentication));
      });

      test('categorizes 404 as not found', () {
        final category = categorizeError('HTTP 404: Not Found');
        expect(category, equals(ErrorCategoryType.notFound));
      });

      test('categorizes validation errors', () {
        final category =
            categorizeError('Validation failed: field is required');
        expect(category, equals(ErrorCategoryType.validation));
      });

      test('categorizes invalid input errors', () {
        final category = categorizeError('Invalid input provided');
        expect(category, equals(ErrorCategoryType.validation));
      });

      test('categorizes 500 as server error', () {
        final category = categorizeError('HTTP 500: Internal Server Error');
        expect(category, equals(ErrorCategoryType.server));
      });

      test('categorizes 503 as server error', () {
        final category = categorizeError('Service unavailable (503)');
        expect(category, equals(ErrorCategoryType.server));
      });

      test('categorizes rate limit 429', () {
        final category = categorizeError('HTTP 429: Too Many Requests');
        expect(category, equals(ErrorCategoryType.rateLimit));
      });

      test('categorizes rate limit message', () {
        final category = categorizeError('Rate limit exceeded');
        expect(category, equals(ErrorCategoryType.rateLimit));
      });

      test('categorizes unknown errors', () {
        final category = categorizeError('Some random error message');
        expect(category, equals(ErrorCategoryType.unknown));
      });
    });

    group('error info', () {
      test('network error has correct info', () {
        final info = getErrorInfo(ErrorCategoryType.network);
        expect(info.title, isNotEmpty);
        expect(info.userMessage, isNotEmpty);
        expect(info.suggestedAction, contains('internet'));
        expect(info.icon, isNotNull);
      });

      test('authentication error has correct info', () {
        final info = getErrorInfo(ErrorCategoryType.authentication);
        expect(info.title, contains('Authentication'));
        expect(info.suggestedAction.toLowerCase(), contains('sign in'));
      });

      test('validation error has correct info', () {
        final info = getErrorInfo(ErrorCategoryType.validation);
        expect(info.title, contains('Invalid'));
        expect(info.suggestedAction, contains('input'));
      });

      test('not found error has correct info', () {
        final info = getErrorInfo(ErrorCategoryType.notFound);
        expect(info.title, contains('Not Found'));
        expect(info.suggestedAction.toLowerCase(), contains('deleted'));
      });

      test('server error has correct info', () {
        final info = getErrorInfo(ErrorCategoryType.server);
        expect(info.title, contains('Server'));
        expect(info.suggestedAction.toLowerCase(), contains('try again'));
      });

      test('rate limit error has correct info', () {
        final info = getErrorInfo(ErrorCategoryType.rateLimit);
        expect(info.title, contains('Too Many'));
        expect(info.suggestedAction.toLowerCase(), contains('wait'));
      });

      test('unknown error has helpful info', () {
        final info = getErrorInfo(ErrorCategoryType.unknown);
        expect(info.title, isNotEmpty);
        expect(info.suggestedAction, isNotEmpty);
      });
    });
  });

  group('ErrorDisplay', () {
    Widget createWidget({
      required String error,
      VoidCallback? onRetry,
      Object? errorObject,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ErrorDisplay(
            error: error,
            onRetry: onRetry,
            errorObject: errorObject,
          ),
        ),
      );
    }

    group('basic functionality (backward compatibility)', () {
      testWidgets('shows categorized title instead of raw error',
          (tester) async {
        await tester.pumpWidget(createWidget(error: 'Test error message'));

        final info = getErrorInfo(ErrorCategoryType.unknown);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows retry button when onRetry provided', (tester) async {
        var retryCalled = false;
        await tester.pumpWidget(createWidget(
          error: 'Test error',
          onRetry: () => retryCalled = true,
        ));

        expect(find.text('Retry'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        expect(retryCalled, isTrue);
      });

      testWidgets('hides retry button when onRetry is null', (tester) async {
        await tester.pumpWidget(createWidget(error: 'Test error'));

        expect(find.text('Retry'), findsNothing);
      });
    });

    group('smart categorization', () {
      testWidgets('shows network-specific title for network errors',
          (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Connection failed',
          errorObject: 'SocketException: Connection refused',
        ));

        final info = getErrorInfo(ErrorCategoryType.network);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows network-specific suggested action', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Connection failed',
          errorObject: 'SocketException: Connection refused',
        ));

        final info = getErrorInfo(ErrorCategoryType.network);
        expect(find.text(info.suggestedAction), findsOneWidget);
      });

      testWidgets('shows authentication-specific title', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Auth failed',
          errorObject: 'HTTP 401: Unauthorized',
        ));

        final info = getErrorInfo(ErrorCategoryType.authentication);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows validation-specific title', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Bad input',
          errorObject: 'Validation failed: required field',
        ));

        final info = getErrorInfo(ErrorCategoryType.validation);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows not found-specific title', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Not found',
          errorObject: 'HTTP 404: Not Found',
        ));

        final info = getErrorInfo(ErrorCategoryType.notFound);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows server error-specific title', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Server issue',
          errorObject: 'HTTP 500: Internal Server Error',
        ));

        final info = getErrorInfo(ErrorCategoryType.server);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows rate limit-specific title', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Too many',
          errorObject: 'HTTP 429: Too Many Requests',
        ));

        final info = getErrorInfo(ErrorCategoryType.rateLimit);
        expect(find.text(info.title), findsOneWidget);
      });
    });

    group('help button', () {
      testWidgets('shows "Get Help" button', (tester) async {
        await tester.pumpWidget(createWidget(error: 'Test error'));

        expect(find.text('Get Help'), findsOneWidget);
      });

      testWidgets('shows technical details in dialog on tap', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Test error message',
          errorObject: 'Detailed technical info',
        ));

        await tester.tap(find.text('Get Help'));
        await tester.pumpAndSettle();

        expect(find.text('Technical Details'), findsOneWidget);
        expect(find.text('Detailed technical info'), findsOneWidget);
      });

      testWidgets('can close help dialog', (tester) async {
        await tester.pumpWidget(createWidget(error: 'Test error'));

        await tester.tap(find.text('Get Help'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        expect(find.text('Technical Details'), findsNothing);
      });
    });

    group('icons', () {
      testWidgets('shows wifi_off icon for network errors', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Network error',
          errorObject: 'SocketException',
        ));

        final info = getErrorInfo(ErrorCategoryType.network);
        expect(find.byIcon(info.icon), findsOneWidget);
      });

      testWidgets('shows lock icon for authentication errors', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Auth error',
          errorObject: '401 Unauthorized',
        ));

        final info = getErrorInfo(ErrorCategoryType.authentication);
        expect(find.byIcon(info.icon), findsOneWidget);
      });
    });

    group('without errorObject (backward compat)', () {
      testWidgets('falls back to error text for categorization',
          (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'SocketException: Connection refused',
        ));

        final info = getErrorInfo(ErrorCategoryType.network);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows generic icon for unknown errors', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Some random error',
        ));

        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      });
    });
  });
}
