class PurchaseRecord {
  final String id;
  final String userId;
  final String scriptId;
  final String transactionId;
  final double price;
  final String currency;
  final String paymentMethod;
  final String status; // pending, completed, failed, refunded
  final DateTime createdAt;

  const PurchaseRecord({
    required this.id,
    required this.userId,
    required this.scriptId,
    required this.transactionId,
    required this.price,
    this.currency = 'USD',
    required this.paymentMethod,
    this.status = 'pending',
    required this.createdAt,
  });

  factory PurchaseRecord.fromJson(Map<String, dynamic> json) {
    return PurchaseRecord(
      id: json['id'] as String,
      userId: json['userId'] as String,
      scriptId: json['scriptId'] as String,
      transactionId: json['transactionId'] as String,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      paymentMethod: json['paymentMethod'] as String,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'scriptId': scriptId,
      'transactionId': transactionId,
      'price': price,
      'currency': currency,
      'paymentMethod': paymentMethod,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  PurchaseRecord copyWith({
    String? id,
    String? userId,
    String? scriptId,
    String? transactionId,
    double? price,
    String? currency,
    String? paymentMethod,
    String? status,
    DateTime? createdAt,
  }) {
    return PurchaseRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      scriptId: scriptId ?? this.scriptId,
      transactionId: transactionId ?? this.transactionId,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'PurchaseRecord{scriptId: $scriptId, userId: $userId, price: $price, status: $status}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurchaseRecord &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

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