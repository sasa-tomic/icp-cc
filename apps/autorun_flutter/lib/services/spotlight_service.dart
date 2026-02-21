import 'package:shared_preferences/shared_preferences.dart';

enum SpotlightPosition {
  top,
  bottom,
  left,
  right,
  center,
}

class SpotlightStep {
  final String targetKey;
  final String title;
  final String description;
  final SpotlightPosition position;

  const SpotlightStep({
    required this.targetKey,
    required this.title,
    required this.description,
    required this.position,
  });
}

class SpotlightService {
  static const String _currentStepKey = 'spotlight_current_step';
  static const String _completedKey = 'spotlight_completed';
  static const String _dismissedKey = 'spotlight_dismissed';
  static const String _explicitlyStartedKey = 'spotlight_explicitly_started';
  static const int totalSteps = 5;

  static const List<SpotlightStep> _steps = [
    SpotlightStep(
      targetKey: 'home_tab',
      title: 'Your Scripts',
      description:
          'This is your main workspace where you can manage and run your scripts. Your local scripts and marketplace downloads appear here.',
      position: SpotlightPosition.top,
    ),
    SpotlightStep(
      targetKey: 'scripts_section',
      title: 'Your Scripts',
      description:
          'Create, edit, and run Lua scripts here. Scripts can interact with ICP canisters and automate your workflows.',
      position: SpotlightPosition.bottom,
    ),
    SpotlightStep(
      targetKey: 'discover_tab',
      title: 'Canisters',
      description:
          'Explore the Internet Computer ecosystem. Browse canisters, interact with services, and discover new dapps.',
      position: SpotlightPosition.top,
    ),
    SpotlightStep(
      targetKey: 'profile_menu',
      title: 'Profile Menu',
      description:
          'Access your profile, passkeys, settings, and more. Click your avatar to open the menu.',
      position: SpotlightPosition.bottom,
    ),
    SpotlightStep(
      targetKey: 'final_step',
      title: "You're All Set!",
      description:
          'You know the basics. Create scripts, explore canisters, and make the most of ICP Autorun!',
      position: SpotlightPosition.center,
    ),
  ];

  /// Returns true ONLY if the user has explicitly started the tour via Settings.
  /// The tour does NOT auto-start for new users - it's opt-in only.
  Future<bool> shouldShowTour() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_completedKey) ?? false;
    final dismissed = prefs.getBool(_dismissedKey) ?? false;
    final explicitlyStarted = prefs.getBool(_explicitlyStartedKey) ?? false;

    // Only show if user explicitly started AND hasn't completed or dismissed
    return explicitlyStarted && !completed && !dismissed;
  }

  Future<int> currentStep() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentStepKey) ?? 0;
  }

  Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  Future<bool> isDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dismissedKey) ?? false;
  }

  Future<void> nextStep() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_currentStepKey) ?? 0;
    await prefs.setInt(_currentStepKey, current + 1);
  }

  Future<void> previousStep() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_currentStepKey) ?? 0;
    if (current > 0) {
      await prefs.setInt(_currentStepKey, current - 1);
    }
  }

  Future<void> goToStep(int step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentStepKey, step.clamp(0, totalSteps));
  }

  Future<void> completeTour() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
    await prefs.setInt(_currentStepKey, totalSteps);
  }

  Future<void> dismissTour() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, true);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentStepKey);
    await prefs.remove(_completedKey);
    await prefs.remove(_dismissedKey);
    await prefs.remove(_explicitlyStartedKey);
  }

  /// Resets the tour and marks it as explicitly started.
  /// This should be called when user clicks "Restart Tour" in Settings.
  /// The tour will then be shown on the next app launch.
  Future<void> resetAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentStepKey);
    await prefs.remove(_completedKey);
    await prefs.remove(_dismissedKey);
    await prefs.setBool(_explicitlyStartedKey, true);
  }

  SpotlightStep getStepInfo(int step) {
    if (step < 0 || step >= _steps.length) {
      throw RangeError(
          'Step $step is out of range. Valid range: 0-${_steps.length - 1}');
    }
    return _steps[step];
  }

  List<SpotlightStep> get steps => List.unmodifiable(_steps);
}
