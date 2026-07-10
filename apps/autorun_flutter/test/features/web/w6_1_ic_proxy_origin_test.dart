// W6-1 — IC-agent proxy-origin resolution + friendly IC error mapping (VM).
//
// Pure-Dart CONTRACT tests for the two W6-1 helpers that live in
// `ic_agent_types.dart` (the shared pure-Dart contract imported by both the
// Web engine and the VM stub). Both helpers are split from browser I/O so they
// are unit-testable on the VM exactly like `ConnectivityService`'s probe seam.
//
//   - `resolveProxyOrigin` — the priority decision (override → API endpoint →
//     page origin). Bug 1: the previous fallback to `window.location.origin`
//     silently POSTed to the static file server on split-origin deploys.
//   - `friendlyIcErrorMessage` — maps raw `IcAgentLoadException` dumps (HTTP
//     status lines, server banners, HTML bodies) to a concise message. Bug 2:
//     raw exception stacks were rendered verbatim as the result text.

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/rust/web/ic_agent_types.dart';

void main() {
  group('resolveProxyOrigin (W6-1 Bug 1)', () {
    test(
        'explicit override wins (IC_AGENT_PROXY_HOST dart-define, highest '
        'priority)', () {
      expect(
        resolveProxyOrigin(
          override: 'http://override.example:9999',
          apiEndpoint: 'http://127.0.0.1:37245',
          locationOrigin: 'http://127.0.0.1:8099',
        ),
        'http://override.example:9999',
      );
    });

    test(
        'API endpoint is the fallback when override is unset — correct for '
        'split-origin deploys (frontend :8099, backend :37245)', () {
      // This is the Bug 1 regression: previously the fallback was
      // window.location.origin (:8099, the static file server) → the IC agent
      // POSTed fetchCandid to the Python static server → HTTP 501 HTML dumped
      // at the user. The API endpoint (:37245) hosts /api/v1/ic/relay.
      expect(
        resolveProxyOrigin(
          override: '',
          apiEndpoint: 'http://127.0.0.1:37245',
          locationOrigin: 'http://127.0.0.1:8099',
        ),
        'http://127.0.0.1:37245',
      );
    });

    test(
        'page origin is the LAST resort (correct only for same-origin '
        'reverse-proxy production deploys)', () {
      expect(
        resolveProxyOrigin(
          override: '',
          apiEndpoint: '',
          locationOrigin: 'https://app.example.com',
        ),
        'https://app.example.com',
      );
    });

    test('override beats a non-empty API endpoint', () {
      expect(
        resolveProxyOrigin(
          override: 'http://probe.local',
          apiEndpoint: 'https://icp-mp.kalaj.org',
          locationOrigin: 'https://app.example.com',
        ),
        'http://probe.local',
      );
    });
  });

  group('friendlyIcErrorMessage (W6-1 Bug 2)', () {
    test('maps an IcAgentLoadException dump to a concise friendly message', () {
      // The raw text the static server's 501 produces — server banner + HTML.
      final raw = 'IcAgentLoadException: agent-js fetchCandid failed: '
          'Server returned 501\n'
          'Server: SimpleHTTP/0.6 Python/3.13.5\n'
          '<!DOCTYPE HTML>\n<html lang="en"><head></head><body>...</body>';
      final friendly = friendlyIcErrorMessage(raw);
      expect(friendly, isNot(contains('IcAgentLoadException')));
      expect(friendly, isNot(contains('<!DOCTYPE')));
      expect(friendly, isNot(contains('Python')));
      expect(friendly, contains('canister'));
    });

    test('maps a raw 501 HTML body (no IcAgentLoadException prefix) to friendly',
        () {
      final raw = 'Server: SimpleHTTP/0.6 Python/3.13.5\r\n'
          'Content-Type: text/html\r\n\r\n'
          '<!DOCTYPE HTML><html><body>Error response</body></html>';
      final friendly = friendlyIcErrorMessage(raw);
      expect(friendly, isNot(contains('<html')));
      expect(friendly, isNot(contains('SimpleHTTP')));
      expect(friendly, contains('canister'));
    });

    test('passes through an already-friendly / typed error unchanged', () {
      // A candid decode error is a legitimate, friendly message — must NOT be
      // clobbered.
      const raw = 'could not parse candid for reply decode '
          '(method "symbol" not found)';
      expect(friendlyIcErrorMessage(raw), raw);
    });

    test('passes through an invalid-canister-id message unchanged', () {
      const raw = 'invalid canister id: not-a-real-id';
      expect(friendlyIcErrorMessage(raw), raw);
    });
  });
}
