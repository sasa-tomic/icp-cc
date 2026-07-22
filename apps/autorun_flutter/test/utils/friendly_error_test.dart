import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/utils/friendly_error.dart';

void main() {
  group('friendlyErrorMessage', () {
    test('network family -> Could not connect to the server', () {
      expect(
        friendlyErrorMessage(SocketException('Connection refused')),
        'Could not connect to the server',
      );
      expect(
        friendlyErrorMessage(TimeoutException('slow', const Duration(seconds: 1))),
        'Could not connect to the server',
      );
      expect(
        friendlyErrorMessage(http.ClientException('reset')),
        'Could not connect to the server',
      );
    });

    test('authentication -> Your session has expired or is invalid', () {
      expect(
        friendlyErrorMessage(DownloadAuthException('403')),
        'Your session has expired or is invalid',
      );
    });

    test('validation -> The data provided is not valid', () {
      expect(
        friendlyErrorMessage(const FormatException('bad json')),
        'The data provided is not valid',
      );
      expect(
        friendlyErrorMessage(const PurchaseRequiredException(9.99)),
        'The data provided is not valid',
      );
    });

    test('server -> Something went wrong on our end', () {
      expect(
        friendlyErrorMessage(PaymentsNotConfiguredException()),
        'Something went wrong on our end',
      );
    });

    test('unknown -> An unexpected error occurred', () {
      expect(
        friendlyErrorMessage(StateError('boom')),
        'An unexpected error occurred',
      );
      expect(
        friendlyErrorMessage(Object()),
        'An unexpected error occurred',
      );
    });

    test('PasskeyException -> classified by status code', () {
      expect(
        friendlyErrorMessage(PasskeyException('Unauthorized', statusCode: 401)),
        'Your session has expired or is invalid',
      );
      expect(
        friendlyErrorMessage(PasskeyException('Not Found', statusCode: 404)),
        'The requested resource does not exist',
      );
    });

    test('context is prepended verbatim with a colon', () {
      expect(
        friendlyErrorMessage(
          SocketException('x'),
          context: 'Download failed',
        ),
        'Download failed: Could not connect to the server',
      );
    });

    test('empty context is treated as no context', () {
      expect(
        friendlyErrorMessage(SocketException('x'), context: ''),
        'Could not connect to the server',
      );
    });

    test('PlatformException -> unknown category, friendly message', () {
      // PlatformException is NOT in categorizeError's typed switches — it
      // falls through to 'unknown'. The user must never see the verbatim
      // 'PlatformException(code, detail, ...)' dump in the primary text.
      final err = PlatformException(code: '42', message: ' boom ');
      expect(
        friendlyErrorMessage(err),
        'An unexpected error occurred',
      );
    });
  });

  group('friendlyErrorDetail', () {
    test('strips Exception: prefix', () {
      expect(
        friendlyErrorDetail(Exception('something specific went wrong')),
        'something specific went wrong',
      );
    });

    test('returns null for opaque Instance of ... dumps', () {
      expect(friendlyErrorDetail(Object()), isNull);
      expect(friendlyErrorDetail(_Opaque()), isNull);
    });

    test('returns null when only an Exception: prefix remains after strip', () {
      expect(friendlyErrorDetail(Exception('')), isNull);
    });

    test('returns null for raw HTML server dumps', () {
      expect(
        friendlyErrorDetail('<!doctype html><html><body>500 Server Error</body></html>'),
        isNull,
      );
      expect(
        friendlyErrorDetail('<html>oops</html>'),
        isNull,
      );
    });

    test('passes through actionable messages verbatim', () {
      expect(
        friendlyErrorDetail(FormatException('Expected digit at offset 7')),
        'FormatException: Expected digit at offset 7',
      );
    });
  });
}

class _Opaque {}
