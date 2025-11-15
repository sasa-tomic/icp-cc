import 'dart:async';
import 'package:flutter/material.dart';

import 'rust/native_bridge.dart';
import 'config/app_config.dart';
import 'theme/app_design_system.dart';
import 'theme/modern_components.dart';
import 'screens/favorites_screen.dart';
import 'screens/identity_home_page.dart';
import 'screens/scripts_screen.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.debugPrintConfig();
  runApp(const IdentityApp());
}

class IdentityApp extends StatelessWidget {
  const IdentityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICP Autorun',
      theme: AppDesignSystem.lightTheme,
      darkTheme: AppDesignSystem.darkTheme,
      themeMode: ThemeMode.system,
      home: const MainHomePage(),
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
      extendBody: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
              Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
            ],
          ),
        ),
        child: IndexedStack(
          index: _currentIndex,
          children: <Widget>[
            const ScriptsScreen(),
            FavoritesScreen(bridge: _bridge, onOpenClient: _openCanisterClient),
            const IdentityHomePage(),
          ],
        ),
      ),
      bottomNavigationBar: _buildModernNavigationBar(),
    );
  }

  Widget _buildModernNavigationBar() {
    return ModernNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() => _currentIndex = index);
      },
      items: const [
        ModernNavigationItem(
          icon: Icons.code_rounded,
          activeIcon: Icons.code_rounded,
          label: 'Scripts',
        ),
        ModernNavigationItem(
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          label: 'Favorites',
        ),
        ModernNavigationItem(
          icon: Icons.verified_user_outlined,
          activeIcon: Icons.verified_user_rounded,
          label: 'Identities',
        ),
      ],
    );
  }
}
 
