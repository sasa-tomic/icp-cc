import 'package:shared_preferences/shared_preferences.dart';

/// Actions that may require a profile.
enum AppAction {
  browseMarketplace,
  downloadScript,
  publishScript,
  savePreferences,
  createScript,
  runScript,
}

/// Service for managing onboarding state.
///
/// With contextual onboarding, this service:
/// - No longer triggers upfront dialogs on first launch
/// - Provides utility for checking if profile is needed for actions
class OnboardingService {
  static const String _onboardingShownKey = 'onboarding_shown';
  static const String _onboardingVersionKey = 'onboarding_version';
  static const int _currentVersion = 2; // Bumped for contextual onboarding

  /// Returns false always - no upfront onboarding.
  ///
  /// The app now opens directly to the main screen.
  /// Contextual tips appear in-context when users reach each feature.
  Future<bool> shouldShowOnboarding({
    required bool hasProfiles,
    required bool hasScripts,
  }) async {
    // Mark onboarding as shown for migration purposes
    final prefs = await SharedPreferences.getInstance();
    final wasShown = prefs.getBool(_onboardingShownKey) ?? false;
    final savedVersion = prefs.getInt(_onboardingVersionKey) ?? 0;

    if (!wasShown || savedVersion < _currentVersion) {
      await prefs.setBool(_onboardingShownKey, true);
      await prefs.setInt(_onboardingVersionKey, _currentVersion);
    }

    // Always return false - no upfront onboarding
    return false;
  }

  /// Marks onboarding as shown (kept for backward compatibility).
  Future<void> markOnboardingShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingShownKey, true);
    await prefs.setInt(_onboardingVersionKey, _currentVersion);
  }

  /// Checks if a profile is required for the given action.
  ///
  /// Some actions (browsing, downloading) don't require a profile.
  /// Others (publishing, saving preferences) do.
  Future<bool> needsProfileForAction({
    required AppAction action,
    required bool hasProfile,
  }) async {
    // If already has a profile, no need to prompt
    if (hasProfile) return false;

    // Determine if this action requires a profile
    switch (action) {
      case AppAction.browseMarketplace:
      case AppAction.downloadScript:
      case AppAction.createScript:
      case AppAction.runScript:
        // These actions don't require a profile
        return false;
      case AppAction.publishScript:
      case AppAction.savePreferences:
        // These require a profile
        return true;
    }
  }

  /// Resets onboarding state.
  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingShownKey);
    await prefs.remove(_onboardingVersionKey);
  }
}
