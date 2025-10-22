class MarketplaceScript {
  final String id;
  final String title;
  final String description;
  final String category;
  final List<String> tags;
  final String authorId;
  final String authorName;
  final double price;
  final String currency;
  final int downloads;
  final double rating;
  final int reviewCount;
  final int? verifiedReviewCount;
  final String luaSource;
  final String? iconUrl;
  final List<String>? screenshots;
  final List<String> canisterIds;
  final String? compatibility;
  final String? version;
  final bool isPublic;
  final bool isApproved;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MarketplaceAuthor? author;

  const MarketplaceScript({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.tags = const [],
    required this.authorId,
    required this.authorName,
    this.price = 0.0,
    this.currency = 'USD',
    this.downloads = 0,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.verifiedReviewCount,
    required this.luaSource,
    this.iconUrl,
    this.screenshots,
    this.canisterIds = const [],
    this.compatibility,
    this.version,
    this.isPublic = true,
    this.isApproved = false,
    required this.createdAt,
    required this.updatedAt,
    this.author,
  });

  factory MarketplaceScript.fromJson(Map<String, dynamic> json) {
    return MarketplaceScript(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      downloads: json['downloads'] as int? ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: json['reviewCount'] as int? ?? 0,
      verifiedReviewCount: json['verifiedReviewCount'] as int?,
      luaSource: json['luaSource'] as String,
      iconUrl: json['iconUrl'] as String?,
      screenshots: (json['screenshots'] as List<dynamic>?)?.cast<String>(),
      canisterIds: (json['canisterIds'] as List<dynamic>?)?.cast<String>() ?? [],
      compatibility: json['compatibility'] as String?,
      version: json['version'] as String?,
      isPublic: json['isPublic'] as bool? ?? true,
      isApproved: json['isApproved'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      author: json['author'] != null
          ? MarketplaceAuthor.fromJson(json['author'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category,
      'tags': tags,
      'authorId': authorId,
      'authorName': authorName,
      'price': price,
      'currency': currency,
      'downloads': downloads,
      'rating': rating,
      'reviewCount': reviewCount,
      'verifiedReviewCount': verifiedReviewCount,
      'luaSource': luaSource,
      'iconUrl': iconUrl,
      'screenshots': screenshots,
      'canisterIds': canisterIds,
      'compatibility': compatibility,
      'version': version,
      'isPublic': isPublic,
      'isApproved': isApproved,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'author': author?.toJson(),
    };
  }

  MarketplaceScript copyWith({
    String? id,
    String? title,
    String? description,
    String? category,
    List<String>? tags,
    String? authorId,
    String? authorName,
    double? price,
    String? currency,
    int? downloads,
    double? rating,
    int? reviewCount,
    int? verifiedReviewCount,
    String? luaSource,
    String? iconUrl,
    List<String>? screenshots,
    List<String>? canisterIds,
    String? compatibility,
    String? version,
    bool? isPublic,
    bool? isApproved,
    DateTime? createdAt,
    DateTime? updatedAt,
    MarketplaceAuthor? author,
  }) {
    return MarketplaceScript(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      downloads: downloads ?? this.downloads,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      verifiedReviewCount: verifiedReviewCount ?? this.verifiedReviewCount,
      luaSource: luaSource ?? this.luaSource,
      iconUrl: iconUrl ?? this.iconUrl,
      screenshots: screenshots ?? this.screenshots,
      canisterIds: canisterIds ?? this.canisterIds,
      compatibility: compatibility ?? this.compatibility,
      version: version ?? this.version,
      isPublic: isPublic ?? this.isPublic,
      isApproved: isApproved ?? this.isApproved,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      author: author ?? this.author,
    );
  }

  @override
  String toString() {
    return 'MarketplaceScript{id: $id, title: $title, category: $category, author: $authorName, price: $price, rating: $rating}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarketplaceScript &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class MarketplaceAuthor {
  final String id;
  final String username;
  final String displayName;
  final String? avatar;
  final bool isVerifiedDeveloper;
  final String? bio;
  final String? website;
  final List<String>? socialLinks;
  final int? scriptsPublished;
  final int? totalDownloads;
  final double? averageRating;

  const MarketplaceAuthor({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatar,
    this.isVerifiedDeveloper = false,
    this.bio,
    this.website,
    this.socialLinks,
    this.scriptsPublished,
    this.totalDownloads,
    this.averageRating,
  });

  factory MarketplaceAuthor.fromJson(Map<String, dynamic> json) {
    return MarketplaceAuthor(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      avatar: json['avatar'] as String?,
      isVerifiedDeveloper: json['isVerifiedDeveloper'] as bool? ?? false,
      bio: json['bio'] as String?,
      website: json['website'] as String?,
      socialLinks: (json['socialLinks'] as List<dynamic>?)?.cast<String>(),
      scriptsPublished: json['scriptsPublished'] as int?,
      totalDownloads: json['totalDownloads'] as int?,
      averageRating: (json['averageRating'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'displayName': displayName,
      'avatar': avatar,
      'isVerifiedDeveloper': isVerifiedDeveloper,
      'bio': bio,
      'website': website,
      'socialLinks': socialLinks,
      'scriptsPublished': scriptsPublished,
      'totalDownloads': totalDownloads,
      'averageRating': averageRating,
    };
  }

  @override
  String toString() {
    return 'MarketplaceAuthor{username: $username, displayName: $displayName, verified: $isVerifiedDeveloper}';
  }
}