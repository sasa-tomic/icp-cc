import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/screens/account_profile_screen.dart';
import 'package:icp_autorun/models/account.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';

import '../../shared/test_keypair_factory.dart';

/// Fake ProfileKeypair for mocktail fallback values
class FakeProfileKeypair extends Fake implements ProfileKeypair {}

/// Mock AccountController for testing
class MockAccountController extends Mock implements AccountController {}

/// Mock ProfileController for testing
class MockProfileController extends Mock implements ProfileController {}

/// Helper class to pump AccountProfileScreen with required mocks
class AccountProfileScreenTestHelper {
  /// Creates a test Account with specified keys
  static Account createTestAccount({
    required String username,
    required String displayName,
    List<AccountPublicKey>? publicKeys,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
  }) {
    return Account(
      id: 'account-$username',
      username: username,
      displayName: displayName,
      publicKeys: publicKeys ?? [],
      contactEmail: contactEmail,
      contactTelegram: contactTelegram,
      contactTwitter: contactTwitter,
      contactDiscord: contactDiscord,
      websiteUrl: websiteUrl,
      bio: bio,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      updatedAt: DateTime.now(),
    );
  }

  /// Creates an AccountPublicKey for testing
  static AccountPublicKey createTestAccountPublicKey({
    required String id,
    required String publicKey,
    required String icPrincipal,
    bool isActive = true,
    String? label,
    DateTime? disabledAt,
  }) {
    return AccountPublicKey(
      id: id,
      publicKey: publicKey,
      icPrincipal: icPrincipal,
      isActive: isActive,
      addedAt: DateTime.now().subtract(const Duration(days: 7)),
      label: label,
      disabledAt: disabledAt,
    );
  }

  /// Creates a test Profile with keypairs
  static Future<Profile> createTestProfileWithKeypairs({
    required String id,
    required String name,
    String? username,
    int keypairCount = 1,
    String? activeKeypairId,
  }) async {
    final keypairs = <ProfileKeypair>[];
    for (int i = 0; i < keypairCount; i++) {
      final keypair = await TestKeypairFactory.fromSeed(i + 1);
      keypairs.add(keypair);
    }
    return Profile(
      id: id,
      name: name,
      keypairs: keypairs,
      username: username,
      activeKeypairId: activeKeypairId,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a matching account and profile setup
  static Future<MatchingSetup> createMatchingAccountAndProfile({
    required String username,
    required String displayName,
    int keyCount = 1,
  }) async {
    final keypairs = <ProfileKeypair>[];
    final accountKeys = <AccountPublicKey>[];

    for (int i = 0; i < keyCount; i++) {
      final keypair = await TestKeypairFactory.fromSeed(i + 100);
      keypairs.add(keypair);
      accountKeys.add(createTestAccountPublicKey(
        id: 'key-$i',
        publicKey: keypair.publicKey,
        icPrincipal: keypair.principal ?? 'principal-$i',
        label: keypair.label,
      ));
    }

    final profile = Profile(
      id: 'profile-$username',
      name: displayName,
      keypairs: keypairs,
      username: username,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      updatedAt: DateTime.now(),
    );

    final account = createTestAccount(
      username: username,
      displayName: displayName,
      publicKeys: accountKeys,
    );

    return MatchingSetup(account: account, profile: profile);
  }

  /// Pumps the AccountProfileScreen widget
  static Future<void> pumpAccountProfileScreen(
    WidgetTester tester, {
    required Account account,
    required AccountController accountController,
    required Profile profile,
    required ProfileController profileController,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AccountProfileScreen(
          account: account,
          accountController: accountController,
          profile: profile,
          profileController: profileController,
        ),
      ),
    );
    // Wait for initial build and potential async operations
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Register fallback values for mocktail
  static void registerFallbackValues() {
    registerFallbackValue(FakeProfileKeypair());
  }
}

/// Container for matching account and profile data
class MatchingSetup {
  final Account account;
  final Profile profile;

  MatchingSetup({required this.account, required this.profile});
}

/// Test fixture for account profile screen tests
class AccountProfileTestFixture {
  late MockAccountController accountController;
  late MockProfileController profileController;
  late Account account;
  late Profile profile;

  Future<void> setUp({
    String username = 'testuser',
    String displayName = 'Test User',
    int keyCount = 1,
  }) async {
    accountController = MockAccountController();
    profileController = MockProfileController();

    final setup =
        await AccountProfileScreenTestHelper.createMatchingAccountAndProfile(
      username: username,
      displayName: displayName,
      keyCount: keyCount,
    );
    account = setup.account;
    profile = setup.profile;
  }

  /// Configure mock for successful account refresh
  void configureSuccessfulRefresh([Account? refreshedAccount]) {
    when(() => accountController.refreshAccount(any()))
        .thenAnswer((_) async => refreshedAccount ?? account);
  }

  /// Configure mock for successful profile update
  void configureSuccessfulProfileUpdate() {
    when(() => accountController.updateProfile(
          username: any(named: 'username'),
          signingKeypair: any(named: 'signingKeypair'),
          displayName: any(named: 'displayName'),
          contactEmail: any(named: 'contactEmail'),
          contactTelegram: any(named: 'contactTelegram'),
          contactTwitter: any(named: 'contactTwitter'),
          contactDiscord: any(named: 'contactDiscord'),
          websiteUrl: any(named: 'websiteUrl'),
          bio: any(named: 'bio'),
        )).thenAnswer((_) async => account);
  }

  /// Configure mock for successful key removal
  void configureSuccessfulKeyRemoval() {
    when(() => accountController.removePublicKey(
          username: any(named: 'username'),
          keyId: any(named: 'keyId'),
          signingKeypair: any(named: 'signingKeypair'),
        )).thenAnswer((_) async => account.publicKeys.first);
  }

  /// Configure mock for successful signing key change
  void configureSuccessfulSigningKeyChange(Profile updatedProfile) {
    when(() => profileController.setActiveKeypair(
          profileId: any(named: 'profileId'),
          keypairId: any(named: 'keypairId'),
        )).thenAnswer((_) async {});
    when(() => profileController.findById(any())).thenReturn(updatedProfile);
  }
}
