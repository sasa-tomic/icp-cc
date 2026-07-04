// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/example_dapps.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unit coverage for [DappTrustStore] — the persisted "Trust this dapp" grant
/// introduced by UX-10. Asserts the storage round-trip (the property the
/// host's restart-skip-prompt behaviour depends on), the default-false
/// contract, and [DappTrustStore.clear].
void main() {
  const String dappId = 'test_dapp';

  setUp(() {
    // Fresh, isolated SharedPreferences store per test.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('DappTrustStore', () {
    test('isTrusted defaults to false for an unseen dapp id', () async {
      expect(await DappTrustStore.isTrusted(dappId), isFalse);
    });

    test('setTrusted persists the grant (loadable on a "restart")', () async {
      await DappTrustStore.setTrusted(dappId);
      // Simulate a restart: a fresh SharedPreferences read in a new process
      // would see the same value because it was persisted.
      expect(await DappTrustStore.isTrusted(dappId), isTrue);
    });

    test('setTrusted is idempotent', () async {
      await DappTrustStore.setTrusted(dappId);
      await DappTrustStore.setTrusted(dappId);
      expect(await DappTrustStore.isTrusted(dappId), isTrue);
    });

    test('clear removes the grant (next isTrusted returns false)', () async {
      await DappTrustStore.setTrusted(dappId);
      expect(await DappTrustStore.isTrusted(dappId), isTrue);
      await DappTrustStore.clear(dappId);
      expect(await DappTrustStore.isTrusted(dappId), isFalse);
    });

    test('grants are isolated per dapp id (no cross-talk)', () async {
      await DappTrustStore.setTrusted('dapp_A');
      expect(await DappTrustStore.isTrusted('dapp_A'), isTrue);
      expect(await DappTrustStore.isTrusted('dapp_B'), isFalse,
          reason: 'A grant for one dapp must not trust another');
    });
  });
}
