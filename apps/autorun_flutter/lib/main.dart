import 'dart:async';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'controllers/profile_controller.dart';
import 'models/profile.dart';
import 'models/script_template.dart';
import 'rust/native_bridge.dart';
import 'theme/app_design_system.dart';
import 'theme/modern_components.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/profile_home_page.dart';
import 'screens/scripts_screen.dart';
import 'widgets/profile_scope.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ScriptTemplates.ensureInitialized();
  AppConfig.debugPrintConfig();
  runApp(const IdentityApp());
}

class IdentityApp extends StatefulWidget {
  const IdentityApp({super.key});

  @override
  State<IdentityApp> createState() => _IdentityAppState();
}

class _IdentityAppState extends State<IdentityApp> {
  late final ProfileController _profileController;

  @override
  void initState() {
    super.initState();
    _profileController = ProfileController();
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

  Future<void> _openCanisterClient({String? initialCanisterId, String? initialMethodName}) async {
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
                      Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                      Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: IndexedStack(
                  index: _currentIndex,
                  children: <Widget>[
                    const ScriptsScreen(),
                    BookmarksScreen(bridge: _bridge, onOpenClient: _openCanisterClient),
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
