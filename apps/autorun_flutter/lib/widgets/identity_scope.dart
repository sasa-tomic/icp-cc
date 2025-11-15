import 'package:flutter/widgets.dart';

import '../controllers/identity_controller.dart';

class IdentityScope extends InheritedNotifier<IdentityController> {
  const IdentityScope({
    super.key,
    required IdentityController controller,
    required super.child,
  }) : super(notifier: controller);

  static IdentityController of(BuildContext context, {bool listen = true}) {
    IdentityScope? scope;
    if (listen) {
      scope = context.dependOnInheritedWidgetOfExactType<IdentityScope>();
    } else {
      final InheritedElement? element =
          context.getElementForInheritedWidgetOfExactType<IdentityScope>();
      scope = element?.widget as IdentityScope?;
    }
    if (scope == null || scope.notifier == null) {
      throw StateError('IdentityScope is not available in the current context.');
    }
    return scope.notifier!;
  }
}
