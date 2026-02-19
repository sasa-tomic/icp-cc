import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _onboardingShownKey = 'onboarding_shown';
  static const String _onboardingVersionKey = 'onboarding_version';
  static const int _currentVersion = 1;

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

  Future<void> resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_onboardingShownKey);
    await prefs.remove(_onboardingVersionKey);
  }
}
