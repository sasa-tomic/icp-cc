import 'package:flutter/widgets.dart';

import '../controllers/profile_controller.dart';

/// ProfileScope provides ProfileController to the widget tree using InheritedWidget
///
/// Usage:
/// ```dart
/// ProfileScope(
///   controller: profileController,
///   child: MyApp(),
/// )
/// ```
///
/// Access in widgets:
/// ```dart
/// final profileController = ProfileScope.of(context);
/// ```
class ProfileScope extends InheritedNotifier<ProfileController> {
  const ProfileScope({
    super.key,
    required ProfileController controller,
    required super.child,
  }) : super(notifier: controller);

  static ProfileController of(BuildContext context, {bool listen = true}) {
    ProfileScope? scope;
    if (listen) {
      scope = context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    } else {
      final InheritedElement? element =
          context.getElementForInheritedWidgetOfExactType<ProfileScope>();
      scope = element?.widget as ProfileScope?;
    }
    if (scope == null || scope.notifier == null) {
      throw StateError('ProfileScope is not available in the current context.');
    }
    return scope.notifier!;
  }
}
