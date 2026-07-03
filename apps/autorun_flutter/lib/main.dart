import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';

import 'config/app_config.dart';
import 'controllers/account_controller.dart';
import 'controllers/profile_controller.dart';
import 'controllers/script_controller.dart';
import 'models/script_template.dart';
import 'rust/native_bridge.dart';
import 'services/deep_link_service.dart';
import 'services/marketplace_open_api_service.dart';
import 'services/onboarding_service.dart';
import 'services/script_repository.dart';
import 'services/secure_storage_readiness.dart';
import 'services/settings_service.dart';
import 'services/spotlight_service.dart';
import 'theme/app_design_system.dart';
import 'theme/modern_components.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/dapps_screen.dart';
import 'screens/scripts_screen.dart';
import 'screens/unified_setup_wizard.dart';
import 'widgets/connectivity_scope.dart';
import 'widgets/keyboard_shortcuts.dart';
import 'widgets/profile_scope.dart';
import 'widgets/profile_menu.dart';
import 'widgets/shortcuts_help_sheet.dart';
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
    if (index >= 0 && index < 3) {
      setState(() => _currentIndex = index);
    }
  }

  void _handleShowShortcuts() {
    showShortcutsHelpSheet(context);
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

    // With contextual onboarding, no upfront dialog is shown.
    // This call auto-marks the onboarding version for migration purposes.
    await _onboardingService.shouldShowOnboarding(
      hasProfiles: profileController.profiles.isNotEmpty,
      hasScripts: scriptController.scripts.isNotEmpty,
    );
    // Contextual tips are shown in-context via ContextualTipService
    // when user first reaches each feature screen.

    // First-run gate: a brand-new user has no profile, so walk them through
    // the unified setup wizard (the polished single-screen onboarding) before
    // they reach an empty Scripts screen with no path to identity creation.
    if (mounted) {
      await showFirstRunSetupIfNeeded(
        context: context,
        profileController: profileController,
        accountController: _getAccountController(),
        secureStorageReadiness: SecureStorageReadiness(),
      );
      if (mounted) setState(() {});
    }
  }

  void _handleSpotlightComplete() {}

  void _handleSpotlightDismiss() {}

  AccountController _getAccountController() {
    final appState = context.findAncestorStateOfType<_KeypairAppState>();
    return appState!._accountController;
  }

  void _showProfileMenu() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: AppDesignSystem.sheetBorderRadius,
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
      onShowShortcuts: _handleShowShortcuts,
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
                              BookmarksScreen(bridge: _bridge),
                              const DappsScreen(),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (DesktopShortcuts.isDesktop)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: ShortcutsHelpButton(),
                          ),
                        ProfileAvatarButton(
                          key: _profileMenuKey,
                          displayName: displayName,
                          hasAccount: activeProfile?.username != null,
                          onTap: _showProfileMenu,
                        ),
                      ],
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
          label: kCanistersTabLabel,
        ),
        ModernNavigationItem(
          icon: Icons.apps_outlined,
          activeIcon: Icons.apps_rounded,
          label: 'Dapps',
        ),
      ],
    );
  }
}

/// First-run gate. When the user has no profile yet, present the
/// [UnifiedSetupWizard] so onboarding is guided (one form + success screen)
/// instead of a dead-end empty Scripts screen. Returns whether the wizard was
/// shown. Top-level so the first-run decision is unit-testable in isolation.
Future<bool> showFirstRunSetupIfNeeded({
  required BuildContext context,
  required ProfileController profileController,
  required AccountController accountController,
  SecureStorageReadiness? secureStorageReadiness,
}) async {
  if (profileController.profiles.isNotEmpty) {
    return false;
  }
  await Navigator.of(context).push<UnifiedSetupResult>(
    MaterialPageRoute<UnifiedSetupResult>(
      fullscreenDialog: true,
      builder: (_) => UnifiedSetupWizard(
        profileController: profileController,
        accountController: accountController,
        // WU-S2: gate profile creation on secure-storage readiness so the
        // wizard can complete on Linux (and surface an actionable panel +
        // attempt gnome-keyring auto-start when the keyring is down). When
        // null (unit tests of the gate), the gate is skipped.
        secureStorageReadiness: secureStorageReadiness,
      ),
    ),
  );
  return true;
}
