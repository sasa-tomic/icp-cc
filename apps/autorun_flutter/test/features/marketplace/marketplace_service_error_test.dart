import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';

http.Client _statusClient(int status, {String body = ''}) =>
    MockClient((_) async => http.Response(body, status));

http.Client _throwingClient(Object error) =>
    MockClient((_) async => throw error);

Matcher _exceptionMessageContaining(String fragment) => throwsA(
      isA<Exception>().having(
        (e) => e.toString(),
        'message',
        contains(fragment),
      ),
    );

void main() {
  late MarketplaceOpenApiService service;

  setUp(() {
    suppressDebugOutput = true;
    AppConfig.setTestEndpoint('https://mock.api');
    service = MarketplaceOpenApiService();
  });

  tearDown(() {
    suppressDebugOutput = false;
    service.resetHttpClient();
  });

  group('HTTP 5xx server errors', () {
    test('searchScripts surfaces 500 as Exception carrying the status', () {
      service.overrideHttpClient(_statusClient(500));
      expect(
        service.searchScripts(),
        _exceptionMessageContaining('HTTP 500'),
      );
    });

    test('uploadScript surfaces 500 and extracts server error from JSON body',
        () {
      service.overrideHttpClient(_statusClient(
        500,
        body: jsonEncode({'error': 'database is down'}),
      ));
      expect(
        service.uploadScript(
          slug: 's',
          title: 't',
          description: 'd',
          category: 'Utilities',
          tags: const [],
          bundle: 'print(1)',
        ),
        throwsA(
          isA<Exception>()
              .having((e) => e.toString(), 'status prefix',
                  contains('Upload failed (HTTP 500)'))
              .having((e) => e.toString(), 'server error detail',
                  contains('database is down')),
        ),
      );
    });

    test('getMarketplaceStats surfaces 503 even without try/catch wrapper',
        () {
      service.overrideHttpClient(_statusClient(503));
      expect(
        service.getMarketplaceStats(),
        _exceptionMessageContaining('HTTP 503'),
      );
    });
  });

  group('401/403 auth failures (not specially typed)', () {
    test('searchScripts surfaces 401 as plain Exception with the status', () {
      service.overrideHttpClient(_statusClient(401));
      expect(
        service.searchScripts(),
        _exceptionMessageContaining('HTTP 401'),
      );
    });

    test('uploadScript surfaces 403 with the Upload failed prefix', () {
      service.overrideHttpClient(_statusClient(403));
      expect(
        service.uploadScript(
          slug: 's',
          title: 't',
          description: 'd',
          category: 'Utilities',
          tags: const [],
          bundle: 'print(1)',
        ),
        _exceptionMessageContaining('Upload failed (HTTP 403)'),
      );
    });
  });

  group('404 not-found handling', () {
    test('getScriptDetails throws Script not found on 404', () {
      service.overrideHttpClient(_statusClient(404, body: 'missing'));
      expect(
        service.getScriptDetails('script-404'),
        _exceptionMessageContaining('Script not found'),
      );
    });

    test('getAccount returns null on 404 (not found is not an error)', () async {
      service.overrideHttpClient(_statusClient(404, body: 'missing'));
      final result = await service.getAccount(username: 'nobody');
      expect(result, isNull);
    });

    test('getAccountByPublicKey returns null on 404', () async {
      service.overrideHttpClient(_statusClient(404, body: 'missing'));
      final result =
          await service.getAccountByPublicKey(publicKeyB64: 'dGVzdA==');
      expect(result, isNull);
    });
  });

  group('malformed JSON body', () {
    test('searchScripts throws FormatException on non-JSON 200 body', () {
      service.overrideHttpClient(_statusClient(200, body: 'not-json{'));
      expect(
        service.searchScripts(),
        throwsA(isA<FormatException>()),
      );
    });

    test('getScriptDetails throws FormatException on malformed JSON', () {
      service.overrideHttpClient(_statusClient(200, body: '<<<garbage>>>'));
      expect(
        service.getScriptDetails('script-1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('getAccount throws FormatException on non-JSON 200 body', () {
      service.overrideHttpClient(_statusClient(200, body: 'totally not json'));
      expect(
        service.getAccount(username: 'alice'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('timeout (real .timeout wiring, Duration seconds:45)', () {
    test('searchScripts propagates TimeoutException when request exceeds 45s',
        () {
      fakeAsync((async) {
        final client = MockClient((_) => Completer<http.Response>().future);
        service.overrideHttpClient(client);

        Object? captured;
        service.searchScripts().then<void>(
              (_) {},
              onError: (Object e) {
                captured = e;
              },
            );

        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 46));
        async.flushMicrotasks();

        expect(captured, isA<TimeoutException>());
      });
    });

    test('uploadScript (POST) propagates TimeoutException on timeout', () {
      fakeAsync((async) {
        final client = MockClient((_) => Completer<http.Response>().future);
        service.overrideHttpClient(client);

        Object? captured;
        service
            .uploadScript(
              slug: 's',
              title: 't',
              description: 'd',
              category: 'Utilities',
              tags: const [],
              bundle: 'print(1)',
            )
            .then<void>(
              (_) {},
              onError: (Object e) {
                captured = e;
              },
            );

        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 46));
        async.flushMicrotasks();

        expect(captured, isA<TimeoutException>());
      });
    });
  });

  group('network failure / transport error', () {
    test('searchScripts propagates http.ClientException unchanged', () {
      service.overrideHttpClient(
          _throwingClient(http.ClientException('Connection refused')));
      expect(
        service.searchScripts(),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('uploadScript propagates http.ClientException unchanged', () {
      service.overrideHttpClient(
          _throwingClient(http.ClientException('Connection terminated')));
      expect(
        service.uploadScript(
          slug: 's',
          title: 't',
          description: 'd',
          category: 'Utilities',
          tags: const [],
          bundle: 'print(1)',
        ),
        throwsA(isA<http.ClientException>()),
      );
    });

    test(
        'registerAccount propagates http.ClientException '
        '(request signature is forwarded, not verified by service)', () {
      service.overrideHttpClient(
          _throwingClient(http.ClientException('Socket closed')));
      final request = RegisterAccountRequest(
        username: 'alice',
        displayName: 'Alice',
        publicKeyB64: 'dGVzdA==',
        timestamp: 1700000000,
        nonce: '11111111-1111-1111-1111-111111111111',
        signature: 'cGxhY2Vob2xkZXI=',
      );
      expect(
        service.registerAccount(request),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('success:false envelope and server error extraction', () {
    test('searchScripts throws the envelope error when success:false on 200',
        () {
      service.overrideHttpClient(_statusClient(
        200,
        body: jsonEncode({'success': false, 'error': 'malformed query'}),
      ));
      expect(
        service.searchScripts(),
        _exceptionMessageContaining('malformed query'),
      );
    });

    test('updateScript surfaces server error field from non-2xx JSON body', () {
      service.overrideHttpClient(_statusClient(
        409,
        body: jsonEncode({'error': 'version conflict'}),
      ));
      expect(
        service.updateScript('script-1', title: 'new'),
        _exceptionMessageContaining('version conflict'),
      );
    });

    test('deleteScript surfaces server error field from non-2xx JSON body', () {
      service.overrideHttpClient(_statusClient(
        403,
        body: jsonEncode({'error': 'not the author'}),
      ));
      expect(
        service.deleteScript('script-1'),
        _exceptionMessageContaining('not the author'),
      );
    });

    test(
        'registerAccount surfaces status and server detail on non-2xx '
        '(signature forwarded, not verified)', () {
      service.overrideHttpClient(_statusClient(
        409,
        body: jsonEncode({'error': 'username already taken'}),
      ));
      final request = RegisterAccountRequest(
        username: 'alice',
        displayName: 'Alice',
        publicKeyB64: 'dGVzdA==',
        timestamp: 1700000000,
        nonce: '11111111-1111-1111-1111-111111111111',
        signature: 'cGxhY2Vob2xkZXI=',
      );
      expect(
        service.registerAccount(request),
        throwsA(
          isA<Exception>()
              .having((e) => e.toString(), 'status line',
                  contains('Account registration failed (HTTP 409)'))
              .having((e) => e.toString(), 'server detail',
                  contains('username already taken')),
        ),
      );
    });
  });

  group('response-shape edge cases', () {
    test('getScriptDetails throws when data field is null', () {
      service.overrideHttpClient(_statusClient(
        200,
        body: jsonEncode({'success': true, 'data': null}),
      ));
      expect(
        service.getScriptDetails('script-1'),
        _exceptionMessageContaining('missing data field'),
      );
    });

    test('getScriptDetails throws when data is not an object', () {
      service.overrideHttpClient(_statusClient(
        200,
        body: jsonEncode({'success': true, 'data': [1, 2, 3]}),
      ));
      expect(
        service.getScriptDetails('script-1'),
        _exceptionMessageContaining('not a valid object'),
      );
    });

    test('uploadScript throws on empty 200 response body', () {
      service.overrideHttpClient(_statusClient(200, body: ''));
      expect(
        service.uploadScript(
          slug: 's',
          title: 't',
          description: 'd',
          category: 'Utilities',
          tags: const [],
          bundle: 'print(1)',
        ),
        _exceptionMessageContaining('Empty response from server'),
      );
    });
  });
}
