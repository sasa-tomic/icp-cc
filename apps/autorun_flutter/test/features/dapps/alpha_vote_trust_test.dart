// ALPHA-Vote trust-store integration test (spec §9.3).
//
// Mirrors dapp_trust_store_test.dart but pinned to the alpha_vote descriptor
// id, so a future rename of the descriptor (or a regression that drops the
// trust gate wiring for this dapp specifically) is caught here.
//
// Three behavioural guarantees:
//   1. `DappTrustStore.isTrusted('alpha_vote')` returns false on a fresh
//      install (the trust gate fires on first run).
//   2. After `setTrusted('alpha_vote')`, the runner treats the dapp as
//      trusted (no re-prompt).
//   3. `DappTrustStore.clear('alpha_vote')` resets it (the revoke path).
//
// Also verifies the descriptor with id 'alpha_vote' exists in `exampleDapps`
// (guards against a refactor that drops it from the catalog by mistake).
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/example_dapps.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const String dappId = 'alpha_vote';

  setUp(() {
    // Fresh, isolated SharedPreferences store per test.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ALPHA-Vote trust gate (DappTrustStore for alpha_vote)', () {
    test('the alpha_vote descriptor is registered in exampleDapps', () {
      // Sanity: catch a refactor that drops the dapp or renames its id.
      final match = exampleDapps.firstWhere(
        (d) => d.id == dappId,
        orElse: () => throw StateError(
            'alpha_vote dapp descriptor missing from exampleDapps'),
      );
      expect(match.title, 'Neuron Voting');
      expect(match.bundleAssetPath, 'lib/examples/10_alpha_vote.js');
      expect(match.isMainnet, isTrue);
      // Authenticated NNS governance canister id (single source).
      expect(match.backendCanisterId, kMainnetNnsGovernanceCanisterId);
    });

    test('isTrusted(alpha_vote) defaults to false on a fresh install',
        () async {
      expect(await DappTrustStore.isTrusted(dappId), isFalse,
          reason: 'first run must surface the trust prompt');
    });

    test('setTrusted(alpha_vote) persists the grant (no re-prompt on restart)',
        () async {
      await DappTrustStore.setTrusted(dappId);
      expect(await DappTrustStore.isTrusted(dappId), isTrue);
    });

    test(
        'clear(alpha_vote) resets the grant (next run re-prompts — the revoke '
        'path the runner exposes via "Revoke trust")', () async {
      await DappTrustStore.setTrusted(dappId);
      expect(await DappTrustStore.isTrusted(dappId), isTrue);
      await DappTrustStore.clear(dappId);
      expect(await DappTrustStore.isTrusted(dappId), isFalse);
    });

    test(
        'alpha_vote grant is isolated from other dapp grants (no cross-talk)',
        () async {
      await DappTrustStore.setTrusted(dappId);
      expect(await DappTrustStore.isTrusted(dappId), isTrue);
      expect(await DappTrustStore.isTrusted('nns_proposals'), isFalse,
          reason: 'trusting alpha_vote must NOT trust other dapps');
      expect(await DappTrustStore.isTrusted('icp_poll'), isFalse);
    });
  });
}
