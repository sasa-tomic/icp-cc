import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/account.dart';
import '../models/identity_record.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/account_signature_service.dart';

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

/// Controller for account management operations
///
/// Manages account state, registration, and key management.
/// Integrates with MarketplaceOpenApiService for backend communication
/// and AccountSignatureService for cryptographic signing.
class AccountController extends ChangeNotifier {
  AccountController({
    MarketplaceOpenApiService? marketplaceService,
    FlutterSecureStorage? secureStorage,
  }) : _marketplaceService = marketplaceService ?? MarketplaceOpenApiService(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final MarketplaceOpenApiService _marketplaceService;
  final FlutterSecureStorage _secureStorage;

  // Key prefix for storing identity-username mappings
  static const String _identityUsernamePrefix = 'identity_username_';

  /// Cache of accounts by username
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

  /// Add a public key to an account
  ///
  /// The signing identity must have an active key in the account.
  /// The new public key will be derived from newIdentity.
  ///
  /// Returns the newly added AccountPublicKey.
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

  /// Get account for a specific identity
  ///
  /// Searches cached accounts to find one containing the identity's public key.
  /// Returns null if no matching account found.
  Account? accountForIdentity(IdentityRecord identity) {
    // Convert identity public key to hex format for comparison
    final publicKeyHex = AccountSignatureService.publicKeyToHex(identity.publicKey);

    for (final account in _accounts.values) {
      final hasKey = account.publicKeys.any((key) => key.publicKey == publicKeyHex);
      if (hasKey) {
        return account;
      }
    }

    return null;
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
