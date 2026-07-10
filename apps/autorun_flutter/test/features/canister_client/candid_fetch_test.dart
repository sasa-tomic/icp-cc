import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/config/app_config.dart';
import 'package:icp_autorun/services/candid_service.dart';

const _canisterId = 'rrkah-fqaaa-aaaaa-aaaaq-cai';

/// Builds a [MockClient] that asserts the single-source User-Agent header
/// (TD-6 owns `AppConfig.userAgent`; TD-3 references it) is on every request,
/// then returns the canned response.
http.Client _statusClient(int status, {String body = ''}) =>
    MockClient((request) async {
      expect(request.headers['User-Agent'], AppConfig.userAgent);
      return http.Response(body, status);
    });

http.Client _throwingClient(Object error) =>
    MockClient((_) async => throw error);

/// Runs [service.fetchCanisterMethods], expecting it to throw a
/// [CandidFetchException]; returns the captured exception for field assertions.
Future<CandidFetchException> _expectFetchError(
  CandidService service,
) async {
  late final CandidFetchException captured;
  try {
    await service.fetchCanisterMethods(_canisterId);
    fail('expected CandidFetchException');
  } on CandidFetchException catch (e) {
    captured = e;
  }
  return captured;
}

void main() {
  group('CandidService candid fetch (TD-3)', () {
    test('200 + body returns the parsed Candid methods', () async {
      // Method on its own line — the parser skips `service :` declaration
      // lines, so a single-line Candid would parse to nothing.
      const candid = 'service : {\n  hello : () -> ();\n}';
      final service =
          CandidService(httpClient: _statusClient(200, body: candid));

      final methods = await service.fetchCanisterMethods(_canisterId);

      expect(methods, isNotEmpty);
      expect(methods.first.name, 'hello');
    });

    test('non-200 status throws typed CandidFetchException (non200)',
        () async {
      final service = CandidService(
        httpClient: _statusClient(503, body: 'Service Unavailable'),
      );

      final err = await _expectFetchError(service);

      expect(err.kind, CandidFetchErrorKind.non200);
      expect(err.statusCode, 503);
      expect(err.body, 'Service Unavailable');
      expect(err.canisterId, _canisterId);
    });

    test('404 maps to the non200 variant too', () async {
      final service = CandidService(
        httpClient: _statusClient(404, body: 'Not Found'),
      );

      final err = await _expectFetchError(service);

      expect(err.kind, CandidFetchErrorKind.non200);
      expect(err.statusCode, 404);
    });

    test('200 + empty body throws typed CandidFetchException (emptyBody)',
        () async {
      final service =
          CandidService(httpClient: _statusClient(200, body: ''));

      final err = await _expectFetchError(service);

      expect(err.kind, CandidFetchErrorKind.emptyBody);
      expect(err.statusCode, 200);
    });

    test('network failure throws typed CandidFetchException (network)',
        () async {
      final service = CandidService(
        httpClient: _throwingClient(http.ClientException('Connection refused')),
      );

      final err = await _expectFetchError(service);

      expect(err.kind, CandidFetchErrorKind.network);
      expect(err.cause, isA<http.ClientException>());
    });

    test('timeout surfaces as a network CandidFetchException', () {
      fakeAsync((async) {
        final service = CandidService(
          httpClient:
              MockClient((_) async => Completer<http.Response>().future),
        );

        Object? captured;
        service.fetchCanisterMethods(_canisterId).then<void>(
              (_) {},
              onError: (Object e) => captured = e,
            );

        async.flushMicrotasks();
        // AppDurations.networkRequest == 30s; elapse past it.
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();

        expect(captured, isA<CandidFetchException>());
        expect(
          (captured as CandidFetchException).kind,
          CandidFetchErrorKind.network,
        );
      });
    });

    test('exception message renders canister + body + code', () async {
      final service = CandidService(
        httpClient: _statusClient(500, body: 'boom'),
      );

      final err = await _expectFetchError(service);

      // The user-visible message the canister-call builder surfaces.
      expect(
        err.toString(),
        "Couldn't load Candid for $_canisterId: boom (500)",
      );
    });

    test(
        'no hardcoded fallback: a previously-bundled canister still hits the '
        'registry and surfaces a typed error when unreachable', () async {
      // The NNS governance canister id was previously served by an inline
      // _getFallbackCandid switch. After TD-3 it MUST come from the registry —
      // a network failure now propagates instead of returning stale Candid.
      final service = CandidService(
        httpClient: _throwingClient(http.ClientException('offline')),
      );

      late final CandidFetchException captured;
      try {
        await service.fetchCanisterMethods('rrkah-fqaaa-aaaaa-aaaaq-cai');
        fail('expected CandidFetchException');
      } on CandidFetchException catch (e) {
        captured = e;
      }
      expect(captured.kind, CandidFetchErrorKind.network);
    });
  });

  // A-W6-11: the Candid registry host must be a single named constant, not an
  // inline magic literal. These tests pin the const value + that requests hit
  // that exact host (so the literal cannot silently drift back inline).
  group('CandidService registry host (A-W6-11)', () {
    test('kCandidRegistryHost is the canonical Candid registry value', () {
      expect(kCandidRegistryHost, 'https://icp-api.io');
    });

    test('fetch targets the canonical host when no host override is given',
        () async {
      String? requestedUrl;
      const candid = 'service : {\n  hello : () -> ();\n}';
      final client = MockClient((request) async {
        requestedUrl = request.url.toString();
        return http.Response(candid, 200);
      });
      final service = CandidService(httpClient: client);

      await service.fetchCanisterMethods(_canisterId);

      // The host portion must be the named const, not an inline literal.
      expect(
        requestedUrl,
        '$kCandidRegistryHost/api/v2/canister/$_canisterId/candid',
      );
    });
  });
}
