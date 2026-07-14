// ignore_for_file: lines_longer_than_80_chars

// H — the vault full-UI lifecycle through a real app boot: setup → restart →
// unlock (decrypt locally) → wrong-password rejection. Closes the MEDIUM test
// gap where the vault chain was only verified in pieces (A-4 ZK round-trip in
// zk_integration_test.dart with real FFI; setup + unlock screens at widget
// level in passkey/screens_test.dart with a deterministic fake) but never
// driven as ONE chain through a running app with REAL client-side crypto and
// the REAL production screens.
//
// ════════════════════════════════════════════════════════════════════════════
// BACKEND-DATA APPROACH — OPTION (b): MOCK HTTP TRANSPORT, REAL FFI CRYPTO
// ════════════════════════════════════════════════════════════════════════════
// The vault POSTs/GETs `/api/v1/vault` as an OPAQUE BLOB. As of A-4 W4 the
// server is PROVABLY a pure opaque-blob store — it performs ZERO crypto and
// holds NO password field:
//     rg "encrypt_vault|aes_gcm|Aes256Gcm" backend/src   →  EMPTY
// (verified and documented in zk_integration_test.dart's header). The W4
// handlers only base64-decode the four-tuple, persist the bytes, and echo them
// verbatim on GET.
//
// Therefore the mock HTTP transport below (an in-memory opaque-blob store)
// loses NO zero-knowledge signal: it does byte-identical work to the real
// server. The load-bearing signal — REAL FFI Argon2id (64 MiB, t=3, p=4) +
// AES-256-GCM running inside a background isolate via `compute()`, plus the
// EXACT W4 wire contract `{account_id, encrypted_data, salt, nonce}` built by
// the production PasskeyService — runs UNMODIFIED against the real
// VaultCryptoService and the real screens. This mirrors zk_integration_test.dart
// (W5) exactly; this file layers the UI screens on top with the same faithful
// transport.
//
// Option (a) (the real backend via `just api-dev-up`) was REJECTED for this
// tier: the ux_probe suite deliberately runs WITHOUT a backend (every probe
// fakes a "no connectivity" baseline), and starting Postgres + cargo-building
// the API server inside this test would add a hard, slow, non-deterministic
// dependency — exactly the flakiness the suite forbids.
//
// The CLIENT-SIDE CRYPTO IS NEVER MOCKED (AGENTS.md). The screens use the
// DEFAULT `VaultCryptoService()` (real FFI) — NOT the deterministic fake used
// by passkey/screens_test.dart (which exists only so widget tests run on boxes
// where libicp_core is unavailable).
//
// ════════════════════════════════════════════════════════════════════════════
// "REAL APP BOOT" + RESIDUAL GAP (documented honestly, not faked)
// ════════════════════════════════════════════════════════════════════════════
// This probe boots the REAL app (lib/main.dart → app.main()) under the
// integration-test binding so the real init path runs (FFI loads the way the
// real app loads it, real ProfileController/AccountController are wired). A
// REAL profile is then created via a real ProfileController (real Ed25519
// keypair gen via FFI + real libsecret round-trip under the mock keyring — the
// r3_addendum pattern) to supply a real `account_id` (the vault blob is keyed
// by account_id).
//
// RESIDUAL GAP: the production vault screens (VaultPasswordSetupScreen /
// VaultUnlockScreen) are standalone widgets that are NOT YET wired into the
// app's navigation — verified:
//     rg "VaultPasswordSetupScreen|VaultUnlockScreen" lib
// matches only the screen files themselves + the widget test. They therefore
// cannot be reached by tapping through the booted app shell. To drive them
// end-to-end we mount the REAL production screen widgets in-tree (the
// r3_addendum Addendum-WU-4 pattern: pump the production widget against a real
// controller) using the REAL FFI VaultCryptoService and the REAL PasskeyService
// singleton. Every production code path the screens invoke (form validation →
// PasskeyService → VaultCryptoService → FFI isolate) runs unmodified; the only
// seams are the HTTP transport (see above) and the widget host.
//
// ════════════════════════════════════════════════════════════════════════════
// RESTART SIMULATION
// ════════════════════════════════════════════════════════════════════════════
// The unlock screen holds NO in-memory vault state: on each attempt it fetches
// the opaque blob fresh via `PasskeyService.getVault` and decrypts it locally.
// VaultCryptoService is stateless. So a "restart" is faithfully modeled by
// mounting a FRESH VaultUnlockScreen widget while the opaque blob persists in
// the (server-side) mock store — exactly the post-restart state of the world:
// the server still holds the blob, the device holds no vault plaintext, and the
// user must re-enter the password to decrypt.
//
// ════════════════════════════════════════════════════════════════════════════
// pumpAndSettle WORKAROUND
// ════════════════════════════════════════════════════════════════════════════
// The real FFI Argon2id derivation (~0.1–1 s) runs in a background isolate via
// `compute()`. While it runs the screen shows an indeterminate
// CircularProgressIndicator, which schedules frames forever → `pumpAndSettle`
// NEVER returns (the W3 implementer hit exactly this). We therefore drive with
// bounded `pump(Duration)` loops via `_waitUntil`, asserting on post-completion
// state (callback fired / error text shown). Integration-test pumps use real
// wall-clock time, so isolate messages from `compute()` are processed during the
// pumps (same mechanism f_dapp_vote_flow_test relies on for its bounded-pump
// async chains).
//
// Run UNDER the mock keyring (PASS 2 of `just test-ux-probe`):
//   DISPLAY=:99 LD_LIBRARY_PATH=/code/icp-cc/target/release \
//     scripts/run-with-mock-keyring.sh flutter test \
//       integration_test/ux_probe/h_vault_lifecycle_test.dart

@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/main.dart' as app;
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/vault_password_setup_screen.dart';
import 'package:icp_autorun/screens/vault_unlock_screen.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/services/profile_repository.dart';
import 'package:icp_autorun/services/vault_crypto_service.dart';

const String _kShotDir =
    '/code/icp-cc/docs/specs/ux_screenshots/vault_lifecycle';
const Size _kDesktopSize = Size(1440, 900);
const double _kDpr = 1.0;

// Strong passwords that satisfy the setup validator (>=12 chars, upper, lower,
// digit, special). The wrong one differs in every token.
const String _kCorrectPassword = 'VaultPass123!';
const String _kWrongPassword = 'WrongVault999!';
// Hardcoded by VaultPasswordSetupScreen._createVault (it encrypts '{}').
const String _kSetupPlaintext = '{}';

/// The W7-12 wire-contract field names (auth fields + opaque-blob fields).
/// Mirror of the production `kVaultField*` / action consts; re-declared so a
/// prod copy/paste drift is caught here, per the zk_integration_test.dart
/// convention. Note: NO `account_id` (resolved server-side from the verified
/// public key as of W7-12).
const Set<String> _kExpectedBodyKeys = <String>{
  'signature',
  'author_public_key',
  'author_principal',
  'timestamp',
  'nonce',
  'encrypted_data',
  'salt',
  'blob_nonce',
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'H: real boot → profile → setup vault → restart → unlock decrypts → '
      'wrong password fails loud (one lifecycle chain)', (tester) async {
    // ── 0. Reset state + loud FFI probe ───────────────────────────────────
    await _clearState();
    await tester.runAsync(() => ProfileRepository().deleteAllSecureData());
    await tester.pump();

    expect(VaultCryptoService.nativeLibAvailable(), isTrue,
        reason: 'libicp_core.so must load — set '
            'LD_LIBRARY_PATH=/code/icp-cc/target/release. Without it the real '
            'Argon2id+AES-GCM crypto cannot run and this test has no honest '
            'fallback.');

    // ── 1. Real app boot (real FFI load + real init path) ─────────────────
    tester.view.physicalSize = _kDesktopSize * _kDpr;
    tester.view.devicePixelRatio = _kDpr;
    await tester.runAsync(() => app.main());
    await tester.pump(const Duration(seconds: 2));
    await _dismissWizard(tester); // bounded; let the real shell come up.
    await _shot(binding, 'h_01_booted_shell', tester);

    // ── 2. Create a REAL profile → real account_id (vault blob key) ───────
    // r3_addendum pattern: real Ed25519 FFI gen + real libsecret round-trip
    // under the mock keyring. The profile.id is the vault account_id. (Profile
    // creation through the running app's own controller is proven end-to-end by
    // f_dapp_vote_flow_test; the standalone controller here is equivalent and
    // avoids reaching into the live tree's ProfileScope.)
    final profileController =
        ProfileController(profileRepository: ProfileRepository());
    late String accountId;
    late ProfileKeypair keypair;
    await tester.runAsync(() async {
      final profile = await profileController.createProfile(
        profileName: 'H Vault Owner',
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );
      accountId = profile.id;
      keypair = profileController.activeKeypair!;
    });
    await tester.pump(const Duration(seconds: 1));
    expect(accountId, isNotEmpty,
        reason: 'A real profile must be created (real FFI keypair gen + '
            'libsecret) to key the vault blob.');

    // ── 3. Install the mock opaque-blob store on the PasskeyService ───────
    // singleton (the ONLY transport seam; see file header). The store persists
    // across the "restart" between setup and unlock — that is the server-side
    // persistence a real restart preserves.
    final store = _VaultBlobStore();
    PasskeyService().overrideHttpClient(store.toClient());

    // =========================================================================
    // PHASE A — SETUP: real screen → enter password → confirm → submit → the
    // screen encrypts '{}' LOCALLY (real FFI) + POSTs the opaque blob.
    // =========================================================================
    //
    // The screen is hosted above a placeholder route via _VaultScreenHost so
    // the screen's success `Navigator.pop` reveals the placeholder instead of
    // emptying the root navigator (an empty root navigator triggers
    // SystemNavigator.pop, which stalls the next pumpWidget — _VaultScreenHost
    // keeps the navigator non-empty at all times).
    var setupCreated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: _VaultScreenHost(
          key: const Key('vault-phase-a'),
          screen: VaultPasswordSetupScreen(
            accountId: accountId,
            keypair: keypair,
            onVaultCreated: () => setupCreated = true,
            // DEFAULT VaultCryptoService → REAL FFI (NOT the widget-test fake).
          ),
        ),
      ),
    );
    await _pumpUntilScreenReady(tester);
    await _shot(binding, 'h_02_setup_screen', tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      _kCorrectPassword,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      _kCorrectPassword,
    );
    await tester.pump();
    final setupBtn = find.widgetWithText(ElevatedButton, 'Create Vault');
    expect(tester.widget<ElevatedButton>(setupBtn).enabled, isTrue,
        reason: 'SETUP pre: with a strong matching password the Create Vault '
            'button must be enabled.');

    await tester.tap(setupBtn);
    // Bounded-pump through the real Argon2id+AES-GCM isolate (NEVER
    // pumpAndSettle — the indeterminate spinner never settles; see header).
    final setupDone = await _waitUntil(tester, () => setupCreated,
        timeout: const Duration(seconds: 45));
    await _shot(binding, 'h_03_setup_done', tester);

    expect(setupDone, isTrue,
        reason: 'SETUP: onVaultCreated must fire — the screen must encrypt '
            'locally (real FFI) and POST the opaque blob successfully.');
    final setupBody = store.lastRequestBody;
    expect(setupBody, isNotNull, reason: 'createVault must POST a JSON body.');
    expect(
      setupBody!.keys.toSet(),
      equals(_kExpectedBodyKeys),
      reason: 'SETUP: wire body MUST be exactly the W4 opaque-blob four-tuple.',
    );
    expect(setupBody.containsKey('password'), isFalse,
        reason: 'SETUP ZK: the password MUST NOT be in the wire body.');
    expect(setupBody.containsKey('account_id'), isFalse,
        reason: 'SETUP W7-12: account_id must NOT be in the body (server-resolved).');
    expect(setupBody['author_public_key'], equals(keypair.publicKey));
    expect(store.hasRow(keypair.publicKey), isTrue,
        reason: 'SETUP: the opaque blob must be persisted server-side.');

    // =========================================================================
    // PHASE B — RESTART + UNLOCK (correct password): FRESH unlock screen, blob
    // still in the store. Real FFI decrypt → plaintext '{}'.
    // =========================================================================
    String? unlockedPlaintext;
    var unlockAOk = false;
    await tester.pumpWidget(
      MaterialApp(
        home: _VaultScreenHost(
          key: const Key('vault-phase-b'),
          screen: VaultUnlockScreen(
            accountId: accountId,
            keypair: keypair,
            onUnlocked: (plaintext) {
              unlockedPlaintext = plaintext;
              unlockAOk = true;
            },
            // DEFAULT VaultCryptoService → REAL FFI.
          ),
        ),
      ),
    );
    await _pumpUntilScreenReady(tester);
    await _shot(binding, 'h_04_unlock_screen', tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      _kCorrectPassword,
    );
    await tester.pump();
    final unlockBtn = find.widgetWithText(ElevatedButton, 'Unlock');
    expect(tester.widget<ElevatedButton>(unlockBtn).enabled, isTrue);

    await tester.tap(unlockBtn);
    final unlockDone = await _waitUntil(tester, () => unlockAOk,
        timeout: const Duration(seconds: 45));
    await _shot(binding, 'h_05_unlock_success', tester);

    expect(unlockDone, isTrue,
        reason: 'UNLOCK (correct pw): onUnlocked must fire — the SAME password '
            'must decrypt the persisted blob LOCALLY (A-4 zero-knowledge: the '
            'server returned opaque bytes; only the device derived the key).');
    expect(unlockedPlaintext, equals(_kSetupPlaintext),
        reason: 'UNLOCK: real FFI decrypt must recover the EXACT plaintext '
            "('{}') that setup encrypted — byte-faithful round-trip through "
            'screen → wire → store → wire → screen.');

    // =========================================================================
    // PHASE C — WRONG password (negative): FRESH unlock screen, enter a
    // DIFFERENT password → AES-256-GCM auth-tag rejection → LOUD error, NO
    // silent success, NO crash.
    // =========================================================================
    var wrongUnlockFired = false;
    await tester.pumpWidget(
      MaterialApp(
        home: _VaultScreenHost(
          key: const Key('vault-phase-c'),
          screen: VaultUnlockScreen(
            accountId: accountId,
            keypair: keypair,
            onUnlocked: (_) => wrongUnlockFired = true,
          ),
        ),
      ),
    );
    await _pumpUntilScreenReady(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      _kWrongPassword,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock'));

    final wrongDone = await _waitUntil(
      tester,
      () => _present(find.textContaining('Incorrect password'), tester),
      timeout: const Duration(seconds: 45),
    );
    await _shot(binding, 'h_06_wrong_password_error', tester);

    expect(wrongDone, isTrue,
        reason: 'WRONG pw: a clear error must be shown — the real FFI AES-GCM '
            'auth-tag MUST reject the wrong-derived key.');
    expect(wrongUnlockFired, isFalse,
        reason: 'WRONG pw: onUnlocked must NOT fire — no silent success and no '
            'garbage plaintext.');
    expect(
      _present(find.textContaining('Incorrect password'), tester),
      isTrue,
      reason: 'WRONG pw: the loud "Incorrect password" error must be visible '
          'to the user.',
    );

    // ignore: avoid_print
    print('H_VAULT_LIFECYCLE: PASS — setup → restart → unlock (decrypt) → '
        'wrong-pw-reject, all through real FFI + real production screens.');
  });
}

// ── Helpers ────────────────────────────────────────────────────────────────

/// Hosts [screen] above a placeholder route via a declarative Navigator so the
/// screen's success `Navigator.pop` is ABSORBED (onPopPage returns false)
/// instead of emptying the root navigator. An empty root navigator triggers
/// `SystemNavigator.pop`, which stalls the next `pumpWidget` and breaks the
/// setup→unlock→wrong-pw chain. Because [screen] is in the initial pages list,
/// it renders on the first frame (no post-frame push timing). The placeholder
/// route is always beneath it, so the navigator never goes empty.
class _VaultScreenHost extends StatelessWidget {
  const _VaultScreenHost({required this.screen, super.key});
  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      pages: [
        const MaterialPage<void>(child: _HostPlaceholder()),
        MaterialPage<void>(child: screen),
      ],
      // Absorb the screen's success-pop: the route stays, we move on via
      // pumpWidget. This is what prevents SystemNavigator.pop. (onPopPage is
      // the only declarative hook that can VETO a pop — onDidRemovePage fires
      // only after removal — so the deprecation is accepted here with an
      // explicit ignore.)
      // ignore: deprecated_member_use
      onPopPage: (route, dynamic result) => false,
    );
  }
}

class _HostPlaceholder extends StatelessWidget {
  const _HostPlaceholder();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('VAULT_HOST_ROOT')));
}

/// After pumpWidget-ing a [_VaultScreenHost], pump until the hosted vault
/// screen has mounted its form. Fails loud if the screen never appears.
Future<void> _pumpUntilScreenReady(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (tester.widgetList(find.byType(TextFormField)).isNotEmpty) return;
  }
  throw StateError('Vault screen did not render inside _VaultScreenHost.');
}

/// Wipe on-disk profile state so the boot is first-run clean (mirrors
/// r3_addendum_helpers.clearAddendumProfileState / ux_helpers.clearProfileState;
/// kept local so this probe is self-contained).
Future<void> _clearState() async {
  final xdg = Platform.environment['XDG_DATA_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    final dir = Directory('$xdg/com.example.icp_autorun');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
  final home = Platform.environment['HOME'] ?? '/tmp';
  final cacheDir = Directory('$home/.cache/data/com.example.icp_autorun');
  if (await cacheDir.exists()) {
    final profiles = File('${cacheDir.path}/profiles.json');
    if (await profiles.exists()) {
      await profiles.writeAsString('{"version":1,"profiles":[]}');
    }
  }
}

/// Bounded-pump until [ready] returns true. NEVER uses pumpAndSettle (the
/// real-FFI CircularProgressIndicator animates forever). Integration-test pumps
/// use real wall-clock time, so the background-isolate crypto completes during
/// the pumps.
Future<bool> _waitUntil(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 30),
  Duration step = const Duration(milliseconds: 200),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (ready()) return true;
  }
  return ready();
}

/// Dismiss the first-run wizard (bounded — pumpAndSettle never returns: the
/// Scripts screen kicks off marketplace fetches against the unreachable URL).
/// Mirrors r3_helpers.dismissWizardR3.
Future<void> _dismissWizard(WidgetTester tester) async {
  int guard = 0;
  while (!_present(find.byIcon(Icons.close), tester) && guard < 60) {
    await tester.pump(const Duration(milliseconds: 200));
    guard++;
  }
  if (_present(find.byIcon(Icons.close), tester)) {
    await tester.tap(find.byIcon(Icons.close).first);
  }
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

bool _present(Finder f, WidgetTester tester) => tester.any(f);

/// Capture a screenshot into the vault_lifecycle dir (evidence; same layer-tree
/// technique as r3_helpers.shotR3).
Future<void> _shot(
    IntegrationTestWidgetsFlutterBinding binding,
    String name,
    WidgetTester tester) async {
  await Directory(_kShotDir).create(recursive: true);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  final RenderView view = tester.binding.renderViews.first;
  final Size size = view.size.isEmpty ? _kDesktopSize : view.size;
  // Screenshot capture requires direct access to the render layer tree; this is
  // a legitimate test-only use of the protected member.
  // ignore: invalid_use_of_protected_member
  final OffsetLayer layer = view.layer! as OffsetLayer;
  final ui.Image image =
      await layer.toImage(Offset.zero & size, pixelRatio: _kDpr);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw StateError('Failed to encode screenshot $name to PNG.');
  }
  await File('$_kShotDir/$name.png').writeAsBytes(byteData.buffer.asUint8List());
  image.dispose();
}

// ── Mock opaque-blob store (the W4 server, faithfully) ─────────────────────
//
// Faithful emulation of the A-4 W4 backend: stores the four-tuple from POST/PUT
// and returns those EXACT bytes from GET. Performs NO crypto, holds NO password
// field. Byte-identical to what the real server does (see file header). The
// store persists across the "restart" between PHASE A and PHASE B/C — that is
// the server-side persistence a real restart preserves.

class _VaultBlobStore {
  final Map<String, _StoredRow> _rows = <String, _StoredRow>{};

  /// Most-recent serialised POST/PUT body captured (for contract-shape asserts).
  Map<String, dynamic>? lastRequestBody;

  // Keyed by author_public_key (the server-resolved account identity as of
  // W7-12).
  bool hasRow(String publicKey) => _rows.containsKey(publicKey);

  http.Client toClient() => MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/api/v1/vault') &&
            (request.method == 'POST' || request.method == 'PUT')) {
          final body =
              (jsonDecode(request.body) as Map).cast<String, dynamic>();
          lastRequestBody = body;
          _rows[body['author_public_key'] as String] = _StoredRow(
            encryptedData: body['encrypted_data'] as String,
            salt: body['salt'] as String,
            nonce: body['blob_nonce'] as String,
          );
          return _resp(200, {'success': true});
        }
        // W7-12: GET became POST /vault/get with a signed body.
        if (path.endsWith('/api/v1/vault/get') && request.method == 'POST') {
          final body =
              (jsonDecode(request.body) as Map).cast<String, dynamic>();
          final row = _rows[body['author_public_key'] as String];
          if (row == null) {
            return _resp(404, {'success': false, 'error': 'Vault not found'});
          }
          return _resp(200, {
            'success': true,
            'data': {
              'encrypted_data': row.encryptedData,
              'salt': row.salt,
              'nonce': row.nonce,
            },
          });
        }
        return _resp(405, {'success': false, 'error': 'method not allowed'});
      });
}

class _StoredRow {
  _StoredRow({
    required this.encryptedData,
    required this.salt,
    required this.nonce,
  });
  final String encryptedData;
  final String salt;
  final String nonce;
}

http.Response _resp(int code, Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), code);
