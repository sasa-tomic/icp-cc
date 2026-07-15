import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/rust/native_bridge.dart';
import 'package:icp_autorun/screens/vault_password_setup_screen.dart';
import 'package:icp_autorun/screens/recovery_codes_screen.dart';
import 'package:icp_autorun/screens/vault_unlock_screen.dart';
import 'package:icp_autorun/services/passkey_service.dart';
import 'package:icp_autorun/services/vault_crypto_service.dart';
import '../../shared/test_keypair_factory.dart';

/// Deterministic fake VaultCryptoService for widget tests. The real FFI crypto
/// is unit-tested separately in vault_crypto_service_test.dart; widget tests
/// use this fake so they run even when libicp_core is unavailable.
///
/// `decrypt` throws [VaultDecryptionException] for any password != [password]
/// (mirrors the real AES-256-GCM auth-tag failure mode).
class _FakeVaultCrypto extends VaultCryptoService {
  _FakeVaultCrypto({required this.password, required this.plaintext});
  final String password;
  final String plaintext;

  @override
  Future<EncryptedVaultResult> encrypt({
    required String password,
    required String plaintext,
  }) async {
    return EncryptedVaultResult(
      encryptedDataB64: base64.encode(utf8.encode('ENC|$plaintext')),
      saltB64: 'c2FsdA==',
      nonceB64: 'bm9uY2U=',
    );
  }

  @override
  Future<String> decrypt({
    required String password,
    required EncryptedVaultResult blob,
  }) async {
    if (password != this.password) {
      throw VaultDecryptionException('wrong password (fake)');
    }
    return plaintext;
  }
}

/// Widget tests for passkey-related screens
void main() {
  // W7-12: the vault screens now carry the active ProfileKeypair (used to sign
  // the signature-gated vault request). One real Ed25519 keypair for all tests.
  late ProfileKeypair keypair;

  setUpAll(() async {
    keypair = await TestKeypairFactory.getEd25519Keypair();
  });

  group('VaultPasswordSetupScreen', () {
    testWidgets('displays password requirements', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultPasswordSetupScreen(accountId: 'test-account', keypair: keypair),
        ),
      );

      expect(find.text('At least 12 characters'), findsOneWidget);
      expect(find.text('One uppercase letter (A-Z)'), findsOneWidget);
      expect(find.text('One lowercase letter (a-z)'), findsOneWidget);
      expect(find.text('One number (0-9)'), findsOneWidget);
      expect(find.text('One special character (!@#\$%^&*)'), findsOneWidget);
    });

    testWidgets('shows error on weak password', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultPasswordSetupScreen(accountId: 'test-account', keypair: keypair),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'weak',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'weak',
      );
      await tester.pump();

      final button = find.widgetWithText(ElevatedButton, 'Create Vault');
      expect(tester.widget<ElevatedButton>(button).enabled, isFalse);
    });

    testWidgets('shows error when passwords do not match', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultPasswordSetupScreen(accountId: 'test-account', keypair: keypair),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'StrongP@ssw0rd!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'DifferentP@ssw0rd!',
      );
      await tester.pump();

      final button = find.widgetWithText(ElevatedButton, 'Create Vault');
      expect(tester.widget<ElevatedButton>(button).enabled, isFalse);
    });

    testWidgets('disables button until form is valid', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultPasswordSetupScreen(accountId: 'test-account', keypair: keypair),
        ),
      );

      final button = find.widgetWithText(ElevatedButton, 'Create Vault');
      expect(tester.widget<ElevatedButton>(button).enabled, isFalse);
    });
  });

  group('RecoveryCodesScreen', () {
    final testCodes = [
      'ABCD-EFGH-IJKL',
      'MNOP-QRST-UVWX',
      'YZ12-3456-7890',
      '1234-5678-90AB',
      'CDEF-GHIJ-KLMN',
      'OPQR-STUV-WXYZ',
    ];

    testWidgets('displays all recovery codes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryCodesScreen(
            codes: testCodes,
            accountId: 'test-account',
          ),
        ),
      );

      for (final code in testCodes) {
        expect(find.text(code), findsOneWidget);
      }
    });

    testWidgets('disables continue button until confirmed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryCodesScreen(
            codes: testCodes,
            accountId: 'test-account',
          ),
        ),
      );

      final button = find.widgetWithText(ElevatedButton, 'Continue');
      expect(tester.widget<ElevatedButton>(button).enabled, isFalse);
    });

    testWidgets('enables continue button when confirmed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryCodesScreen(
            codes: testCodes,
            accountId: 'test-account',
          ),
        ),
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final button = find.widgetWithText(ElevatedButton, 'Continue');
      expect(tester.widget<ElevatedButton>(button).enabled, isTrue);
    });

    testWidgets('shows warning message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryCodesScreen(
            codes: testCodes,
            accountId: 'test-account',
          ),
        ),
      );

      expect(find.text('Save These Codes'), findsOneWidget);
      expect(
        find.textContaining('ONLY way to access your vault'),
        findsOneWidget,
      );
    });
  });

  group('VaultUnlockScreen', () {
    setUp(() {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'encrypted_data': 'ZW5jcnlwdGVk',
              'salt': 'c2FsdA==',
              'nonce': 'bm9uY2U=',
            },
          }),
          200,
        );
      });
      PasskeyService().overrideHttpClient(mockClient);
    });

    testWidgets('displays lock icon and password field', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(accountId: 'test-account', keypair: keypair),
        ),
      );

      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    });

    testWidgets('disables unlock button with empty password', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(accountId: 'test-account', keypair: keypair),
        ),
      );

      final button = find.widgetWithText(ElevatedButton, 'Unlock');
      expect(tester.widget<ElevatedButton>(button).enabled, isFalse);
    });

    testWidgets('enables unlock button with password', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(accountId: 'test-account', keypair: keypair),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'some-password',
      );
      await tester.pump();

      final button = find.widgetWithText(ElevatedButton, 'Unlock');
      expect(tester.widget<ElevatedButton>(button).enabled, isTrue);
    });

    testWidgets('shows recovery code link', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(accountId: 'test-account', keypair: keypair),
        ),
      );

      expect(
        find.text('Forgot password? Use recovery code'),
        findsOneWidget,
      );
    });
  });

  // ===========================================================================
  // A-4 W3 — full round-trip + negative-path widget tests for the vault screens.
  // Both screens accept an injected VaultCryptoService; widget tests pass a
  // deterministic fake (above) so they run even when libicp_core is unavailable.
  // The real FFI crypto is unit-tested in vault_crypto_service_test.dart.
  // HTTP is mocked; per AGENTS.md the HTTP layer MAY be mocked.
  // ===========================================================================
  group('VaultPasswordSetupScreen (A-4 W3 local-crypto round-trip)', () {
    testWidgets('happy path: form submit encrypts locally and POSTs the blob',
        (tester) async {
      Map<String, dynamic>? capturedBody;
      var onVaultCreatedCalled = false;

      final client = MockClient((request) async {
        if (request.url.path.contains('/recovery/generate')) {
          return http.Response(
              jsonEncode({
                'data': {
                  'codes': ['AAAA-BBBB', 'CCCC-DDDD'],
                  'remaining_unused': 2,
                }
              }),
              200);
        }
        if (request.method == 'POST' && request.body.isNotEmpty) {
          capturedBody =
              (jsonDecode(request.body) as Map).cast<String, dynamic>();
        }
        return http.Response(jsonEncode({'success': true}), 200);
      });
      PasskeyService().overrideHttpClient(client);

      const fakePassword = 'StrongP@ssw0rd!';
      await tester.pumpWidget(
        MaterialApp(
          home: VaultPasswordSetupScreen(
            accountId: 'acct-w3-setup',
            keypair: keypair,
            onVaultCreated: () => onVaultCreatedCalled = true,
            vaultCrypto:
                _FakeVaultCrypto(password: fakePassword, plaintext: '{}'),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        fakePassword,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        fakePassword,
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Vault'));
      await tester.pumpAndSettle();

      expect(onVaultCreatedCalled, isTrue,
          reason: 'onVaultCreated must fire on success');
      expect(capturedBody, isNotNull,
          reason: 'a POST must have been made');
      // W7-12: body now carries auth fields + opaque blob (NO account_id —
      // resolved server-side).
      expect(capturedBody!.keys,
          equals(<String>{
            'signature',
            'author_public_key',
            'author_principal',
            'timestamp',
            'nonce',
            'encrypted_data',
            'salt',
            'blob_nonce',
          }));
      expect(capturedBody!.containsKey('password'), isFalse,
          reason: 'password must never be in the wire body');
      expect(capturedBody!.containsKey('account_id'), isFalse,
          reason: 'account_id must NOT be in the body (server-resolved)');
    });
  });

  group('VaultUnlockScreen (A-4 W3 decrypt-and-surface)', () {
    testWidgets('happy path: correct password decrypts the blob locally and '
        'surfaces the plaintext via onUnlocked', (tester) async {
      const correctPassword = 'CorrectP@ss1!';
      const plaintext = '{"k":"v"}';

      // GET returns a blob; the fake crypto will decrypt it iff the password
      // matches.
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'encrypted_data': 'ZW5j',
              'salt': 'c2FsdA==',
              'nonce': 'bm9uY2U=',
            },
          }),
          200,
        );
      });
      PasskeyService().overrideHttpClient(client);

      String? unlockedContents;
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(
            accountId: 'acct-w3-unlock',
            keypair: keypair,
            onUnlocked: (decrypted) => unlockedContents = decrypted,
            vaultCrypto:
                _FakeVaultCrypto(password: correctPassword, plaintext: plaintext),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        correctPassword,
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock'));
      await tester.pumpAndSettle();

      expect(unlockedContents, equals(plaintext),
          reason: 'onUnlocked must fire with the decrypted vault contents');
    });

    testWidgets('negative path: WRONG password shows a clear error, '
        'increments failed attempts, does NOT silently succeed',
        (tester) async {
      const correctPassword = 'CorrectP@ss1!';
      const wrongPassword = 'WrongP@ssword2!';
      const plaintext = '{"k":"v"}';

      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'encrypted_data': 'ZW5j',
                'salt': 'c2FsdA==',
                'nonce': 'bm9uY2U=',
              },
            }),
            200,
          ));
      PasskeyService().overrideHttpClient(client);

      var onUnlockedCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(
            accountId: 'acct-w3-unlock-wrong',
            keypair: keypair,
            onUnlocked: (_) => onUnlockedCalled = true,
            vaultCrypto:
                _FakeVaultCrypto(password: correctPassword, plaintext: plaintext),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        wrongPassword,
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock'));
      await tester.pumpAndSettle();

      expect(onUnlockedCalled, isFalse,
          reason: 'wrong password must NOT fire onUnlocked (no silent success)');
      expect(find.textContaining('Incorrect password'), findsOneWidget,
          reason: 'a clear error must be shown to the user');
    });

    testWidgets('vault not found (404) shows a clear error', (tester) async {
      const correctPassword = 'CorrectP@ss1!';
      final client = MockClient((_) async => http.Response(
            jsonEncode({'success': false, 'error': 'Vault not found'}),
            404,
          ));
      PasskeyService().overrideHttpClient(client);

      var onUnlockedCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: VaultUnlockScreen(
            accountId: 'acct-w3-no-vault',
            keypair: keypair,
            onUnlocked: (_) => onUnlockedCalled = true,
            vaultCrypto:
                _FakeVaultCrypto(password: correctPassword, plaintext: '{}'),
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        correctPassword,
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Unlock'));
      await tester.pumpAndSettle();

      expect(onUnlockedCalled, isFalse);
      expect(find.textContaining('Vault not found'), findsOneWidget);
    });

    // Note: the full REAL-FFI round-trip (real Argon2id + AES-256-GCM through
    // the screen) is intentionally NOT a widget test. It is covered in:
    //   - vault_crypto_service_test.dart (W1 — real FFI encrypt/decrypt)
    //   - passkey_service_vault_test.dart  (W2 — captured POST body decrypts
    //     back via real FFI)
    // Those are non-widget tests that don't use pumpAndSettle (which would
    // never settle against the indeterminate CircularProgressIndicator
    // animating during the isolate crypto). Widget tests use the deterministic
    // _FakeVaultCrypto above to validate UI flow, per AGENTS.md allowance.
  });
}
