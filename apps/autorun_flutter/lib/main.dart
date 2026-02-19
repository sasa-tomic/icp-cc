import 'dart:async';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'controllers/profile_controller.dart';
import 'controllers/script_controller.dart';
import 'models/profile.dart';
import 'models/script_template.dart';
import 'rust/native_bridge.dart';
import 'services/marketplace_open_api_service.dart';
import 'services/onboarding_service.dart';
import 'services/script_repository.dart';
import 'theme/app_design_system.dart';
import 'theme/modern_components.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/profile_home_page.dart';
import 'screens/scripts_screen.dart';
import 'screens/welcome_onboarding_screen.dart';
import 'widgets/key_parameters_dialog.dart';
import 'widgets/profile_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ScriptTemplates.ensureInitialized();
  AppConfig.debugPrintConfig();
  runApp(const KeypairApp());
}

class KeypairApp extends StatefulWidget {
  const KeypairApp({super.key});

  @override
  State<KeypairApp> createState() => _KeypairAppState();
}

class _KeypairAppState extends State<KeypairApp> {
  late final ProfileController _profileController;

  @override
  void initState() {
    super.initState();
    _profileController = ProfileController(
      marketplaceService: MarketplaceOpenApiService(),
    );
    unawaited(_profileController.ensureLoaded());
  }

  @override
  void dispose() {
    _profileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProfileScope(
      controller: _profileController,
      child: MaterialApp(
        title: 'ICP Autorun',
        theme: AppDesignSystem.lightTheme,
        darkTheme: AppDesignSystem.darkTheme,
        themeMode: ThemeMode.system,
        home: const MainHomePage(),
      ),
    );
  }
}

class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  int _currentIndex = 0;
  final RustBridgeLoader _bridge = const RustBridgeLoader();
  final OnboardingService _onboardingService = OnboardingService();
  bool _onboardingChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_onboardingChecked) {
      _onboardingChecked = true;
      _checkAndShowOnboarding();
    }
  }

  Future<void> _checkAndShowOnboarding() async {
    final profileController = ProfileScope.of(context, listen: false);
    await profileController.ensureLoaded();

    final scriptController = ScriptController(ScriptRepository.instance);
    await scriptController.ensureLoaded();

    final shouldShow = await _onboardingService.shouldShowOnboarding(
      hasProfiles: profileController.profiles.isNotEmpty,
      hasScripts: scriptController.scripts.isNotEmpty,
    );

    if (shouldShow && mounted) {
      final result = await Navigator.of(context).push<OnboardingResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => const WelcomeOnboardingScreen(),
        ),
      );

      await _onboardingService.markOnboardingShown();

      if (result == OnboardingResult.getStarted && mounted) {
        _showCreateProfileDialog();
      } else if (result == OnboardingResult.browseMarketplace && mounted) {
        setState(() => _currentIndex = 0);
      }
    }
  }

  Future<void> _showCreateProfileDialog() async {
    final profileController = ProfileScope.of(context, listen: false);
    final KeyParameters? params = await showDialog<KeyParameters>(
      context: context,
      builder: (context) => const KeyParametersDialog(
        title: 'Create Your First Profile',
      ),
    );

    if (params == null || !mounted) return;

    final String profileName =
        params.label ?? 'Profile ${profileController.profiles.length + 1}';

    await profileController.createProfile(
      profileName: profileName,
      algorithm: params.algorithm,
      mnemonic: params.seed,
      setAsActive: true,
    );
  }

  Future<void> _openCanisterClient(
      {String? initialCanisterId, String? initialMethodName}) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return CanisterClientSheet(
          bridge: _bridge,
          initialCanisterId: initialCanisterId,
          initialMethodName: initialMethodName,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.95),
                      Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: IndexedStack(
                  index: _currentIndex,
                  children: <Widget>[
                    const ScriptsScreen(),
                    BookmarksScreen(
                        bridge: _bridge, onOpenClient: _openCanisterClient),
                    const ProfileHomePage(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      bottomNavigationBar: _buildModernNavigationBar(),
    );
  }

  Widget _buildModernNavigationBar() {
    final ProfileController profileController = ProfileScope.of(context);
    final bool shouldShowBadge = _shouldShowProfileBadge(profileController);

    return ModernNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() => _currentIndex = index);
      },
      items: [
        const ModernNavigationItem(
          icon: Icons.code_rounded,
          activeIcon: Icons.code_rounded,
          label: 'Scripts',
        ),
        const ModernNavigationItem(
          icon: Icons.bookmark_border_rounded,
          activeIcon: Icons.bookmark_rounded,
          label: 'Bookmarks',
        ),
        ModernNavigationItem(
          icon: Icons.verified_user_outlined,
          activeIcon: Icons.verified_user_rounded,
          label: 'Profile',
          showBadge: shouldShowBadge,
        ),
      ],
    );
  }

  bool _shouldShowProfileBadge(ProfileController controller) {
    final Profile? active = controller.activeProfile;
    // Show badge only for anonymous mode (no active profile)
    return active == null;
  }
}
