import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'services/script_signature_service.dart';
import 'services/secure_storage_readiness.dart';
import 'services/service_locator.dart';
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
import 'widgets/profile_setup_chip.dart';
import 'widgets/shortcuts_help_sheet.dart';
import 'widgets/spotlight_overlay.dart';
import 'widgets/script_details_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupServiceLocator();
  await ScriptTemplates.ensureInitialized();
  AppConfig.debugPrintConfig();
  // Test affordance for Playwright/CDP-driven web e2e. The Flutter Web engine
  // only enables its a11y semantics tree (the DOM a Playwright harness asserts
  // on) when it detects a screen reader or a Tab keypress at the engine level;
  // headless Chromium triggers neither reliably. This dart-define forces
  // semantics ON at boot — production users see no change (unset by default).
  if (kIsWeb) {
    const forceSemantics =
        bool.fromEnvironment('FLUTTER_WEB_FORCE_SEMANTICS', defaultValue: false);
    if (forceSemantics) {
      SystemChannels.accessibility.send(<Object?>['enableSemantics', null]);
    }
  }
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
      // W7-2: `GET /scripts/:id` no longer carries entitlement (that branch
      // leaked the paid bundle). Fetch metadata-only, then resolve the
      // signed entitlement separately so the right CTA (Download vs Buy)
      // renders for paid scripts.
      var script = await MarketplaceOpenApiService().getScriptDetails(scriptId);

      // For a paid script with unknown entitlement, ask the signed endpoint.
      if (script.price > 0 && script.purchased == null) {
        final purchased = await _resolveDeepLinkEntitlement(scriptId);
        if (purchased != null) {
          script = script.copyWith(purchased: purchased);
        }
      }

      if (!mounted) return;
      // ignore: use_build_context_synchronously
      final navContext = _navigatorKey.currentContext;
      if (navContext == null) return;
      // ignore: use_build_context_synchronously
      Navigator.of(navContext).pop();

      final owned = script.isDownloadable;
      // ignore: use_build_context_synchronously
      await showDialog<void>(
        // ignore: use_build_context_synchronously
        context: navContext,
        builder: (ctx) => ScriptDetailsDialog(
          script: script,
          onDownload: script.price == 0
              ? () => _downloadScriptFromDeepLink(navContext, script)
              : (owned
                  ? () => _downloadScriptFromDeepLink(navContext, script)
                  : null),
          onBuy: (script.price > 0 && !owned)
              ? () => _showPurchaseUnavailableFromDeepLink(navContext, script)
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

  /// Best-effort signed entitlement check for the deep-link path (W7-2).
  /// Returns the `purchased` boolean for [scriptId] on success, or `null` if
  /// there is no active profile / account, the keypair is missing, or the
  /// signed check failed (callers fall back to the safe default — Buy CTA).
  Future<bool?> _resolveDeepLinkEntitlement(String scriptId) async {
    final profile = _profileController.activeProfile;
    if (profile == null) return null;
    final keypair = profile.primaryKeypair;
    try {
      final signed = await ScriptSignatureService.signEntitlement(
        signingKeypair: keypair,
        scriptId: scriptId,
      );
      final result = await MarketplaceOpenApiService()
          .checkEntitlement(scriptId, signed: signed);
      return result.purchased;
    } catch (e) {
      debugPrint('Deep-link entitlement check for $scriptId failed: $e');
      return null;
    }
  }

  Future<void> _showPurchaseUnavailableFromDeepLink(
      BuildContext context, dynamic script) async {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Open the Scripts tab to purchase this paid script.'),
        duration: Duration(seconds: 4),
      ),
    );
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

  /// Re-opens the [UnifiedSetupWizard] from the persistent "Set up profile"
  /// affordance (IH-9 / UXR-8). This is the always-reachable path back to
  /// profile creation after a user dismissed the first-run wizard. Mirrors the
  /// first-run gate without forcing it — the user explicitly opted in by
  /// tapping the chip.
  void _reopenSetupWizard() {
    presentSetupWizard(
      context: context,
      profileController: ProfileScope.of(context, listen: false),
      accountController: _getAccountController(),
      secureStorageReadiness: SecureStorageReadiness(),
    ).then((_) {
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
    // IH-9 / UXR-8: when there is no profile at all, surface a persistent,
    // always-visible "Set up profile" affordance in the top-right cluster so
    // profile creation is reachable on every tab (the empty-state CTA is
    // off-screen as soon as the user has any content). The wizard's own
    // first-run gate separately remembers a deliberate dismissal, so this never
    // forces a recurring wizard — it only gives a one-tap path back.
    final needsProfileSetup = activeProfile == null;

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
                        if (needsProfileSetup)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ProfileSetupChip(
                              onSetUp: _reopenSetupWizard,
                            ),
                          ),
                        if (DesktopShortcuts.isDesktop)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: ShortcutsHelpButton(),
                          ),
                        ProfileAvatarButton(
                          key: _profileMenuKey,
                          displayName: displayName,
                          hasAccount: activeProfile?.username != null,
                          // When setup is pending, the chip is the clear
                          // primary CTA; keep the avatar compact to avoid a
                          // redundant "No account" label next to it.
                          showLabel: !needsProfileSetup,
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

/// SharedPreferences key recording that the user explicitly dismissed the
/// first-run wizard without creating a profile (IH-9 / UXR-8). Honored by
/// [showFirstRunSetupIfNeeded] so a deliberate dismissal is respected across
/// restarts (no wizard loop), while [presentSetupWizard] (the persistent
/// "Set up profile" affordance) stays reachable to re-enter setup at any time.
const String _firstRunWizardDismissedKey = 'first_run_wizard_dismissed';

/// Presents the [UnifiedSetupWizard] modally and records a dismissal when the
/// user closes it without creating a profile ([result] is `null`). This is the
/// single shared entry point for both the first-run gate and the persistent
/// "Set up profile" affordance (DRY). Returns the wizard result (null =
/// dismissed, non-null = profile created).
Future<UnifiedSetupResult?> presentSetupWizard({
  required BuildContext context,
  required ProfileController profileController,
  required AccountController accountController,
  SecureStorageReadiness? secureStorageReadiness,
}) async {
  final result = await Navigator.of(context).push<UnifiedSetupResult>(
    MaterialPageRoute<UnifiedSetupResult>(
      fullscreenDialog: true,
      builder: (_) => UnifiedSetupWizard(
        profileController: profileController,
        accountController: accountController,
        // WU-S2: gate profile creation on secure-storage readiness so the
        // wizard can complete on Linux (and surface an actionable panel +
        // attempt gnome-keyring auto-start when the keyring is down). When
        // null (unit tests), the gate is skipped.
        secureStorageReadiness: secureStorageReadiness,
      ),
    ),
  );
  if (result == null) {
    // The user chose to browse as a guest. Remember that choice so the wizard
    // does NOT force-reappear on every restart; the persistent "Set up profile"
    // affordance keeps profile creation one tap away instead.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstRunWizardDismissedKey, true);
  }
  return result;
}

/// First-run gate. When the user has no profile yet AND has not previously
/// dismissed the wizard, present the [UnifiedSetupWizard] so onboarding is
/// guided (one form + success screen) instead of a dead-end empty Scripts
/// screen. Returns whether the wizard was shown. Top-level so the first-run
/// decision is unit-testable in isolation.
///
/// A deliberate dismissal is remembered (IH-9 / UXR-8): the wizard never
/// loops on restart. Profile creation stays reachable via the persistent
/// "Set up profile" affordance in the shell (see [presentSetupWizard]).
Future<bool> showFirstRunSetupIfNeeded({
  required BuildContext context,
  required ProfileController profileController,
  required AccountController accountController,
  SecureStorageReadiness? secureStorageReadiness,
}) async {
  if (profileController.profiles.isNotEmpty) {
    return false;
  }
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_firstRunWizardDismissedKey) ?? false) {
    // The user previously dismissed the wizard; respect that choice rather
    // than nagging them on every launch. The persistent shell affordance is
    // the path back.
    return false;
  }
  await presentSetupWizard(
    // The await on SharedPreferences above spans an async gap, but the only
    // caller (MainHomePage._checkAndShowOnboarding) guards with `mounted`
    // before invoking the gate, so the context is still valid. Mirrors the
    // ignore pattern used throughout this deep-link/gate file.
    // ignore: use_build_context_synchronously
    context: context,
    profileController: profileController,
    accountController: accountController,
    secureStorageReadiness: secureStorageReadiness,
  );
  return true;
}
