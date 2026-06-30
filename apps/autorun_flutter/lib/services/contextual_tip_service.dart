import 'package:shared_preferences/shared_preferences.dart';

/// Features where contextual tips can be shown.
enum ContextualTipFeature {
  scriptsView,
  scriptEditor,
  exploreView,
  marketplace,
  profileCreation,
}

/// Content for a contextual tip.
class ContextualTipContent {
  const ContextualTipContent({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

/// Service for managing contextual onboarding tips.
///
/// Instead of showing upfront onboarding dialogs, tips appear
/// in-context when the user first encounters each feature.
class ContextualTipService {
  static const String _prefsKeyPrefix = 'contextual_tip_seen_';

  /// Returns true if the tip for the given feature should be shown.
  Future<bool> shouldShowTip(ContextualTipFeature feature) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_getKey(feature)) ?? false);
  }

  /// Marks a tip as seen so it won't show again.
  Future<void> markTipSeen(ContextualTipFeature feature) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_getKey(feature), true);
  }

  /// Gets the content for a tip.
  ContextualTipContent getTipContent(ContextualTipFeature feature) {
    switch (feature) {
      case ContextualTipFeature.scriptsView:
        return const ContextualTipContent(
          title: 'Your Scripts',
          description:
              'This is where your local scripts appear. Create new scripts or '
              'download from the marketplace to get started.',
        );
      case ContextualTipFeature.scriptEditor:
        return const ContextualTipContent(
          title: 'Script Editor',
          description:
              'Write TypeScript here and tap Run to execute. Scripts can '
              'interact with ICP canisters and automate workflows.',
        );
      case ContextualTipFeature.exploreView:
        return const ContextualTipContent(
          title: 'Explore Canisters',
          description:
              'Discover and interact with ICP canisters. Browse services, '
              'call methods, and explore the ecosystem.',
        );
      case ContextualTipFeature.marketplace:
        return const ContextualTipContent(
          title: 'Marketplace',
          description:
              'Browse scripts shared by the community. Download and run '
              'them locally or use them as starting points for your own.',
        );
      case ContextualTipFeature.profileCreation:
        return const ContextualTipContent(
          title: 'Create a Profile',
          description:
              'A profile stores your settings and lets you publish scripts '
              'to the marketplace. Create one to unlock all features.',
        );
    }
  }

  /// Resets all tips to show again.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    for (final feature in ContextualTipFeature.values) {
      await prefs.remove(_getKey(feature));
    }
  }

  String _getKey(ContextualTipFeature feature) =>
      '$_prefsKeyPrefix${feature.name}';
}
