import 'dart:convert';
import 'profile_keypair.dart';

/// Profile represents a user profile with cryptographic keypairs and backend account
///
/// Architecture: Profile-Centric Model (Browser Profiles)
/// Each profile is an isolated container (like Chrome/Firefox profiles) containing:
/// - Profile metadata (local name, settings)
/// - 1-10 cryptographic keypairs (owned by THIS profile only)
/// - Backend account reference (@username)
///
/// Key Principles:
/// - Tree structure: Profile → Keypairs (not graph)
/// - No key sharing across profiles
/// - 1:1 Profile-Account mapping
/// - Complete profile isolation
class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.keypairs,
    this.username,
    this.activeKeypairId,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(keypairs.isNotEmpty, 'Profile must have at least one keypair'),
       assert(keypairs.length <= 10, 'Profile cannot have more than 10 keypairs');

  /// Unique profile identifier (UUID)
  final String id;

  /// Profile display name (local, user-chosen)
  final String name;

  /// Keypairs owned by this profile (1-10)
  /// Each keypair belongs to exactly ONE profile
  final List<ProfileKeypair> keypairs;

  /// Backend account username (if registered)
  /// Null if profile hasn't been registered on marketplace yet
  final String? username;

  /// ID of the active keypair used for signing operations
  /// Null means use the first keypair (default behavior)
  final String? activeKeypairId;

  /// Profile creation timestamp
  final DateTime createdAt;

  /// Profile last update timestamp
  final DateTime updatedAt;

  /// Get active keypair used for signing operations
  /// Returns the keypair with activeKeypairId, or the first keypair if not set
  ProfileKeypair get primaryKeypair {
    if (activeKeypairId != null) {
      final keypair = getKeypair(activeKeypairId!);
      if (keypair != null) return keypair;
    }
    return keypairs.first;
  }

  /// Check if profile is registered on backend
  bool get isRegistered => username != null;

  /// Check if profile can add more keypairs
  bool get canAddKeypair => keypairs.length < 10;

  /// Get keypair by ID
  ProfileKeypair? getKeypair(String keypairId) {
    try {
      return keypairs.firstWhere((k) => k.id == keypairId);
    } catch (_) {
      return null;
    }
  }

  /// Create a copy with updated fields
  Profile copyWith({
    String? name,
    List<ProfileKeypair>? keypairs,
    String? username,
    String? activeKeypairId,
    bool clearActiveKeypairId = false,
    DateTime? updatedAt,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      keypairs: keypairs ?? this.keypairs,
      username: username ?? this.username,
      activeKeypairId: clearActiveKeypairId ? null : (activeKeypairId ?? this.activeKeypairId),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'keypairs': keypairs.map((k) => k.toJson()).toList(),
      if (username != null) 'username': username,
      if (activeKeypairId != null) 'activeKeypairId': activeKeypairId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Deserialize from JSON
  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String,
      keypairs: (json['keypairs'] as List<dynamic>)
          .map((k) => ProfileKeypair.fromJson(k as Map<String, dynamic>))
          .toList(),
      username: json['username'] as String?,
      activeKeypairId: json['activeKeypairId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  @override
  String toString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Profile && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
