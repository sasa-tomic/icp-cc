import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/account.dart';
import '../models/profile_keypair.dart';
import '../models/profile.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/account_signature_service.dart';
import 'profile_controller.dart';

/// Exception thrown when account is not found
class AccountNotFoundException implements Exception {
  final String username;
  AccountNotFoundException(this.username);

  @override
  String toString() => 'Account not found: $username';
}

/// Exception thrown when network operation fails
class AccountNetworkException implements Exception {
  final String message;
  final Object? originalError;

  AccountNetworkException(this.message, [this.originalError]);

  @override
  String toString() =>
      'Network error: $message${originalError != null ? ' ($originalError)' : ''}';
}

/// Controller for backend account management operations
///
/// ARCHITECTURE: Profile-Centric Model
/// This controller manages backend accounts and their relationship with profiles:
/// - Each Profile has exactly ONE backend Account
/// - Account username is stored in Profile.username
/// - Uses ProfileController to generate new keypairs when needed
/// - NO cross-profile operations
///
/// Key changes from old design:
/// - Works with Profile objects, not individual ProfileKeypairs
/// - Generates keypairs through ProfileController (no importing)
/// - Stores username in Profile, not separate mapping
///
/// Manages account state, registration, and key management.
/// Integrates with MarketplaceOpenApiService for backend communication
/// and AccountSignatureService for cryptographic signing.
class AccountController extends ChangeNotifier {
  AccountController({
    MarketplaceOpenApiService? marketplaceService,
    ProfileController? profileController,
  })  : _marketplaceService = marketplaceService ?? MarketplaceOpenApiService(),
        _profileController = profileController;

  final MarketplaceOpenApiService _marketplaceService;
  final ProfileController? _profileController;

  /// Cache of accounts by username (registered on marketplace)
  final Map<String, Account> _accounts = <String, Account>{};

  /// Cache of username availability checks (username -> isAvailable)
  final Map<String, bool> _availabilityCache = <String, bool>{};

  bool _isBusy = false;

  bool get isBusy => _isBusy;

  /// Get cached account by username
  Account? getAccount(String username) => _accounts[username];

  /// Check if account exists in cache
  bool hasAccount(String username) => _accounts.containsKey(username);

  /// Register a new account
  ///
  /// Creates a cryptographically signed request and submits to backend.
  /// Returns the created account on success.
  ///
  /// Throws:
  /// - Exception if username is invalid or already taken
  /// - Exception if signature generation fails
  /// - Exception if backend request fails
  Future<Account> registerAccount({
    required ProfileKeypair identity,
    required String username,
    required String displayName,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
  }) async {
    _setBusy(true);
    try {
      // Validate username format
      final validation = AccountSignatureService.validateUsername(username);
      if (!validation.isValid) {
        throw Exception(validation.error ?? 'Invalid username');
      }

      // Normalize username
      final normalizedUsername =
          AccountSignatureService.normalizeUsername(username);

      // Create signed request
      final request =
          await AccountSignatureService.createRegisterAccountRequest(
        identity: identity,
        username: normalizedUsername,
        displayName: displayName,
        contactEmail: contactEmail,
        contactTelegram: contactTelegram,
        contactTwitter: contactTwitter,
        contactDiscord: contactDiscord,
        websiteUrl: websiteUrl,
        bio: bio,
      );

      // Submit to backend
      final account = await _marketplaceService.registerAccount(request);

      // Cache the account
      _accounts[normalizedUsername] = account;
      _availabilityCache.remove(normalizedUsername); // Clear availability cache

      notifyListeners();
      return account;
    } finally {
      _setBusy(false);
    }
  }

  /// Fetch account details from backend
  ///
  /// Returns null if account doesn't exist.
  /// Caches the account on success.
  Future<Account?> fetchAccount(String username) async {
    _setBusy(true);
    try {
      final normalizedUsername =
          AccountSignatureService.normalizeUsername(username);
      final account =
          await _marketplaceService.getAccount(username: normalizedUsername);

      if (account != null) {
        _accounts[normalizedUsername] = account;
        notifyListeners();
      }

      return account;
    } finally {
      _setBusy(false);
    }
  }

  /// Refresh account details from backend
  ///
  /// Same as fetchAccount but always fetches from server.
  Future<Account?> refreshAccount(String username) async {
    final normalizedUsername =
        AccountSignatureService.normalizeUsername(username);
    _accounts.remove(normalizedUsername); // Clear cache
    return await fetchAccount(normalizedUsername);
  }

  /// Check if a username is available
  ///
  /// Uses cache when available, otherwise queries backend.
  Future<bool> isUsernameAvailable(String username) async {
    final normalizedUsername =
        AccountSignatureService.normalizeUsername(username);

    // Check cache first
    if (_availabilityCache.containsKey(normalizedUsername)) {
      return _availabilityCache[normalizedUsername]!;
    }

    _setBusy(true);
    try {
      final isAvailable =
          await _marketplaceService.isUsernameAvailable(normalizedUsername);
      _availabilityCache[normalizedUsername] = isAvailable;
      notifyListeners();
      return isAvailable;
    } finally {
      _setBusy(false);
    }
  }

  /// Add a keypair to profile's account
  ///
  /// This method GENERATES a new keypair for the profile and registers it with the backend.
  /// - Generates NEW keypair through ProfileController
  /// - Adds keypair to profile (stored locally)
  /// - Registers public key with backend account
  /// - NO cross-profile operations
  ///
  /// Returns the newly added AccountPublicKey from backend.
  Future<AccountPublicKey> addKeypairToAccount({
    required Profile profile,
    required KeyAlgorithm algorithm,
    String? keypairLabel,
  }) async {
    if (_profileController == null) {
      throw StateError('ProfileController is required for addKeypairToAccount');
    }

    if (profile.username == null) {
      throw StateError(
          'Profile must be registered (have username) to add keypairs');
    }

    _setBusy(true);
    try {
      // Step 1: Generate NEW keypair within the profile (via ProfileController)
      final updatedProfile = await _profileController.addKeypairToProfile(
        profileId: profile.id,
        algorithm: algorithm,
        label: keypairLabel,
      );

      // Step 2: Get the newly added keypair (last one in the list)
      final newKeypair = updatedProfile.keypairs.last;

      // Step 3: Sign request with existing keypair from profile
      final signingKeypair = profile.primaryKeypair;
      final request = await AccountSignatureService.createAddPublicKeyRequest(
        signingIdentity: signingKeypair,
        username: profile.username!,
        newPublicKeyB64: newKeypair.publicKey,
      );

      // Step 4: Submit to backend
      final newKey = await _marketplaceService.addPublicKey(
        username: profile.username!,
        request: request,
      );

      // Step 5: Update cached account
      final cachedAccount = _accounts[profile.username];
      if (cachedAccount != null) {
        final updatedKeys = <AccountPublicKey>[
          ...cachedAccount.publicKeys,
          newKey
        ];
        _accounts[profile.username!] = cachedAccount.copyWith(
          publicKeys: updatedKeys,
          updatedAt: DateTime.now(),
        );
      }

      notifyListeners();
      return newKey;
    } finally {
      _setBusy(false);
    }
  }

  /// Get account for a profile (uses Profile.username)
  ///
  /// Returns cached account if available, otherwise fetches from backend.
  /// Returns null if profile is not registered or account doesn't exist.
  Future<Account?> getAccountForProfile(Profile profile) async {
    if (profile.username == null) {
      // Profile not registered yet
      return null;
    }

    // Check cache first
    final cached = _accounts[profile.username];
    if (cached != null) {
      return cached;
    }

    // Fetch from backend
    return await fetchAccount(profile.username!);
  }

  /// Remove a public key from an account (soft delete)
  ///
  /// The signing identity must have an active key in the account.
  /// Cannot remove the last active key.
  ///
  /// Returns the updated AccountPublicKey (with isActive = false).
  Future<AccountPublicKey> removePublicKey({
    required String username,
    required String keyId,
    required ProfileKeypair signingIdentity,
  }) async {
    _setBusy(true);
    try {
      final normalizedUsername =
          AccountSignatureService.normalizeUsername(username);

      // Create signed request
      final request =
          await AccountSignatureService.createRemovePublicKeyRequest(
        signingIdentity: signingIdentity,
        username: normalizedUsername,
        keyId: keyId,
      );

      // Submit to backend
      final removedKey = await _marketplaceService.removePublicKey(
        username: normalizedUsername,
        keyId: keyId,
        request: request,
      );

      // Update cached account
      final cachedAccount = _accounts[normalizedUsername];
      if (cachedAccount != null) {
        final updatedKeys = cachedAccount.publicKeys.map((key) {
          if (key.id == keyId) {
            return removedKey; // Use updated key from server
          }
          return key;
        }).toList();

        _accounts[normalizedUsername] = cachedAccount.copyWith(
          publicKeys: updatedKeys,
          updatedAt: DateTime.now(),
        );
      }

      notifyListeners();
      return removedKey;
    } finally {
      _setBusy(false);
    }
  }

  /// Update account profile information
  ///
  /// The signing identity must have an active key in the account.
  /// Returns the updated account on success.
  Future<Account> updateProfile({
    required String username,
    required ProfileKeypair signingIdentity,
    String? displayName,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
  }) async {
    _setBusy(true);
    try {
      final normalizedUsername =
          AccountSignatureService.normalizeUsername(username);

      // Create signed request
      final request = await AccountSignatureService.createUpdateAccountRequest(
        signingIdentity: signingIdentity,
        username: normalizedUsername,
        displayName: displayName,
        contactEmail: contactEmail,
        contactTelegram: contactTelegram,
        contactTwitter: contactTwitter,
        contactDiscord: contactDiscord,
        websiteUrl: websiteUrl,
        bio: bio,
      );

      // Submit to backend
      final updatedAccount = await _marketplaceService.updateAccount(
        username: normalizedUsername,
        request: request,
      );

      // Update cached account
      _accounts[normalizedUsername] = updatedAccount;

      notifyListeners();
      return updatedAccount;
    } finally {
      _setBusy(false);
    }
  }

  /// Validate username format
  ///
  /// Returns validation result with error message if invalid.
  UsernameValidation validateUsername(String username) {
    return AccountSignatureService.validateUsername(username);
  }

  /// Clear all cached data
  void clearCache() {
    _accounts.clear();
    _availabilityCache.clear();
    notifyListeners();
  }

  void _setBusy(bool busy) {
    _isBusy = busy;
    notifyListeners();
  }
}
