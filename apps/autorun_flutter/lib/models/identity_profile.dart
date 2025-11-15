import 'package:collection/collection.dart';

class IdentityProfile {
  IdentityProfile({
    required this.id,
    required this.principal,
    required this.displayName,
    this.username,
    this.contactEmail,
    this.contactTelegram,
    this.contactTwitter,
    this.contactDiscord,
    this.websiteUrl,
    this.bio,
    Map<String, dynamic>? metadata,
    required this.createdAt,
    required this.updatedAt,
  }) : metadata = metadata ?? const <String, dynamic>{};

  factory IdentityProfile.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> envelope =
        json.containsKey('profile') ? Map<String, dynamic>.from(json['profile'] as Map) : json;
    return IdentityProfile(
      id: envelope['id'] as String,
      principal: envelope['principal'] as String,
      displayName: envelope['displayName'] as String? ?? envelope['display_name'] as String? ?? '',
      username: envelope['username'] as String?,
      contactEmail: envelope['contactEmail'] as String? ?? envelope['contact_email'] as String?,
      contactTelegram: envelope['contactTelegram'] as String? ?? envelope['contact_telegram'] as String?,
      contactTwitter: envelope['contactTwitter'] as String? ?? envelope['contact_twitter'] as String?,
      contactDiscord: envelope['contactDiscord'] as String? ?? envelope['contact_discord'] as String?,
      websiteUrl: envelope['websiteUrl'] as String? ?? envelope['website_url'] as String?,
      bio: envelope['bio'] as String?,
      metadata: (envelope['metadata'] as Map?)?.map(
            (dynamic key, dynamic value) => MapEntry<String, dynamic>(
              key as String,
              value,
            ),
          ) ??
          const <String, dynamic>{},
      createdAt: DateTime.parse(envelope['createdAt'] as String? ?? envelope['created_at'] as String),
      updatedAt: DateTime.parse(envelope['updatedAt'] as String? ?? envelope['updated_at'] as String),
    );
  }

  final String id;
  final String principal;
  final String displayName;
  final String? username;
  final String? contactEmail;
  final String? contactTelegram;
  final String? contactTwitter;
  final String? contactDiscord;
  final String? websiteUrl;
  final String? bio;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isComplete {
    return <String?>[
      username,
      contactEmail,
      contactTelegram,
      contactTwitter,
      contactDiscord,
      websiteUrl,
      bio,
    ].firstWhereOrNull((String? value) => value != null && value.trim().isNotEmpty) != null;
  }

  IdentityProfile copyWith({
    String? displayName,
    String? username,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
    Map<String, dynamic>? metadata,
  }) {
    return IdentityProfile(
      id: id,
      principal: principal,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      contactEmail: contactEmail ?? this.contactEmail,
      contactTelegram: contactTelegram ?? this.contactTelegram,
      contactTwitter: contactTwitter ?? this.contactTwitter,
      contactDiscord: contactDiscord ?? this.contactDiscord,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      bio: bio ?? this.bio,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class IdentityProfileDraft {
  IdentityProfileDraft({
    required this.principal,
    required this.displayName,
    this.username,
    this.contactEmail,
    this.contactTelegram,
    this.contactTwitter,
    this.contactDiscord,
    this.websiteUrl,
    this.bio,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? const <String, dynamic>{};

  final String principal;
  final String displayName;
  final String? username;
  final String? contactEmail;
  final String? contactTelegram;
  final String? contactTwitter;
  final String? contactDiscord;
  final String? websiteUrl;
  final String? bio;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'principal': principal,
      'display_name': displayName,
      'username': username,
      'contact_email': contactEmail,
      'contact_telegram': contactTelegram,
      'contact_twitter': contactTwitter,
      'contact_discord': contactDiscord,
      'website_url': websiteUrl,
      'bio': bio,
      'metadata': metadata,
    }..removeWhere((String _, dynamic value) => value == null);
  }

  IdentityProfileDraft copyWith({
    String? displayName,
    String? username,
    String? contactEmail,
    String? contactTelegram,
    String? contactTwitter,
    String? contactDiscord,
    String? websiteUrl,
    String? bio,
    Map<String, dynamic>? metadata,
  }) {
    return IdentityProfileDraft(
      principal: principal,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      contactEmail: contactEmail ?? this.contactEmail,
      contactTelegram: contactTelegram ?? this.contactTelegram,
      contactTwitter: contactTwitter ?? this.contactTwitter,
      contactDiscord: contactDiscord ?? this.contactDiscord,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      bio: bio ?? this.bio,
      metadata: metadata ?? this.metadata,
    );
  }
}
