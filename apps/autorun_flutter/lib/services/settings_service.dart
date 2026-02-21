import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for persisting and retrieving app settings.
///
/// Uses SharedPreferences for local storage of user preferences.
class SettingsService {
  static const String _themeModeKey = 'theme_mode';

  /// Gets the stored theme mode preference.
  ///
  /// Returns [ThemeMode.system] by default if no preference is stored.
  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex = prefs.getInt(_themeModeKey);

    if (themeModeIndex == null) {
      return ThemeMode.system;
    }

    return ThemeMode.values[themeModeIndex];
  }

  /// Persists the theme mode preference.
  ///
  /// Stores the index of the [ThemeMode] enum value.
  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }
}
