import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/candid_service.dart';

const _canisterId = 'rrkah-fqaaa-aaaaa-aaaaq-cai';

/// R-3 (fixed 2026-07-23): CandidService now uses the certified `read_state`
/// `candid:service` path via FFI instead of the dead HTTP registry
/// (`icp-api.io`). These tests inject a [CandidFetcher] fake to assert
/// behavior without a native library.
void main() {
  group('CandidService candid fetch (R-3 read_state path)', () {
    test('valid Candid string returns parsed methods', () async {
      const candid = 'service : {\n  hello : () -> ();\n}';
      final service = CandidService(
        fetchCandid: (_, __) async => candid,
      );

      final methods = await service.fetchCanisterMethods(_canisterId);

      expect(methods, isNotEmpty);
      expect(methods.first.name, 'hello');
    });

    test('null read_state result throws CandidFetchException', () async {
      final service = CandidService(fetchCandid: (_, __) async => null);

      late final CandidFetchException captured;
      try {
        await service.fetchCanisterMethods(_canisterId);
        fail('expected CandidFetchException');
      } on CandidFetchException catch (e) {
        captured = e;
      }

      expect(captured.kind, CandidFetchErrorKind.fetchFailed);
      expect(captured.canisterId, _canisterId);
    });

    test('empty read_state result throws CandidFetchException', () async {
      final service = CandidService(fetchCandid: (_, __) async => '');

      late final CandidFetchException captured;
      try {
        await service.fetchCanisterMethods(_canisterId);
        fail('expected CandidFetchException');
      } on CandidFetchException catch (e) {
        captured = e;
      }

      expect(captured.kind, CandidFetchErrorKind.fetchFailed);
    });

    test('read_state throwing is caught and surfaces as CandidFetchException',
        () async {
      final service = CandidService(
        fetchCandid: (_, __) async => throw Exception('network unreachable'),
      );

      late final CandidFetchException captured;
      try {
        await service.fetchCanisterMethods(_canisterId);
        fail('expected CandidFetchException');
      } on CandidFetchException catch (e) {
        captured = e;
      }

      expect(captured.kind, CandidFetchErrorKind.fetchFailed);
    });

    test('exception message renders canister id + read_state context',
        () async {
      final service = CandidService(fetchCandid: (_, __) async => null);

      late final CandidFetchException captured;
      try {
        await service.fetchCanisterMethods(_canisterId);
        fail('expected CandidFetchException');
      } on CandidFetchException catch (e) {
        captured = e;
      }

      expect(
        captured.toString(),
        contains(_canisterId),
      );
      expect(
        captured.toString(),
        contains('read_state'),
      );
    });

    test(
        'no hardcoded fallback: a previously-bundled canister still hits '
        'read_state and surfaces a typed error when unreachable', () async {
      // The NNS governance canister id was previously served by an inline
      // _getFallbackCandid switch. After R-3 it MUST come from the certified
      // read_state path — a null result propagates instead of stale Candid.
      final service = CandidService(fetchCandid: (_, __) async => null);

      late final CandidFetchException captured;
      try {
        await service.fetchCanisterMethods('rrkah-fqaaa-aaaaa-aaaaq-cai');
        fail('expected CandidFetchException');
      } on CandidFetchException catch (e) {
        captured = e;
      }
      expect(captured.kind, CandidFetchErrorKind.fetchFailed);
    });

    test('host override is passed through to the fetcher', () async {
      String? capturedHost;
      const candid = 'service : {\n  hello : () -> ();\n}';
      final service = CandidService(
        fetchCandid: (_, host) async {
          capturedHost = host;
          return candid;
        },
      );

      await service.fetchCanisterMethods(_canisterId, 'https://ic0.app');

      expect(capturedHost, 'https://ic0.app');
    });

    test('multi-method Candid interface parses all methods', () async {
      const candid = '''
service : {
  symbol : () -> (text) query;
  name : () -> (text) query;
  transfer : (record { to : principal; amount : nat }) -> (variant { Ok : nat; Err : text });
}
''';
      final service = CandidService(
        fetchCandid: (_, __) async => candid,
      );

      final methods = await service.fetchCanisterMethods(_canisterId);

      expect(methods.length, 3);
      expect(methods.where((m) => m.mode == 0).length, 2); // 2 queries
      expect(methods.where((m) => m.mode == 1).length, 1); // 1 update
      expect(methods.any((m) => m.name == 'symbol'), isTrue);
      expect(methods.any((m) => m.name == 'transfer'), isTrue);
    });
  });
}
