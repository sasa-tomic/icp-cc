class IdentityProfile {
  IdentityProfile({
    required this.id,
    required this.principal,
    required this.displayName,
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
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  IdentityProfile copyWith({
    String? displayName,
    Map<String, dynamic>? metadata,
  }) {
    return IdentityProfile(
      id: id,
      principal: principal,
      displayName: displayName ?? this.displayName,
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
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? const <String, dynamic>{};

  final String principal;
  final String displayName;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'principal': principal,
      'display_name': displayName,
      'metadata': metadata,
    }..removeWhere((String _, dynamic value) => value == null);
  }

  IdentityProfileDraft copyWith({
    String? displayName,
    Map<String, dynamic>? metadata,
  }) {
    return IdentityProfileDraft(
      principal: principal,
      displayName: displayName ?? this.displayName,
      metadata: metadata ?? this.metadata,
    );
  }
}
