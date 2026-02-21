import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _onboardingShownKey = 'onboarding_shown';
  static const String _onboardingVersionKey = 'onboarding_version';
  static const String _postSetupGuideShownKey = 'post_setup_guide_shown';
  static const String _appUsableSinceKey = 'app_usable_since';
  static const String _firstMeaningfulActionKey = 'first_meaningful_action';
  static const int _currentVersion = 1;

  /// Minimum delay before showing PostSetupGuide after app becomes usable
  static const Duration postSetupGuideDelay = Duration(seconds: 5);

  Future<bool> shouldShowOnboarding({
    required bool hasProfiles,
    required bool hasScripts,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final wasShown = prefs.getBool(_onboardingShownKey) ?? false;
    final savedVersion = prefs.getInt(_onboardingVersionKey) ?? 0;

    if (wasShown && savedVersion >= _currentVersion) {
      return false;
    }

    return !hasProfiles && !hasScripts;
  }

  Future<void> markOnboardingShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingShownKey, true);
    await prefs.setInt(_onboardingVersionKey, _currentVersion);
  }

  Future<bool> shouldShowPostSetupGuide() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_postSetupGuideShownKey) ?? false);
  }

  Future<void> markPostSetupGuideShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_postSetupGuideShownKey, true);
  }

  /// Records when the app became usable (after profile creation dialog closes)
  /// This is used to delay PostSetupGuide until user has seen the app
  Future<void> markAppUsable() async {
    final prefs = await SharedPreferences.getInstance();
    // Don't overwrite if already set
    if (prefs.containsKey(_appUsableSinceKey)) return;
    await prefs.setInt(
        _appUsableSinceKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Records that the user performed their first meaningful action
  /// (viewing a script, exploring a canister, etc.)
  /// This allows PostSetupGuide to be shown immediately
  Future<void> recordFirstMeaningfulAction() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstMeaningfulActionKey, true);
  }

  /// Checks if PostSetupGuide is ready to be shown
  /// Returns true if either:
  /// 1. User has performed a meaningful action, OR
  /// 2. The minimum delay has passed since app became usable
  Future<bool> isPostSetupGuideReady() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if user performed a meaningful action
    final hasAction = prefs.getBool(_firstMeaningfulActionKey) ?? false;
    if (hasAction) return true;

    // Check if enough time has passed since app became usable
    final appUsableSince = prefs.getInt(_appUsableSinceKey);
    if (appUsableSince == null) return false;

    final usableTime = DateTime.fromMillisecondsSinceEpoch(appUsableSince);
    final elapsed = DateTime.now().difference(usableTime);
    return elapsed >= postSetupGuideDelay;
  }

  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingShownKey);
    await prefs.remove(_onboardingVersionKey);
    await prefs.remove(_postSetupGuideShownKey);
    await prefs.remove(_appUsableSinceKey);
    await prefs.remove(_firstMeaningfulActionKey);
  }
}
