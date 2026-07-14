import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/theme/app_design_system.dart';

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

  group('isUsernameAvailable (TD-7: status code, not .contains("404"))', () {
    test('returns true when the backend reports 404 (username is free)',
        () async {
      service.overrideHttpClient(_statusClient(404, body: 'missing'));
      expect(await service.isUsernameAvailable('nobody'), isTrue);
    });

    test('returns false when the account exists (200 with data)', () async {
      service.overrideHttpClient(MockClient((_) async => http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': 'acct-1',
                'username': 'alice',
                'createdAt': '2024-01-01T00:00:00.000Z',
                'updatedAt': '2024-01-01T00:00:00.000Z',
              },
            }),
            200,
          )));
      expect(await service.isUsernameAvailable('alice'), isFalse);
    });

    test('rethrows 5xx — a server error is never mis-read as "available"', () {
      service.overrideHttpClient(_statusClient(500));
      expect(
        service.isUsernameAvailable('alice'),
        _exceptionMessageContaining('HTTP 500'),
      );
    });

    test('rethrows transport errors (not swallowed as available)', () {
      service.overrideHttpClient(
          _throwingClient(http.ClientException('Connection refused')));
      expect(
        service.isUsernameAvailable('alice'),
        throwsA(isA<http.ClientException>()),
      );
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

  group('per-call timeouts (UXR5-3: browse vs download budget wiring)', () {
    // A client that never responds — isolates the `.timeout(...)` budget from
    // any response handling. Mock lives only at the http.Client boundary.
    http.Client hangingClient() =>
        MockClient((_) => Completer<http.Response>().future);

    test('browse reads time out on the short browse budget (searchScripts)', () {
      fakeAsync((async) {
        service.overrideHttpClient(hangingClient());

        Object? captured;
        service.searchScripts().then<void>(
              (_) {},
              onError: (Object e) => captured = e,
            );

        async.flushMicrotasks();
        // Elapse just past the browse budget but far below the download budget.
        // If searchScripts were mis-wired to downloadTimeout this would leave
        // captured null (no timeout yet) and the expectation would fail.
        async.elapse(AppDurations.browseTimeout + const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(captured, isA<TimeoutException>());
      });
    });

    test('mutations outlast the browse window then time out on the download '
        'budget (uploadScript)', () {
      fakeAsync((async) {
        service.overrideHttpClient(hangingClient());

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
              onError: (Object e) => captured = e,
            );

        async.flushMicrotasks();
        // Browse budget elapsed: a mutation on the short budget would have
        // timed out here. uploadScript is on downloadTimeout, so it must hang.
        async.elapse(AppDurations.browseTimeout + const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(captured, isNull,
            reason: 'upload must use the download budget, not the browse one');

        // Past the download budget: now the mutation must time out.
        async.elapse(AppDurations.downloadTimeout);
        async.flushMicrotasks();
        expect(captured, isA<TimeoutException>());
      });
    });

    test('paid bundle download uses the download budget, not browse '
        '(downloadPaidScriptBundle)', () {
      fakeAsync((async) {
        service.overrideHttpClient(hangingClient());

        Object? captured;
        service
            .downloadPaidScriptBundle(
          'script-1',
          accountId: 'a',
          publicKeyB64: 'dGVzdA==',
          signatureB64: 'dGVzdA==',
          timestamp: 'ts',
          nonce: 'n',
        )
            .then<void>(
              (_) {},
              onError: (Object e) => captured = e,
            );

        async.flushMicrotasks();
        async.elapse(AppDurations.browseTimeout + const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(captured, isNull,
            reason: 'full-bundle download must use the download budget');

        async.elapse(AppDurations.downloadTimeout);
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

  group('getCompatibleScripts (W6-4: single canisterId, not a List)', () {
    // Regression: the old signature took List<String> canisterIds, validated
    // *every* id, then silently sent only canisterIds.first — callers passing
    // >1 id got compatibility for just the first with no warning. The endpoint
    // is single-canister, so the API now takes a single String up front and
    // cannot mislead a caller into thinking >1 id is honoured.
    const validId = 'aaaaa-bbbbb-ccccc-ddddd-eee';

    test('sends exactly the canister id passed, as a single string value',
        () async {
      String? capturedBody;
      service.overrideHttpClient(MockClient((req) async {
        capturedBody = req.body;
        return http.Response(
          jsonEncode({'success': true, 'data': <Map<String, dynamic>>[]}),
          200,
        );
      }));

      await service.getCompatibleScripts(validId);

      final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(decoded['canisterId'], validId);
      expect(decoded['canisterId'], isA<String>(),
          reason: 'endpoint gets one id, never the .first of a list');
      expect(decoded['limit'], 50);
    });

    test('rejects an invalid canister id before any network call', () async {
      // No client override: if validation leaked a request, the default client
      // would hit a real host. We assert the validation Exception fires first.
      expect(
        service.getCompatibleScripts('not-a-valid-id'),
        _exceptionMessageContaining('Invalid canister ID format'),
      );
    });

    test('forwards the limit override into the request body', () async {
      String? capturedBody;
      service.overrideHttpClient(MockClient((req) async {
        capturedBody = req.body;
        return http.Response(
          jsonEncode({'success': true, 'data': <Map<String, dynamic>>[]}),
          200,
        );
      }));

      await service.getCompatibleScripts(validId, limit: 5);

      expect((jsonDecode(capturedBody!) as Map<String, dynamic>)['limit'], 5);
    });

    test('returns parsed scripts on a successful 200 envelope', () async {
      service.overrideHttpClient(MockClient((_) async => http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {'id': 'script-1', 'title': 'Script One'},
              ],
            }),
            200,
          )));

      final result = await service.getCompatibleScripts(validId);
      expect(result, hasLength(1));
      expect(result.first.id, 'script-1');
      expect(result.first.title, 'Script One');
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

  // W6-3: the service must decode every envelope through one robust path. These
  // tests reproduce the exact failure modes the old per-method copy-paste had:
  //   * `!responseData['success']` crashes with a TypeError when `success` is
  //     omitted / null / a non-bool (string) instead of throwing a typed
  //     Exception carrying the status.
  //   * `getMarketplaceStats` passed unchecked `data` to `MarketplaceStats
  //     .fromJson`, so `data:null` → TypeError instead of a clear error.
  //   * `updateScript` / `deleteScript` did `jsonDecode(response.body)` inside
  //     the non-2xx branch, so a non-JSON 502 (HTML / empty) surfaced as a
  //     FormatException ("Unexpected end of input") that masked the status.
  group('W6-3: robust success / status / data decoding', () {
    group('fragile success flag (typed Exception, never a TypeError)', () {
      test('searchScripts with success omitted', () {
        service.overrideHttpClient(_statusClient(200,
            body: jsonEncode({
          'data': {'scripts': <Object>[], 'total': 0, 'hasMore': false}
        })));
        expect(service.searchScripts(), throwsA(isA<Exception>()));
      });

      test('searchScripts with success:null', () {
        service.overrideHttpClient(_statusClient(200,
            body: jsonEncode({
          'success': null,
          'data': {'scripts': <Object>[], 'total': 0, 'hasMore': false}
        })));
        expect(service.searchScripts(), throwsA(isA<Exception>()));
      });

      test('searchScripts with success:"true" (string, not bool)', () {
        service.overrideHttpClient(_statusClient(200,
            body: jsonEncode({
          'success': 'true',
          'data': {'scripts': <Object>[], 'total': 0, 'hasMore': false}
        })));
        expect(service.searchScripts(), throwsA(isA<Exception>()));
      });

      test('getMarketplaceStats with success omitted (no try/catch wrapper)',
          () {
        service.overrideHttpClient(_statusClient(200,
            body: jsonEncode({
          'data': {'totalScripts': 1}
        })));
        expect(service.getMarketplaceStats(), throwsA(isA<Exception>()));
      });

      test('uploadScript with success omitted surfaces Upload failed prefix',
          () {
        service.overrideHttpClient(_statusClient(200,
            body: jsonEncode({
          'data': {'id': 'x'}
        })));
        expect(
          service.uploadScript(
            slug: 's',
            title: 't',
            description: 'd',
            category: 'Utilities',
            tags: const [],
            bundle: 'print(1)',
          ),
          throwsA(isA<Exception>()
              .having((e) => e.toString(), 'upload prefix',
                  contains('Upload failed'))),
        );
      });
    });

    group('getMarketplaceStats data field', () {
      // data:null must throw a clear Exception — not a TypeError from
      // MarketplaceStats.fromJson(null)['totalScripts'].
      test('throws a clear Exception (not TypeError) when data is null', () {
        service.overrideHttpClient(_statusClient(
            200,
            body: jsonEncode({'success': true, 'data': null})));
        expect(
          service.getMarketplaceStats(),
          throwsA(isA<Exception>()
              .having((e) => e.toString(), 'mentions data',
                  contains('data'))),
        );
      });

      test('throws when data is present but not an object', () {
        service.overrideHttpClient(_statusClient(
            200,
            body: jsonEncode({'success': true, 'data': [1, 2, 3]})));
        expect(
          service.getMarketplaceStats(),
          throwsA(isA<Exception>()
              .having((e) => e.toString(), 'mentions data',
                  contains('data'))),
        );
      });
    });

    group(
        'non-JSON error bodies must not mask the HTTP status (no FormatException)',
        () {
      test('updateScript surfaces HTTP 502 on a non-JSON (HTML) error body',
          () {
        service.overrideHttpClient(_statusClient(
            502,
            body: '<html><body>502 Bad Gateway</body></html>'));
        expect(
          service.updateScript('script-1', title: 'new'),
          throwsA(isA<Exception>()
              .having((e) => e.toString(), 'carries status',
                  contains('HTTP 502'))
              .having((e) => e.toString(), 'not a decode error',
                  isNot(contains('FormatException')))),
        );
      });

      test('deleteScript surfaces HTTP 502 on an empty error body', () {
        service.overrideHttpClient(_statusClient(502, body: ''));
        expect(
          service.deleteScript('script-1'),
          throwsA(isA<Exception>()
              .having((e) => e.toString(), 'carries status',
                  contains('HTTP 502'))
              .having((e) => e.toString(), 'not a decode error',
                  isNot(contains('Unexpected end of input')))),
        );
      });
    });
  });

  // W7-7: residual robustness/DRY issues in marketplace_open_api_service.
  //   (a) null-unsafe `!responseData['success']` → opaque TypeError if the
  //       server omits the `success` flag (was in getCompatibleScripts).
  //   (b) 3 success-path sites bypassed `_decodeSuccessResponse` (hand-rolled
  //       jsonDecode + success check) — the duplication is what bred (a).
  //   (d) unguarded `as List` casts → raw CastError.
  //   (e) one-sided `> 299` status bound let 1xx through as "success".
  //
  // (W7-7c — getScriptVersions malformed-data — was retired in W7-8: the
  // Versions tab was removed because the backend ships no /versions route, so
  // the method, the ScriptVersion model, and MalformedVersionsResponseException
  // were deleted alongside the tab. The malformed-data contract is still
  // covered for sibling methods via the getCompatibleScripts tests below.)
  group('W7-7: null-safe success + typed cast errors', () {
    const validCanisterId = 'aaaaa-bbbbb-ccccc-ddddd-eee';

    group('getCompatibleScripts (was null-unsafe !responseData[success])', () {
      test(
          'throws a typed Exception (not TypeError) when success is omitted '
          '(W7-7a)', () {
        // Old code: `if (!responseData['success'])` → NoSuchMethodError /
        // TypeError on null. Must throw a typed Exception instead.
        service.overrideHttpClient(_statusClient(
          200,
          body: jsonEncode({'data': <Map<String, dynamic>>[]}),
        ));
        expect(
          service.getCompatibleScripts(validCanisterId),
          throwsA(isA<Exception>()),
        );
      });

      test(
          'throws a typed Exception (not CastError) when data is not a list '
          '(W7-7d)', () {
        // Old code: `responseData['data'] as List` → _TypeError when data is
        // a String. Must throw a typed Exception instead.
        service.overrideHttpClient(_statusClient(
          200,
          body: jsonEncode({'success': true, 'data': 'not-a-list'}),
        ));
        expect(
          service.getCompatibleScripts(validCanisterId),
          throwsA(isA<Exception>()
              .having((e) => e.toString(), 'mentions list',
                  contains('list'))),
        );
      });

      test('1xx is NOT treated as success (W7-7e: one-sided > 299 bound)', () {
        // Old code: `if (response.statusCode > 299)` → 100 falls through to
        // jsonDecode('') → FormatException that masks the status. The correct
        // bound is `< 200 || > 299` (centralised in _decodeSuccessResponse).
        service.overrideHttpClient(_statusClient(100, body: ''));
        expect(
          service.getCompatibleScripts(validCanisterId),
          throwsA(isA<Exception>()
              .having((e) => e.toString(), 'carries status',
                  contains('HTTP 100'))),
        );
      });
    });

    group('downloadPaidScriptBundle (was bypassing _decodeSuccessResponse)', () {
      test('1xx is NOT treated as success (W7-7e)', () {
        // Old code: `if (response.statusCode > 299)` after the 401/402 branches
        // → 100 falls through to jsonDecode('') → FormatException. Now routed
        // through _decodeSuccessResponse which uses `< 200 || > 299`.
        service.overrideHttpClient(_statusClient(100, body: ''));
        expect(
          () => service.downloadPaidScriptBundle(
            'script-1',
            accountId: 'a',
            publicKeyB64: 'pk',
            signatureB64: 'sig',
            timestamp: 'ts',
            nonce: 'n',
          ),
          throwsA(isA<Exception>()
              .having((e) => e.toString(), 'carries status',
                  contains('HTTP 100'))),
        );
      });

      test('throws a typed Exception when data is missing on 200 (W7-7b)', () {
        // Routed through _decodeDataField — a missing data field must produce a
        // clear Exception, not a null-dereference.
        service.overrideHttpClient(_statusClient(
          200,
          body: jsonEncode({'success': true}),
        ));
        expect(
          () => service.downloadPaidScriptBundle(
            'script-1',
            accountId: 'a',
            publicKeyB64: 'pk',
            signatureB64: 'sig',
            timestamp: 'ts',
            nonce: 'n',
          ),
          throwsA(isA<Exception>()
              .having((e) => e.toString(), 'mentions data',
                  contains('data'))),
        );
      });
    });
  });
}
