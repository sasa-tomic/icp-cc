/// Account models for cryptographically-signed account management
///
/// These models represent accounts on the backend. Each account has:
/// - A unique username
/// - One or more public keys (each with derived IC principal)
/// - Cryptographic signatures for all state-changing operations
///
/// See ACCOUNT_PROFILES_DESIGN.md for full specification.
library;

class Account {
  Account({
    required this.id,
    required this.username,
    required this.displayName,
    this.contactEmail,
    this.contactTelegram,
    this.contactTwitter,
    this.contactDiscord,
    this.websiteUrl,
    this.bio,
    required this.publicKeys,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String? ?? json['display_name'] as String? ?? '',
      contactEmail: json['contactEmail'] as String? ?? json['contact_email'] as String?,
      contactTelegram: json['contactTelegram'] as String? ?? json['contact_telegram'] as String?,
      contactTwitter: json['contactTwitter'] as String? ?? json['contact_twitter'] as String?,
      contactDiscord: json['contactDiscord'] as String? ?? json['contact_discord'] as String?,
      websiteUrl: json['websiteUrl'] as String? ?? json['website_url'] as String?,
      bio: json['bio'] as String?,
      publicKeys: (json['publicKeys'] as List<dynamic>? ?? json['public_keys'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => AccountPublicKey.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String? ?? json['created_at'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String? ?? json['updated_at'] as String),
    );
  }

  final String id;
  final String username;
  final String displayName;
  final String? contactEmail;
  final String? contactTelegram;
  final String? contactTwitter;
  final String? contactDiscord;
  final String? websiteUrl;
  final String? bio;
  final List<AccountPublicKey> publicKeys;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Get all active public keys
  List<AccountPublicKey> get activeKeys =>
      publicKeys.where((AccountPublicKey k) => k.isActive).toList();

  /// Get all inactive/disabled keys
  List<AccountPublicKey> get disabledKeys =>
      publicKeys.where((AccountPublicKey k) => !k.isActive).toList();

  /// Check if account has reached max keys (10)
  bool get isAtMaxKeys => publicKeys.length >= 10;

  /// Get key by ID
  AccountPublicKey? keyById(String keyId) {
    try {
      return publicKeys.firstWhere((AccountPublicKey k) => k.id == keyId);
    } catch (_) {
      return null;
    }
  }

  Account copyWith({
    String? displayName,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
    List<AccountPublicKey>? publicKeys,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id,
      username: username,
      displayName: displayName ?? this.displayName,
      contactEmail: contactEmail ?? this.contactEmail,
      contactTelegram: contactTelegram ?? this.contactTelegram,
      contactTwitter: contactTwitter ?? this.contactTwitter,
      contactDiscord: contactDiscord ?? this.contactDiscord,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      bio: bio ?? this.bio,
      publicKeys: publicKeys ?? this.publicKeys,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AccountPublicKey {
  AccountPublicKey({
    required this.id,
    required this.publicKey,
    required this.icPrincipal,
    required this.isActive,
    required this.addedAt,
    this.disabledAt,
    this.disabledByKeyId,
  });

  factory AccountPublicKey.fromJson(Map<String, dynamic> json) {
    return AccountPublicKey(
      id: json['id'] as String,
      publicKey: json['publicKey'] as String? ?? json['public_key'] as String,
      icPrincipal: json['icPrincipal'] as String? ?? json['ic_principal'] as String,
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool,
      addedAt: DateTime.parse(json['addedAt'] as String? ?? json['added_at'] as String),
      disabledAt: json['disabledAt'] != null || json['disabled_at'] != null
          ? DateTime.parse(json['disabledAt'] as String? ?? json['disabled_at'] as String)
          : null,
      disabledByKeyId: json['disabledByKeyId'] as String? ?? json['disabled_by_key_id'] as String?,
    );
  }

  final String id;
  final String publicKey; // hex encoded (0x...)
  final String icPrincipal; // IC principal derived from public key
  final bool isActive;
  final DateTime addedAt;
  final DateTime? disabledAt;
  final String? disabledByKeyId; // ID of key that disabled this key

  /// Format public key for display (first 6 + last 4 characters)
  String get displayKey {
    if (publicKey.length <= 12) return publicKey;
    return '${publicKey.substring(0, 6)}...${publicKey.substring(publicKey.length - 4)}';
  }

  /// Format IC principal for display (first 5 + last 3 characters)
  String get displayPrincipal {
    if (icPrincipal.length <= 10) return icPrincipal;
    return '${icPrincipal.substring(0, 5)}...${icPrincipal.substring(icPrincipal.length - 3)}';
  }
}

/// Request payload for account registration
///
/// Must include signature, timestamp, and nonce for replay protection.
/// See ACCOUNT_PROFILES_DESIGN.md section "Signature Payload Format".
class RegisterAccountRequest {
  RegisterAccountRequest({
    required this.username,
    required this.displayName,
    this.contactEmail,
    this.contactTelegram,
    this.contactTwitter,
    this.contactDiscord,
    this.websiteUrl,
    this.bio,
    required this.publicKey,
    required this.timestamp,
    required this.nonce,
    required this.signature,
  });

  final String username;
  final String displayName;
  final String? contactEmail;
  final String? contactTelegram;
  final String? contactTwitter;
  final String? contactDiscord;
  final String? websiteUrl;
  final String? bio;
  final String publicKey; // hex encoded
  final int timestamp; // Unix timestamp (seconds)
  final String nonce; // UUID v4
  final String signature; // hex or base64 encoded

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'username': username,
      'displayName': displayName,
      if (contactEmail != null) 'contactEmail': contactEmail,
      if (contactTelegram != null) 'contactTelegram': contactTelegram,
      if (contactTwitter != null) 'contactTwitter': contactTwitter,
      if (contactDiscord != null) 'contactDiscord': contactDiscord,
      if (websiteUrl != null) 'websiteUrl': websiteUrl,
      if (bio != null) 'bio': bio,
      'publicKey': publicKey,
      'timestamp': timestamp,
      'nonce': nonce,
      'signature': signature,
    };
  }

  /// Create canonical JSON for signing (alphabetically ordered fields)
  ///
  /// Example: {"action":"register_account","nonce":"...","publicKey":"...","timestamp":1700000000,"username":"alice"}
  Map<String, dynamic> toCanonicalPayload() {
    return <String, dynamic>{
      'action': 'register_account',
      'nonce': nonce,
      'publicKey': publicKey,
      'timestamp': timestamp,
      'username': username,
    };
  }
}

/// Request payload for adding a public key to an account
class AddPublicKeyRequest {
  AddPublicKeyRequest({
    required this.username,
    required this.newPublicKey,
    required this.signingPublicKey,
    required this.timestamp,
    required this.nonce,
    required this.signature,
  });

  final String username;
  final String newPublicKey; // hex encoded
  final String signingPublicKey; // hex encoded (must be active key)
  final int timestamp; // Unix timestamp (seconds)
  final String nonce; // UUID v4
  final String signature; // hex or base64 encoded

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'newPublicKey': newPublicKey,
      'signingPublicKey': signingPublicKey,
      'timestamp': timestamp,
      'nonce': nonce,
      'signature': signature,
    };
  }

  /// Create canonical JSON for signing
  ///
  /// Example: {"action":"add_key","newPublicKey":"...","nonce":"...","signingPublicKey":"...","timestamp":1700000100,"username":"alice"}
  Map<String, dynamic> toCanonicalPayload() {
    return <String, dynamic>{
      'action': 'add_key',
      'newPublicKey': newPublicKey,
      'nonce': nonce,
      'signingPublicKey': signingPublicKey,
      'timestamp': timestamp,
      'username': username,
    };
  }
}

/// Request payload for removing a public key from an account
class RemovePublicKeyRequest {
  RemovePublicKeyRequest({
    required this.username,
    required this.keyId,
    required this.signingPublicKey,
    required this.timestamp,
    required this.nonce,
    required this.signature,
  });

  final String username;
  final String keyId; // UUID of key to remove
  final String signingPublicKey; // hex encoded (must be active key)
  final int timestamp; // Unix timestamp (seconds)
  final String nonce; // UUID v4
  final String signature; // hex or base64 encoded

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'signingPublicKey': signingPublicKey,
      'timestamp': timestamp,
      'nonce': nonce,
      'signature': signature,
    };
  }

  /// Create canonical JSON for signing
  ///
  /// Example: {"action":"remove_key","keyId":"...","nonce":"...","signingPublicKey":"...","timestamp":1700000200,"username":"alice"}
  Map<String, dynamic> toCanonicalPayload() {
    return <String, dynamic>{
      'action': 'remove_key',
      'keyId': keyId,
      'nonce': nonce,
      'signingPublicKey': signingPublicKey,
      'timestamp': timestamp,
      'username': username,
    };
  }
}

/// Request payload for updating account profile
class UpdateAccountRequest {
  UpdateAccountRequest({
    required this.username,
    this.displayName,
    this.contactEmail,
    this.contactTelegram,
    this.contactTwitter,
    this.contactDiscord,
    this.websiteUrl,
    this.bio,
    required this.signingPublicKey,
    required this.timestamp,
    required this.nonce,
    required this.signature,
  });

  final String username;
  final String? displayName;
  final String? contactEmail;
  final String? contactTelegram;
  final String? contactTwitter;
  final String? contactDiscord;
  final String? websiteUrl;
  final String? bio;
  final String signingPublicKey; // hex encoded (must be active key)
  final int timestamp; // Unix timestamp (seconds)
  final String nonce; // UUID v4
  final String signature; // hex or base64 encoded

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (displayName != null) 'displayName': displayName,
      if (contactEmail != null) 'contactEmail': contactEmail,
      if (contactTelegram != null) 'contactTelegram': contactTelegram,
      if (contactTwitter != null) 'contactTwitter': contactTwitter,
      if (contactDiscord != null) 'contactDiscord': contactDiscord,
      if (websiteUrl != null) 'websiteUrl': websiteUrl,
      if (bio != null) 'bio': bio,
      'signingPublicKey': signingPublicKey,
      'timestamp': timestamp,
      'nonce': nonce,
      'signature': signature,
    };
  }

  /// Create canonical JSON for signing (only includes fields being updated)
  ///
  /// Example: {"action":"update_profile","bio":"New bio","displayName":"New Name","nonce":"...","signingPublicKey":"...","timestamp":1700000300,"username":"alice"}
  Map<String, dynamic> toCanonicalPayload() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'action': 'update_profile',
      'nonce': nonce,
      'signingPublicKey': signingPublicKey,
      'timestamp': timestamp,
      'username': username,
    };

    // Only include fields being updated in the signature
    if (displayName != null) payload['displayName'] = displayName;
    if (contactEmail != null) payload['contactEmail'] = contactEmail;
    if (contactTelegram != null) payload['contactTelegram'] = contactTelegram;
    if (contactTwitter != null) payload['contactTwitter'] = contactTwitter;
    if (contactDiscord != null) payload['contactDiscord'] = contactDiscord;
    if (websiteUrl != null) payload['websiteUrl'] = websiteUrl;
    if (bio != null) payload['bio'] = bio;

    return payload;
  }
}

/// Username validation result
class UsernameValidation {
  const UsernameValidation({
    required this.isValid,
    this.error,
  });

  final bool isValid;
  final String? error;

  static const UsernameValidation valid = UsernameValidation(isValid: true);

  factory UsernameValidation.invalid(String error) {
    return UsernameValidation(isValid: false, error: error);
  }
}
