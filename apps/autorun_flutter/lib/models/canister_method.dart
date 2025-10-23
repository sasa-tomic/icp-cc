/// Represents a canister method with its signature information
class CanisterMethod {
  const CanisterMethod({
    required this.name,
    required this.kind,
    required this.args,
    this.returnType,
    this.description,
  });

  final String name;
  /// 0=query, 1=update, 2=composite
  final int kind;
  final List<CanisterArg> args;
  final String? returnType;
  final String? description;

  factory CanisterMethod.fromJson(Map<String, dynamic> json) {
    return CanisterMethod(
      name: json['name'] as String? ?? '',
      kind: (json['kind'] as num?)?.toInt() ?? 0,
      args: (json['args'] as List<dynamic>?)
              ?.map((arg) => CanisterArg.fromJson(arg as Map<String, dynamic>))
              .toList() ??
          [],
      returnType: json['return_type'] as String?,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'kind': kind,
      'args': args.map((arg) => arg.toJson()).toList(),
      'return_type': returnType,
      'description': description,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CanisterMethod &&
        other.name == name &&
        other.kind == kind &&
        _listEquals(other.args, args);
  }

  @override
  int get hashCode => name.hashCode ^ kind.hashCode ^ args.hashCode;

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Represents a canister method argument
class CanisterArg {
  const CanisterArg({
    required this.name,
    required this.type,
    this.optional = false,
    this.defaultValue,
  });

  final String name;
  final String type;
  final bool optional;
  final dynamic defaultValue;

  factory CanisterArg.fromJson(Map<String, dynamic> json) {
    return CanisterArg(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      optional: json['optional'] as bool? ?? false,
      defaultValue: json['default_value'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'optional': optional,
      'default_value': defaultValue,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CanisterArg &&
        other.name == name &&
        other.type == type &&
        other.optional == optional &&
        other.defaultValue == defaultValue;
  }

  @override
  int get hashCode => name.hashCode ^ type.hashCode ^ optional.hashCode ^ defaultValue.hashCode;
}