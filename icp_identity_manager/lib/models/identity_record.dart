import 'dart:convert';

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

class IdentityRecord {
  IdentityRecord({
    required this.id,
    required this.label,
    required this.algorithm,
    required this.publicKey,
    required this.privateKey,
    required this.mnemonic,
    required this.createdAt,
  });

  final String id;
  final String label;
  final KeyAlgorithm algorithm;
  final String publicKey; // base64 encoded
  final String privateKey; // base64 encoded
  final String mnemonic;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'algorithm': keyAlgorithmToString(algorithm),
    'publicKey': publicKey,
    'privateKey': privateKey,
    'mnemonic': mnemonic,
    'createdAt': createdAt.toIso8601String(),
  };

  factory IdentityRecord.fromJson(Map<String, dynamic> json) {
    return IdentityRecord(
      id: json['id'] as String,
      label: json['label'] as String,
      algorithm: keyAlgorithmFromString(json['algorithm'] as String),
      publicKey: json['publicKey'] as String,
      privateKey: json['privateKey'] as String,
      mnemonic: json['mnemonic'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  IdentityRecord copyWith({String? label}) {
    return IdentityRecord(
      id: id,
      label: label ?? this.label,
      algorithm: algorithm,
      publicKey: publicKey,
      privateKey: privateKey,
      mnemonic: mnemonic,
      createdAt: createdAt,
    );
  }

  Map<String, String> exportDetails() {
    return <String, String>{
      'Mnemonic': mnemonic,
      'Public key (base64)': publicKey,
      'Private key (base64)': privateKey,
    };
  }

  @override
  String toString() => jsonEncode(toJson());
}
