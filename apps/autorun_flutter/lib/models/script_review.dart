class ScriptReview {
  final String id;
  final String userId;
  final String scriptId;
  final int rating; // 1-5 stars
  final String? comment;
  final bool isVerifiedPurchase;
  final String status; // approved, pending, rejected
  final DateTime createdAt;
  final DateTime updatedAt;

  const ScriptReview({
    required this.id,
    required this.userId,
    required this.scriptId,
    required this.rating,
    this.comment,
    this.isVerifiedPurchase = false,
    this.status = 'pending',
    required this.createdAt,
    required this.updatedAt,
  });

  factory ScriptReview.fromJson(Map<String, dynamic> json) {
    return ScriptReview(
      id: json['id'] as String,
      userId: json['userId'] as String,
      scriptId: json['scriptId'] as String,
      rating: json['rating'] as int,
      comment: json['comment'] as String?,
      isVerifiedPurchase: json['isVerifiedPurchase'] as bool? ?? false,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'scriptId': scriptId,
      'rating': rating,
      'comment': comment,
      'isVerifiedPurchase': isVerifiedPurchase,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'ScriptReview{scriptId: $scriptId, rating: $rating, verified: $isVerifiedPurchase}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScriptReview &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
