import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OnboardingItem {
  browseMarketplace,
  downloadScript,
  createScript,
  tryCanisterClient,
  setUpPasskey;

  String get label {
    switch (this) {
      case OnboardingItem.browseMarketplace:
        return 'Browse the marketplace';
      case OnboardingItem.downloadScript:
        return 'Download your first script';
      case OnboardingItem.createScript:
        return 'Create your first script';
      case OnboardingItem.tryCanisterClient:
        return 'Try the canister client';
      case OnboardingItem.setUpPasskey:
        return 'Set up a passkey';
    }
  }

  String get description {
    switch (this) {
      case OnboardingItem.browseMarketplace:
        return 'Explore scripts shared by the community';
      case OnboardingItem.downloadScript:
        return 'Add a script to your library';
      case OnboardingItem.createScript:
        return 'Start building your own automation';
      case OnboardingItem.tryCanisterClient:
        return 'Discover and interact with ICP services';
      case OnboardingItem.setUpPasskey:
        return 'Secure your account with passkeys';
    }
  }

  IconData get icon {
    switch (this) {
      case OnboardingItem.browseMarketplace:
        return Icons.storefront_outlined;
      case OnboardingItem.downloadScript:
        return Icons.download_outlined;
      case OnboardingItem.createScript:
        return Icons.code_rounded;
      case OnboardingItem.tryCanisterClient:
        return Icons.dns_outlined;
      case OnboardingItem.setUpPasskey:
        return Icons.key_outlined;
    }
  }

  static const String _prefsKeyPrefix = 'onboarding_item_';
  String get prefsKey => '$_prefsKeyPrefix$name';
}

class OnboardingProgress {
  final int completed;
  final int total;

  const OnboardingProgress({required this.completed, required this.total});

  bool get isComplete => completed >= total;
  double get percentage => total > 0 ? completed / total : 0.0;
}

class OnboardingProgressService {
  static const String _dismissedKey = 'onboarding_guide_dismissed';
  static const String _snoozedUntilKey = 'onboarding_snoozed_until';
  static const Duration _snoozeDuration = Duration(hours: 24);

  Future<List<OnboardingItem>> getIncompleteItems() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingItem.values
        .where((item) => !(prefs.getBool(item.prefsKey) ?? false))
        .toList();
  }

  Future<bool> isComplete(OnboardingItem item) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(item.prefsKey) ?? false;
  }

  Future<bool> markComplete(OnboardingItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyComplete = prefs.getBool(item.prefsKey) ?? false;
    if (alreadyComplete) return false;
    await prefs.setBool(item.prefsKey, true);
    return true;
  }

  Future<OnboardingProgress> getCompletionProgress() async {
    final prefs = await SharedPreferences.getInstance();
    var completed = 0;
    for (final item in OnboardingItem.values) {
      if (prefs.getBool(item.prefsKey) ?? false) {
        completed++;
      }
    }
    return OnboardingProgress(
      completed: completed,
      total: OnboardingItem.values.length,
    );
  }

  Future<bool> shouldShowGuide() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_dismissedKey) ?? false) return false;

    final snoozedUntil = prefs.getInt(_snoozedUntilKey);
    if (snoozedUntil != null) {
      final snoozeTime = DateTime.fromMillisecondsSinceEpoch(snoozedUntil);
      if (DateTime.now().isBefore(snoozeTime)) return false;
    }

    final progress = await getCompletionProgress();
    return !progress.isComplete;
  }

  Future<void> dismissPermanently() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissedKey, true);
  }

  Future<void> snooze() async {
    final prefs = await SharedPreferences.getInstance();
    final snoozedUntil = DateTime.now().add(_snoozeDuration);
    await prefs.setInt(_snoozedUntilKey, snoozedUntil.millisecondsSinceEpoch);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dismissedKey);
    await prefs.remove(_snoozedUntilKey);
    for (final item in OnboardingItem.values) {
      await prefs.remove(item.prefsKey);
    }
  }

  Future<void> markAction(OnboardingAction action) async {
    switch (action) {
      case OnboardingAction.browsedMarketplace:
        await markComplete(OnboardingItem.browseMarketplace);
      case OnboardingAction.downloadedScript:
        await markComplete(OnboardingItem.downloadScript);
      case OnboardingAction.createdScript:
        await markComplete(OnboardingItem.createScript);
      case OnboardingAction.usedCanisterClient:
        await markComplete(OnboardingItem.tryCanisterClient);
      case OnboardingAction.configuredPasskey:
        await markComplete(OnboardingItem.setUpPasskey);
    }
  }
}

enum OnboardingAction {
  browsedMarketplace,
  downloadedScript,
  createdScript,
  usedCanisterClient,
  configuredPasskey,
}
