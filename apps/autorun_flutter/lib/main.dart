import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';

import 'config/app_config.dart';
import 'controllers/account_controller.dart';
import 'controllers/profile_controller.dart';
import 'controllers/script_controller.dart';
import 'models/profile_keypair.dart';
import 'models/script_template.dart';
import 'rust/native_bridge.dart';
import 'services/deep_link_service.dart';
import 'services/marketplace_open_api_service.dart';
import 'services/onboarding_service.dart';
import 'services/script_repository.dart';
import 'services/settings_service.dart';
import 'services/spotlight_service.dart';
import 'theme/app_design_system.dart';
import 'theme/modern_components.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/canister_client_screen.dart';
import 'screens/quick_profile_creation_dialog.dart';
import 'screens/scripts_screen.dart';
import 'widgets/connectivity_scope.dart';
import 'widgets/keyboard_shortcuts.dart';
import 'widgets/post_setup_guide.dart';
import 'widgets/profile_scope.dart';
import 'widgets/profile_menu.dart';
import 'widgets/spotlight_overlay.dart';
import 'widgets/script_details_dialog.dart';

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
  final SettingsService _settingsService = SettingsService();
  final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier(ThemeMode.system);
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<DeepLinkData>? _deepLinkSubscription;
  AppLinks? _appLinks;

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
    _loadThemePreference();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.linux) {
      return;
    }

    _appLinks = AppLinks();

    _deepLinkSubscription = DeepLinkService.instance.linkStream.listen(
      _handleDeepLink,
    );

    _appLinks?.uriLinkStream.listen((uri) {
      DeepLinkService.instance.handleLink(uri);
    });
  }

  void _handleDeepLink(DeepLinkData data) {
    final context = _navigatorKey.currentContext;
    if (context == null || !mounted) return;

    switch (data.type) {
      case DeepLinkType.script:
        if (data.scriptId != null) {
          _openScriptFromDeepLink(context, data.scriptId!);
        }
    }
  }

  Future<void> _openScriptFromDeepLink(
      BuildContext context, String scriptId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final script =
          await MarketplaceOpenApiService().getScriptDetails(scriptId);

      if (!mounted) return;
      // ignore: use_build_context_synchronously
      final navContext = _navigatorKey.currentContext;
      if (navContext == null) return;
      // ignore: use_build_context_synchronously
      Navigator.of(navContext).pop();

      // ignore: use_build_context_synchronously
      await showDialog<void>(
        // ignore: use_build_context_synchronously
        context: navContext,
        builder: (ctx) => ScriptDetailsDialog(
          script: script,
          onDownload: script.price == 0
              ? () => _downloadScriptFromDeepLink(navContext, script)
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      final navContext = _navigatorKey.currentContext;
      if (navContext == null) return;
      // ignore: use_build_context_synchronously
      Navigator.of(navContext).pop();

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(navContext).showSnackBar(
        SnackBar(
          content: Text('Script not found: $scriptId'),
          // ignore: use_build_context_synchronously
          backgroundColor: Theme.of(navContext).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _downloadScriptFromDeepLink(
      BuildContext context, dynamic script) async {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Script downloaded')),
    );
  }

  Future<void> _loadThemePreference() async {
    final themeMode = await _settingsService.getThemeMode();
    _themeModeNotifier.value = themeMode;
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    _profileController.dispose();
    _accountController.dispose();
    _themeModeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProfileScope(
      controller: _profileController,
      child: ConnectivityScope(
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: _themeModeNotifier,
          builder: (context, themeMode, child) {
            return MaterialApp(
              navigatorKey: _navigatorKey,
              title: 'ICP Autorun',
              theme: AppDesignSystem.lightTheme,
              darkTheme: AppDesignSystem.darkTheme,
              themeMode: themeMode,
              home: MainHomePage(
                settingsService: _settingsService,
                themeModeNotifier: _themeModeNotifier,
              ),
            );
          },
        ),
      ),
    );
  }
}

class MainHomePage extends StatefulWidget {
  const MainHomePage({
    required this.settingsService,
    required this.themeModeNotifier,
    super.key,
  });

  final SettingsService settingsService;
  final ValueNotifier<ThemeMode> themeModeNotifier;

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage> {
  int _currentIndex = 0;
  final RustBridgeLoader _bridge = const RustBridgeLoader();
  final OnboardingService _onboardingService = OnboardingService();
  final SpotlightService _spotlightService = SpotlightService();
  bool _onboardingChecked = false;

  final GlobalKey<State<ScriptsScreen>> _scriptsScreenKey = GlobalKey();
  final GlobalKey _homeTabKey = GlobalKey();
  final GlobalKey _discoverTabKey = GlobalKey();
  final GlobalKey _profileMenuKey = GlobalKey();
  final GlobalKey _scriptsSectionKey = GlobalKey();

  late final Map<String, GlobalKey> _spotlightTargetKeys;

  @override
  void dispose() {
    _scriptsScreenKey.currentState?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _spotlightTargetKeys = {
      'home_tab': _homeTabKey,
      'discover_tab': _discoverTabKey,
      'profile_menu': _profileMenuKey,
      'scripts_section': _scriptsSectionKey,
      'final_step': GlobalKey(),
    };
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
    if (index >= 0 && index < 2) {
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowOnboarding();
      });
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
      // Show quick profile creation dialog (single action)
      final result = await showDialog<QuickProfileCreationResult>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const QuickProfileCreationDialog(),
      );

      await _onboardingService.markOnboardingShown();

      // Create profile if name provided
      if (result != null && result.hasName && mounted) {
        await profileController.createProfile(
          profileName: result.profileName!,
          algorithm: KeyAlgorithm.ed25519,
          setAsActive: true,
        );
        setState(() {});
        // Mark app as usable - PostSetupGuide will be delayed until
        // user has seen the app (either by action or 5 second delay)
        await _onboardingService.markAppUsable();
        _schedulePostSetupGuide();
      }
    }
  }

  /// Schedules the PostSetupGuide to show after delay or first meaningful action
  void _schedulePostSetupGuide() {
    // Check immediately in case conditions are already met
    _tryShowPostSetupGuide();

    // Also check after the delay period
    Future.delayed(OnboardingService.postSetupGuideDelay, () {
      if (mounted) _tryShowPostSetupGuide();
    });
  }

  Future<void> _tryShowPostSetupGuide() async {
    // Check if guide was already shown
    final alreadyShown = !await _onboardingService.shouldShowPostSetupGuide();
    if (alreadyShown || !mounted) return;

    // Check if conditions are met (action OR delay)
    final isReady = await _onboardingService.isPostSetupGuideReady();
    if (!isReady || !mounted) return;

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

  void _handleSpotlightComplete() {}

  void _handleSpotlightDismiss() {}

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
    // Record that user performed a meaningful action (exploring canisters)
    _onboardingService.recordFirstMeaningfulAction();

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => CanisterClientScreen(
          bridge: _bridge,
          initialCanisterId: initialCanisterId,
          initialMethodName: initialMethodName,
        ),
      ),
    );
  }

  void _showProfileMenu() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ProfileMenuWidget(
        profileController: ProfileScope.of(context, listen: false),
        accountController: _getAccountController(),
        onThemeChanged: _reloadTheme,
      ),
    ).then((_) {
      // Refresh state when menu closes
      if (mounted) setState(() {});
    });
  }

  Future<void> _reloadTheme() async {
    final themeMode = await widget.settingsService.getThemeMode();
    widget.themeModeNotifier.value = themeMode;
  }

  @override
  Widget build(BuildContext context) {
    final profileController = ProfileScope.of(context);
    final activeProfile = profileController.activeProfile;
    final displayName = activeProfile?.name ?? 'Guest';

    return DesktopShortcuts(
      onCreateScript: _handleCreateScript,
      onFocusSearch: _handleFocusSearch,
      onRefresh: _handleRefresh,
      onNavigateToTab: _handleNavigateToTab,
      child: EscapeHandler(
        onEscape: _handleEscape,
        child: SpotlightTour(
          service: _spotlightService,
          targetKeys: _spotlightTargetKeys,
          onComplete: _handleSpotlightComplete,
          onDismiss: _handleSpotlightDismiss,
          child: Scaffold(
            body: SafeArea(
              top: true,
              bottom: true,
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Container(
                          key: _scriptsSectionKey,
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
                                  bridge: _bridge,
                                  onOpenClient: _openCanisterClient),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  Positioned(
                    top: 8,
                    right: 16,
                    child: ProfileAvatarButton(
                      key: _profileMenuKey,
                      displayName: displayName,
                      hasAccount: activeProfile?.username != null,
                      onTap: _showProfileMenu,
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: _buildModernNavigationBar(),
          ),
        ),
      ),
    );
  }

  Widget _buildModernNavigationBar() {
    return ModernNavigationBar(
      key: _currentIndex == 0 ? _homeTabKey : _discoverTabKey,
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() => _currentIndex = index);
      },
      items: const [
        ModernNavigationItem(
          icon: Icons.code_outlined,
          activeIcon: Icons.code_rounded,
          label: 'Scripts',
        ),
        ModernNavigationItem(
          icon: Icons.dns_outlined,
          activeIcon: Icons.dns_rounded,
          label: 'Canisters',
        ),
      ],
    );
  }
}
