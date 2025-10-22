class MarketplaceUser {
  final String userId;
  final String username;
  final String displayName;
  final String? bio;
  final String? avatar;
  final String? website;
  final List<String>? socialLinks;
  final int scriptsPublished;
  final int totalDownloads;
  final double averageRating;
  final bool isVerifiedDeveloper;
  final List<String> favorites;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MarketplaceUser({
    required this.userId,
    required this.username,
    required this.displayName,
    this.bio,
    this.avatar,
    this.website,
    this.socialLinks,
    this.scriptsPublished = 0,
    this.totalDownloads = 0,
    this.averageRating = 0.0,
    this.isVerifiedDeveloper = false,
    this.favorites = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory MarketplaceUser.fromJson(Map<String, dynamic> json) {
    return MarketplaceUser(
      userId: json['userId'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      bio: json['bio'] as String?,
      avatar: json['avatar'] as String?,
      website: json['website'] as String?,
      socialLinks: (json['socialLinks'] as List<dynamic>?)?.cast<String>(),
      scriptsPublished: json['scriptsPublished'] as int? ?? 0,
      totalDownloads: json['totalDownloads'] as int? ?? 0,
      averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0.0,
      isVerifiedDeveloper: json['isVerifiedDeveloper'] as bool? ?? false,
      favorites: (json['favorites'] as List<dynamic>?)?.cast<String>() ?? [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'displayName': displayName,
      'bio': bio,
      'avatar': avatar,
      'website': website,
      'socialLinks': socialLinks,
      'scriptsPublished': scriptsPublished,
      'totalDownloads': totalDownloads,
      'averageRating': averageRating,
      'isVerifiedDeveloper': isVerifiedDeveloper,
      'favorites': favorites,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  MarketplaceUser copyWith({
    String? userId,
    String? username,
    String? displayName,
    String? bio,
    String? avatar,
    String? website,
    List<String>? socialLinks,
    int? scriptsPublished,
    int? totalDownloads,
    double? averageRating,
    bool? isVerifiedDeveloper,
    List<String>? favorites,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MarketplaceUser(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatar: avatar ?? this.avatar,
      website: website ?? this.website,
      socialLinks: socialLinks ?? this.socialLinks,
      scriptsPublished: scriptsPublished ?? this.scriptsPublished,
      totalDownloads: totalDownloads ?? this.totalDownloads,
      averageRating: averageRating ?? this.averageRating,
      isVerifiedDeveloper: isVerifiedDeveloper ?? this.isVerifiedDeveloper,
      favorites: favorites ?? this.favorites,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'MarketplaceUser{username: $username, displayName: $displayName, scripts: $scriptsPublished}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarketplaceUser &&
          runtimeType == other.runtimeType &&
          userId == other.userId;

  @override
  int get hashCode => userId.hashCode;
}