import 'package:shared_preferences/shared_preferences.dart';

/// Manages the dismiss state for the offline banner.
///
/// The banner reappears after 1 hour since last dismissal.
class OfflineBannerDismissService {
  static const String _dismissedAtKey = 'offline_banner_dismissed_at';

  /// The duration after which the banner reappears.
  static const Duration reappearDuration = Duration(hours: 1);

  /// Checks if the banner should be shown based on last dismiss time.
  ///
  /// Returns `true` if:
  /// - Never been dismissed
  /// - Was dismissed more than 1 hour ago
  Future<bool> shouldShowBanner() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissedAtStr = prefs.getString(_dismissedAtKey);

    if (dismissedAtStr == null) {
      return true;
    }

    final dismissedAt = DateTime.parse(dismissedAtStr);
    final elapsed = DateTime.now().difference(dismissedAt);

    return elapsed >= reappearDuration;
  }

  /// Marks the banner as dismissed.
  ///
  /// The banner will reappear after 1 hour.
  Future<void> dismissBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dismissedAtKey, DateTime.now().toIso8601String());
  }

  /// Clears the dismiss state, causing the banner to show immediately.
  ///
  /// Useful for testing or resetting user preferences.
  Future<void> clearDismissState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dismissedAtKey);
  }
}
