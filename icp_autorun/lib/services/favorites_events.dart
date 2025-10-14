import 'package:flutter/foundation.dart';

class FavoritesEvents {
  FavoritesEvents._();

  static final ValueNotifier<int> _version = ValueNotifier<int>(0);

  static Listenable get listenable => _version;

  static void notifyChanged() {
    _version.value = _version.value + 1;
  }
}
