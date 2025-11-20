import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/identity_record.dart';
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
  String toString() => 'Network error: $message${originalError != null ? ' ($originalError)' : ''}';
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
/// - Works with Profile objects, not individual IdentityRecords
/// - Generates keypairs through ProfileController (no importing)
/// - Stores username in Profile, not separate mapping
/// - Draft accounts are part of Profile (not separate storage)
///
/// Manages account state, registration, and key management.
/// Integrates with MarketplaceOpenApiService for backend communication
/// and AccountSignatureService for cryptographic signing.
class AccountController extends ChangeNotifier {
  AccountController({
    MarketplaceOpenApiService? marketplaceService,
    FlutterSecureStorage? secureStorage,
    ProfileController? profileController,
  }) : _marketplaceService = marketplaceService ?? MarketplaceOpenApiService(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _profileController = profileController;

  final MarketplaceOpenApiService _marketplaceService;
  final FlutterSecureStorage _secureStorage;
  final ProfileController? _profileController;

  // DEPRECATED: For backward compatibility with old code
  static const String _identityUsernamePrefix = 'identity_username_';
  static const String _draftAccountPrefix = 'draft_account_';

  /// Cache of accounts by username (registered on marketplace)
  final Map<String, Account> _accounts = <String, Account>{};

  /// Cache of draft accounts by identity ID (local only, not yet registered)
  final Map<String, Account> _draftAccounts = <String, Account>{};

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
    required IdentityRecord identity,
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
      final normalizedUsername = AccountSignatureService.normalizeUsername(username);

      // Create signed request
      final request = await AccountSignatureService.createRegisterAccountRequest(
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

      // Store identity-username mapping for future app loads
      await storeUsernameForIdentity(identity.id, normalizedUsername);

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
      final normalizedUsername = AccountSignatureService.normalizeUsername(username);
      final account = await _marketplaceService.getAccount(username: normalizedUsername);

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
    final normalizedUsername = AccountSignatureService.normalizeUsername(username);
    _accounts.remove(normalizedUsername); // Clear cache
    return await fetchAccount(normalizedUsername);
  }

  /// Check if a username is available
  ///
  /// Uses cache when available, otherwise queries backend.
  Future<bool> isUsernameAvailable(String username) async {
    final normalizedUsername = AccountSignatureService.normalizeUsername(username);

    // Check cache first
    if (_availabilityCache.containsKey(normalizedUsername)) {
      return _availabilityCache[normalizedUsername]!;
    }

    _setBusy(true);
    try {
      final isAvailable = await _marketplaceService.isUsernameAvailable(normalizedUsername);
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
      throw StateError('Profile must be registered (have username) to add keypairs');
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
        final updatedKeys = <AccountPublicKey>[...cachedAccount.publicKeys, newKey];
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

  /// DEPRECATED: Use addKeypairToAccount instead
  ///
  /// This method violates profile isolation by accepting identities from anywhere.
  /// It's kept for backward compatibility but should not be used in new code.
  @Deprecated('Use addKeypairToAccount with ProfileController instead')
  Future<AccountPublicKey> addPublicKey({
    required String username,
    required IdentityRecord signingIdentity,
    required IdentityRecord newIdentity,
  }) async {
    _setBusy(true);
    try {
      final normalizedUsername = AccountSignatureService.normalizeUsername(username);

      // Create signed request
      final request = await AccountSignatureService.createAddPublicKeyRequest(
        signingIdentity: signingIdentity,
        username: normalizedUsername,
        newPublicKeyB64: newIdentity.publicKey,
      );

      // Submit to backend
      final newKey = await _marketplaceService.addPublicKey(
        username: normalizedUsername,
        request: request,
      );

      // Update cached account
      final cachedAccount = _accounts[normalizedUsername];
      if (cachedAccount != null) {
        final updatedKeys = <AccountPublicKey>[...cachedAccount.publicKeys, newKey];
        _accounts[normalizedUsername] = cachedAccount.copyWith(
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

  /// Remove a public key from an account (soft delete)
  ///
  /// The signing identity must have an active key in the account.
  /// Cannot remove the last active key.
  ///
  /// Returns the updated AccountPublicKey (with isActive = false).
  Future<AccountPublicKey> removePublicKey({
    required String username,
    required String keyId,
    required IdentityRecord signingIdentity,
  }) async {
    _setBusy(true);
    try {
      final normalizedUsername = AccountSignatureService.normalizeUsername(username);

      // Create signed request
      final request = await AccountSignatureService.createRemovePublicKeyRequest(
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
    required IdentityRecord signingIdentity,
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
      final normalizedUsername = AccountSignatureService.normalizeUsername(username);

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

  /// DEPRECATED: Use getAccountForProfile instead
  ///
  /// This method searches ALL accounts for a matching key, which violates
  /// profile isolation. Use Profile.username directly or getAccountForProfile().
  @Deprecated('Use getAccountForProfile with Profile instead')
  Account? accountForIdentity(IdentityRecord identity) {
    // Convert identity public key to hex format for comparison
    final publicKeyHex = AccountSignatureService.publicKeyToHex(identity.publicKey);

    // Check registered accounts first
    for (final account in _accounts.values) {
      final hasKey = account.publicKeys.any((key) => key.publicKey == publicKeyHex);
      if (hasKey) {
        return account;
      }
    }

    // Check draft accounts (cached in memory)
    if (_draftAccounts.containsKey(identity.id)) {
      return _draftAccounts[identity.id];
    }

    return null;
  }

  /// DEPRECATED: Use getAccountForProfile instead
  @Deprecated('Use getAccountForProfile with Profile instead')
  Future<Account?> getAccountForIdentity(IdentityRecord identity) async {
    // Try memory cache first
    final cached = accountForIdentity(identity);
    if (cached != null) {
      return cached;
    }

    // Try loading draft account from storage
    return await getDraftAccount(identity.id);
  }

  /// Validate username format
  ///
  /// Returns validation result with error message if invalid.
  UsernameValidation validateUsername(String username) {
    return AccountSignatureService.validateUsername(username);
  }

  /// Store identity-to-username mapping in secure storage
  ///
  /// This mapping is used to fetch accounts when the app restarts.
  Future<void> storeUsernameForIdentity(String identityId, String username) async {
    await _secureStorage.write(
      key: '$_identityUsernamePrefix$identityId',
      value: username,
    );
  }

  /// Get stored username for an identity
  ///
  /// Returns null if no mapping exists.
  Future<String?> getUsernameForIdentity(String identityId) async {
    return await _secureStorage.read(
      key: '$_identityUsernamePrefix$identityId',
    );
  }

  /// Fetch account for an identity using stored username mapping
  ///
  /// First tries to use the locally stored identity→username mapping.
  /// If no mapping exists, queries the server by public key to discover the account.
  /// If an account is found via public key lookup, the mapping is stored for future use.
  ///
  /// Returns null if no account exists for this identity.
  ///
  /// Throws [AccountNetworkException] for network-related failures.
  /// Throws [TimeoutException] if the request takes too long.
  Future<Account?> fetchAccountForIdentity(IdentityRecord identity) async {
    // Try local mapping first (fast path)
    final username = await getUsernameForIdentity(identity.id);
    if (username != null) {
      try {
        return await fetchAccount(username).timeout(
          const Duration(seconds: 10),
        );
      } on SocketException catch (e) {
        throw AccountNetworkException('No internet connection', e);
      } on TimeoutException {
        throw AccountNetworkException('Request timed out - check your connection');
      } on http.ClientException catch (e) {
        throw AccountNetworkException('Network error', e);
      }
    }

    // No local mapping - try server lookup by public key (fallback)
    try {
      final publicKeyHex = AccountSignatureService.publicKeyToHex(identity.publicKey);
      final account = await _marketplaceService
          .getAccountByPublicKey(
            publicKeyHex: publicKeyHex,
          )
          .timeout(const Duration(seconds: 10));

      if (account != null) {
        // Found account! Store the mapping for future use
        await storeUsernameForIdentity(identity.id, account.username);

        // Cache the account
        _accounts[account.username] = account;
        notifyListeners();
      }

      return account;
    } on SocketException catch (e) {
      throw AccountNetworkException('No internet connection', e);
    } on TimeoutException {
      throw AccountNetworkException('Request timed out - check your connection');
    } on http.ClientException catch (e) {
      throw AccountNetworkException('Network error', e);
    } catch (e) {
      // Other errors - rethrow for debugging
      if (!e.toString().contains('404') && !e.toString().contains('not found')) {
        rethrow;
      }
      // 404 means no account exists - return null
      return null;
    }
  }

  /// Create a draft account (local only, not registered on marketplace)
  ///
  /// FIXME - ARCHITECTURE ISSUE:
  /// Draft accounts are stored per-identity, but should be per-profile.
  /// Once Profile model exists, this should be:
  /// - createDraftProfile(username, displayName, algorithm)
  /// - Generates initial keypair
  /// - Creates Profile with Account reference
  /// - Returns Profile (not Account)
  ///
  /// This creates a local account that will be used until the user registers
  /// on the marketplace. The draft account is persisted and will survive app restarts.
  Future<Account> createDraftAccount({
    required IdentityRecord identity,
    required String username,
    required String displayName,
  }) async {
    final normalizedUsername = AccountSignatureService.normalizeUsername(username);
    final publicKeyHex = AccountSignatureService.publicKeyToHex(identity.publicKey);

    final now = DateTime.now();
    final draftAccount = Account(
      id: 'draft_${identity.id}',
      username: normalizedUsername,
      displayName: displayName,
      publicKeys: [
        AccountPublicKey(
          id: 'draft_key_${identity.id}',
          publicKey: publicKeyHex,
          icPrincipal: '', // Will be populated when registered
          isActive: true,
          addedAt: now,
          disabledAt: null,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    // Store in cache
    _draftAccounts[identity.id] = draftAccount;

    // Persist to secure storage
    await _secureStorage.write(
      key: '$_draftAccountPrefix${identity.id}',
      value: jsonEncode(draftAccount.toJson()),
    );

    notifyListeners();
    return draftAccount;
  }

  /// Load all draft accounts from secure storage
  Future<void> loadDraftAccounts() async {
    // Note: FlutterSecureStorage doesn't provide a way to list all keys,
    // so we'll load draft accounts on-demand in getDraftAccount
  }

  /// Get draft account for an identity
  ///
  /// Returns null if no draft account exists.
  Future<Account?> getDraftAccount(String identityId) async {
    // Check cache first
    if (_draftAccounts.containsKey(identityId)) {
      return _draftAccounts[identityId];
    }

    // Load from secure storage
    final json = await _secureStorage.read(key: '$_draftAccountPrefix$identityId');
    if (json != null) {
      try {
        final account = Account.fromJson(jsonDecode(json) as Map<String, dynamic>);
        _draftAccounts[identityId] = account;
        return account;
      } catch (e) {
        debugPrint('Failed to parse draft account: $e');
        return null;
      }
    }

    return null;
  }

  /// Delete draft account
  Future<void> deleteDraftAccount(String identityId) async {
    _draftAccounts.remove(identityId);
    await _secureStorage.delete(key: '$_draftAccountPrefix$identityId');
    notifyListeners();
  }

  /// Clear all cached data
  void clearCache() {
    _accounts.clear();
    _draftAccounts.clear();
    _availabilityCache.clear();
    notifyListeners();
  }

  void _setBusy(bool busy) {
    _isBusy = busy;
    notifyListeners();
  }
}
