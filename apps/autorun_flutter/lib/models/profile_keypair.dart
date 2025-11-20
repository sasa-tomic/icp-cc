import 'dart:convert';

/// Cryptographic key algorithm
enum KeyAlgorithm { ed25519, secp256k1 }

KeyAlgorithm keyAlgorithmFromString(String value) {
  switch (value) {
    case 'ed25519':
      return KeyAlgorithm.ed25519;
    case 'secp256k1':
      return KeyAlgorithm.secp256k1;
    default:
      throw ArgumentError('Unsupported key algorithm: $value');
  }
}

String keyAlgorithmToString(KeyAlgorithm algorithm) {
  switch (algorithm) {
    case KeyAlgorithm.ed25519:
      return 'ed25519';
    case KeyAlgorithm.secp256k1:
      return 'secp256k1';
  }
}

/// ProfileKeypair represents a single cryptographic keypair within a Profile
///
/// Architecture: Profile-Centric Model
/// - Each keypair belongs to exactly ONE profile
/// - Profiles contain 1-10 keypairs
/// - No cross-profile key sharing
///
/// Contains:
/// - Public/private key pair (base64 encoded)
/// - Mnemonic phrase for backup/recovery
/// - Algorithm (Ed25519 or secp256k1)
/// - Metadata (id, label, creation timestamp)
class ProfileKeypair {
  ProfileKeypair({
    required this.id,
    required this.label,
    required this.algorithm,
    required this.publicKey,
    required this.privateKey,
    required this.mnemonic,
    required this.createdAt,
  });

  /// Unique keypair identifier (UUID)
  final String id;

  /// User-friendly label for this keypair (e.g., "Laptop", "Phone", "Hardware Wallet")
  final String label;

  /// Cryptographic algorithm used for this keypair
  final KeyAlgorithm algorithm;

  /// Public key (base64 encoded)
  final String publicKey;

  /// Private key (base64 encoded) - stored securely
  final String privateKey;

  /// Mnemonic phrase for recovery (stored securely)
  final String mnemonic;

  /// Keypair creation timestamp
  final DateTime createdAt;

  /// Create a copy with updated fields
  ProfileKeypair copyWith({String? label}) {
    return ProfileKeypair(
      id: id,
      label: label ?? this.label,
      algorithm: algorithm,
      publicKey: publicKey,
      privateKey: privateKey,
      mnemonic: mnemonic,
      createdAt: createdAt,
    );
  }

  /// Export keypair details for backup (includes sensitive data)
  Map<String, String> exportDetails() {
    return <String, String>{
      'Mnemonic': mnemonic,
      'Public key (base64)': publicKey,
      'Private key (base64)': privateKey,
    };
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'algorithm': keyAlgorithmToString(algorithm),
        'publicKey': publicKey,
        'privateKey': privateKey,
        'mnemonic': mnemonic,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Deserialize from JSON
  factory ProfileKeypair.fromJson(Map<String, dynamic> json) {
    return ProfileKeypair(
      id: json['id'] as String,
      label: json['label'] as String,
      algorithm: keyAlgorithmFromString(json['algorithm'] as String),
      publicKey: json['publicKey'] as String,
      privateKey: json['privateKey'] as String,
      mnemonic: json['mnemonic'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileKeypair &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
