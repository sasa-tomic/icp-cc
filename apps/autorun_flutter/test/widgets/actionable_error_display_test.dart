import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icp_autorun/services/candid_service.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/utils/error_categories.dart';
import 'package:icp_autorun/utils/profile_errors.dart';
import 'package:icp_autorun/widgets/error_display.dart';

void main() {
  group('ErrorCategory', () {
    group('categorization by typed exception', () {
      test('null is unknown', () {
        expect(categorizeError(null), equals(ErrorCategoryType.unknown));
      });

      test('SocketException is network', () {
        expect(
          categorizeError(SocketException('Connection refused')),
          equals(ErrorCategoryType.network),
        );
      });

      test('TimeoutException is network', () {
        expect(
          categorizeError(
              TimeoutException('after 5s', const Duration(seconds: 5))),
          equals(ErrorCategoryType.network),
        );
      });

      test('TlsException is network', () {
        expect(
          categorizeError(const TlsException()),
          equals(ErrorCategoryType.network),
        );
      });

      test('HandshakeException (TlsException subclass) is network', () {
        expect(
          categorizeError(HandshakeException()),
          equals(ErrorCategoryType.network),
        );
      });

      test('HttpException is network', () {
        expect(
          categorizeError(HttpException('connection closed')),
          equals(ErrorCategoryType.network),
        );
      });

      test('http.ClientException is network', () {
        expect(
          categorizeError(http.ClientException('Failed to fetch')),
          equals(ErrorCategoryType.network),
        );
      });

      test('DownloadAuthException (HTTP 401) is authentication', () {
        expect(
          categorizeError(const DownloadAuthException('bad signature')),
          equals(ErrorCategoryType.authentication),
        );
      });

      test('BackupDecryptionException is authentication', () {
        expect(
          categorizeError(BackupDecryptionException()),
          equals(ErrorCategoryType.authentication),
        );
      });

      test('PasskeyException with 401 is authentication', () {
        expect(
          categorizeError(PasskeyException('unauthorized', statusCode: 401)),
          equals(ErrorCategoryType.authentication),
        );
      });

      test('PasskeyException with 403 is authentication', () {
        expect(
          categorizeError(PasskeyException('forbidden', statusCode: 403)),
          equals(ErrorCategoryType.authentication),
        );
      });

      test('PasskeyException with 404 is notFound', () {
        expect(
          categorizeError(PasskeyException('gone', statusCode: 404)),
          equals(ErrorCategoryType.notFound),
        );
      });

      test('PasskeyException with 429 is rateLimit', () {
        expect(
          categorizeError(PasskeyException('slow down', statusCode: 429)),
          equals(ErrorCategoryType.rateLimit),
        );
      });

      test('PasskeyException with 400 is validation', () {
        expect(
          categorizeError(PasskeyException('bad request', statusCode: 400)),
          equals(ErrorCategoryType.validation),
        );
      });

      test('PasskeyException with 402 is validation', () {
        expect(
          categorizeError(PasskeyException('payment required', statusCode: 402)),
          equals(ErrorCategoryType.validation),
        );
      });

      test('PasskeyException with 500 is server', () {
        expect(
          categorizeError(PasskeyException('boom', statusCode: 500)),
          equals(ErrorCategoryType.server),
        );
      });

      test('PasskeyException with 503 is server', () {
        expect(
          categorizeError(PasskeyException('unavailable', statusCode: 503)),
          equals(ErrorCategoryType.server),
        );
      });

      test('PasskeyException without statusCode is unknown', () {
        expect(
          categorizeError(PasskeyException('platform unsupported')),
          equals(ErrorCategoryType.unknown),
        );
      });

      test('PurchaseRequiredException (HTTP 402) is validation', () {
        expect(
          categorizeError(const PurchaseRequiredException(1.5)),
          equals(ErrorCategoryType.validation),
        );
      });

      test('ProfileAlreadyExistsException is validation (conflict)', () {
        expect(
          categorizeError(ProfileAlreadyExistsException('profile-1')),
          equals(ErrorCategoryType.validation),
        );
      });

      test('InvalidBackupFormatException is validation', () {
        expect(
          categorizeError(InvalidBackupFormatException('bad envelope')),
          equals(ErrorCategoryType.validation),
        );
      });

      test('FormatException is validation', () {
        expect(
          categorizeError(FormatException('not json')),
          equals(ErrorCategoryType.validation),
        );
      });

      test('PaymentsNotConfiguredException (HTTP 503) is server', () {
        expect(
          categorizeError(const PaymentsNotConfiguredException()),
          equals(ErrorCategoryType.server),
        );
      });

      test('CandidFetchException is categorized as network', () {
        expect(
          categorizeError(CandidFetchException(
            canisterId: 'x',
          )),
          equals(ErrorCategoryType.network),
        );
      });
    });

    group('heuristic failure modes are eliminated', () {
      // The old classifier substring-matched error.toString(); a message that
      // happened to contain "404" was misrouted. Type-first classification
      // makes that impossible.
      test(
          'SocketException whose toString contains "404" is network, NOT '
          'notFound', () {
        final error = SocketException('cached lookup for resource 404 failed');
        expect(error.toString().contains('404'), isTrue);
        expect(
          categorizeError(error),
          equals(ErrorCategoryType.network),
        );
      });

      test('plain String "HTTP 500" is unknown (no substring matching)', () {
        expect(
          categorizeError('HTTP 500: Internal Server Error'),
          equals(ErrorCategoryType.unknown),
        );
      });

      test('plain String "HTTP 404" is unknown (no substring matching)', () {
        expect(
          categorizeError('HTTP 404: Not Found'),
          equals(ErrorCategoryType.unknown),
        );
      });

      test('plain String "TimeoutException" is unknown (type wins, not text)',
          () {
        expect(
          categorizeError('TimeoutException after 30s'),
          equals(ErrorCategoryType.unknown),
        );
      });

      test('generic Exception with status-like message is unknown', () {
        expect(
          categorizeError(Exception('401 unauthorized 404 500')),
          equals(ErrorCategoryType.unknown),
        );
      });

      test('unrecognized gibberish String is unknown', () {
        expect(
          categorizeError('Some random error message'),
          equals(ErrorCategoryType.unknown),
        );
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

    group('smart categorization (by typed errorObject)', () {
      testWidgets('shows network-specific title for SocketException',
          (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Connection failed',
          errorObject: SocketException('Connection refused'),
        ));

        final info = getErrorInfo(ErrorCategoryType.network);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows network-specific suggested action', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Connection failed',
          errorObject: SocketException('Connection refused'),
        ));

        final info = getErrorInfo(ErrorCategoryType.network);
        expect(find.text(info.suggestedAction), findsOneWidget);
      });

      testWidgets('shows authentication-specific title for 401 PasskeyException',
          (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Auth failed',
          errorObject: PasskeyException('unauthorized', statusCode: 401),
        ));

        final info = getErrorInfo(ErrorCategoryType.authentication);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows validation-specific title for FormatException',
          (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Bad input',
          errorObject: FormatException('required field'),
        ));

        final info = getErrorInfo(ErrorCategoryType.validation);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows not found-specific title for 404 PasskeyException',
          (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Not found',
          errorObject: PasskeyException('gone', statusCode: 404),
        ));

        final info = getErrorInfo(ErrorCategoryType.notFound);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets(
          'shows server error-specific title for PaymentsNotConfiguredException',
          (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Server issue',
          errorObject: const PaymentsNotConfiguredException(),
        ));

        final info = getErrorInfo(ErrorCategoryType.server);
        expect(find.text(info.title), findsOneWidget);
      });

      testWidgets('shows rate limit-specific title for 429 PasskeyException',
          (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Too many',
          errorObject: PasskeyException('slow down', statusCode: 429),
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
          errorObject: SocketException('down'),
        ));

        final info = getErrorInfo(ErrorCategoryType.network);
        expect(find.byIcon(info.icon), findsOneWidget);
      });

      testWidgets('shows lock icon for authentication errors', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'Auth error',
          errorObject: PasskeyException('no', statusCode: 401),
        ));

        final info = getErrorInfo(ErrorCategoryType.authentication);
        expect(find.byIcon(info.icon), findsOneWidget);
      });
    });

    group('without errorObject (string-only)', () {
      testWidgets(
          'a plain string error without a typed object is unknown '
          '(no substring guessing)', (tester) async {
        await tester.pumpWidget(createWidget(
          error: 'SocketException: Connection refused',
        ));

        final info = getErrorInfo(ErrorCategoryType.unknown);
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
