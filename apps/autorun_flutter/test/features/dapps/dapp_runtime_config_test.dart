// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/config/example_dapps.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unit coverage for [DappRuntimeConfig]: the override-wins-over-default rule
/// (which also proves a full save→load round-trip), per-field partial override,
/// and [DappRuntimeConfig.clear] restoring defaults.
void main() {
  const DappDescriptor descriptor = DappDescriptor(
    id: 'test_dapp',
    title: 'Test Dapp',
    description: 'desc',
    emoji: '🧪',
    backendCanisterId: 'default-canister-id',
    host: 'http://default-host',
    frontendUrl: 'http://default-frontend',
    bundleAssetPath: 'lib/examples/none.js',
  );

  setUp(() {
    // Fresh, isolated SharedPreferences store per test.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('DappRuntimeConfig.load', () {
    test('returns descriptor defaults when no override is stored', () async {
      final cfg = await DappRuntimeConfig.load(descriptor);
      expect(cfg.backendCanisterId, descriptor.backendCanisterId);
      expect(cfg.host, descriptor.host);
    });

    test('stored override wins over the descriptor default', () async {
      await DappRuntimeConfig.save(
        descriptor.id,
        backendCanisterId: 'my-replica-canister',
        host: 'http://192.168.1.5:8080',
      );

      final cfg = await DappRuntimeConfig.load(descriptor);
      expect(cfg.backendCanisterId, 'my-replica-canister');
      expect(cfg.host, 'http://192.168.1.5:8080');
    });

    test('an empty-string override falls back to the default', () async {
      // Saving an empty string clears the effective value back to default — a
      // user who blanks the field restores the shipped value, not a blank.
      await DappRuntimeConfig.save(
        descriptor.id,
        backendCanisterId: '',
        host: '',
      );

      final cfg = await DappRuntimeConfig.load(descriptor);
      expect(cfg.backendCanisterId, descriptor.backendCanisterId);
      expect(cfg.host, descriptor.host);
    });
  });

  group('DappRuntimeConfig round-trip', () {
    test('save updates only the field passed (partial override)', () async {
      await DappRuntimeConfig.save(descriptor.id, backendCanisterId: 'only-id');

      expect((await DappRuntimeConfig.load(descriptor)).backendCanisterId,
          'only-id');
      // host untouched → default.
      expect((await DappRuntimeConfig.load(descriptor)).host,
          descriptor.host);
    });
  });

  group('DappRuntimeConfig.clear', () {
    test('removes overrides so load yields defaults again', () async {
      await DappRuntimeConfig.save(
        descriptor.id,
        backendCanisterId: 'override-id',
        host: 'http://override-host',
      );
      expect((await DappRuntimeConfig.load(descriptor)).backendCanisterId,
          'override-id');

      await DappRuntimeConfig.clear(descriptor.id);

      final cfg = await DappRuntimeConfig.load(descriptor);
      expect(cfg.backendCanisterId, descriptor.backendCanisterId);
      expect(cfg.host, descriptor.host);
    });
  });

  group('exampleDapps registry', () {
    test('ships the on-chain poll dapp with the documented defaults', () {
      expect(exampleDapps, isNotEmpty);
      final poll =
          exampleDapps.firstWhere((d) => d.id == 'icp_poll');
      expect(poll.title, 'On-chain Polls');
      expect(poll.bundleAssetPath, 'lib/examples/06_icp_poll.js');
      // Defaults must reference the single source of truth constants.
      expect(poll.backendCanisterId, kLocalPollBackendCanisterId);
      expect(poll.host, kLocalPollHost);
      expect(poll.frontendUrl, kLocalPollFrontendUrl);
      expect(poll.hasBackendDirect, isTrue);
      expect(poll.hasFrontendBrowser, isTrue);
    });
  });
}
