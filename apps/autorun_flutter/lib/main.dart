import 'dart:async';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'controllers/account_controller.dart';
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
import 'screens/unified_setup_wizard.dart';
import 'screens/welcome_onboarding_screen.dart';
import 'widgets/keyboard_shortcuts.dart';
import 'widgets/post_setup_guide.dart';
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
  late final AccountController _accountController;

  @override
  void initState() {
    super.initState();
    _profileController = ProfileController(
      marketplaceService: MarketplaceOpenApiService(),
    );
    _accountController = AccountController(
      marketplaceService: MarketplaceOpenApiService(),
      profileController: _profileController,
    );
    unawaited(_profileController.ensureLoaded());
  }

  @override
  void dispose() {
    _profileController.dispose();
    _accountController.dispose();
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

  final GlobalKey<State<ScriptsScreen>> _scriptsScreenKey = GlobalKey();

  @override
  void dispose() {
    _scriptsScreenKey.currentState?.dispose();
    super.dispose();
  }

  void _handleCreateScript() {
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
    }
    final state = _scriptsScreenKey.currentState;
    if (state != null && state.mounted) {
      (state as ScriptsScreenState).createNewScript();
    }
  }

  void _handleFocusSearch() {
    final state = _scriptsScreenKey.currentState;
    if (state != null && state.mounted && _currentIndex == 0) {
      (state as ScriptsScreenState).focusSearch();
    }
  }

  void _handleRefresh() {
    final state = _scriptsScreenKey.currentState;
    if (state != null && state.mounted && _currentIndex == 0) {
      (state as ScriptsScreenState).refreshContent();
    }
  }

  void _handleNavigateToTab(int index) {
    if (index >= 0 && index < 3) {
      setState(() => _currentIndex = index);
    }
  }

  void _handleEscape() {
    Navigator.of(context).maybePop();
  }

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
        _showUnifiedSetupWizard();
      } else if (result == OnboardingResult.browseMarketplace && mounted) {
        setState(() => _currentIndex = 0);
      }
    }
  }

  Future<void> _showUnifiedSetupWizard() async {
    final profileController = ProfileScope.of(context, listen: false);
    final accountController = _getAccountController();

    final result = await Navigator.of(context).push<UnifiedSetupResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => UnifiedSetupWizard(
          profileController: profileController,
          accountController: accountController,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {});
      _showPostSetupGuideIfNeeded();
    }
  }

  Future<void> _showPostSetupGuideIfNeeded() async {
    final shouldShow = await _onboardingService.shouldShowPostSetupGuide();
    if (!shouldShow || !mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => PostSetupGuide(
        onActionSelected: (action) {
          Navigator.of(context).pop();
          _handlePostSetupAction(action);
        },
        onDismiss: () async {
          Navigator.of(context).pop();
          await _onboardingService.markPostSetupGuideShown();
        },
      ),
    );
  }

  void _handlePostSetupAction(PostSetupAction action) async {
    await _onboardingService.markPostSetupGuideShown();

    switch (action) {
      case PostSetupAction.browseMarketplace:
        setState(() => _currentIndex = 0);
      case PostSetupAction.createScript:
        setState(() => _currentIndex = 0);
      case PostSetupAction.exploreCanisters:
        setState(() => _currentIndex = 1);
    }
  }

  AccountController _getAccountController() {
    final appState = context.findAncestorStateOfType<_KeypairAppState>();
    return appState!._accountController;
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
    return DesktopShortcuts(
      onCreateScript: _handleCreateScript,
      onFocusSearch: _handleFocusSearch,
      onRefresh: _handleRefresh,
      onNavigateToTab: _handleNavigateToTab,
      child: EscapeHandler(
        onEscape: _handleEscape,
        child: Scaffold(
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
                        ScriptsScreen(key: _scriptsScreenKey),
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
        ),
      ),
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
          icon: Icons.hub_outlined,
          activeIcon: Icons.hub_rounded,
          label: 'Services',
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
