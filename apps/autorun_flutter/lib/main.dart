import 'dart:async';
import 'package:flutter/material.dart';

import 'rust/native_bridge.dart';
import 'screens/favorites_screen.dart';
import 'screens/identity_home_page.dart';
import 'screens/scripts_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IdentityApp());
}

class IdentityApp extends StatelessWidget {
  const IdentityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICP Identity Manager',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light),
        visualDensity: VisualDensity.standard,
        splashFactory: InkSparkle.splashFactory,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          elevation: 1,
          indicatorShape: StadiumBorder(),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          elevation: 2,
          showCloseIcon: true,
        ),
        dialogTheme: DialogTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          showDragHandle: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        cardTheme: const CardTheme(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
        dividerTheme: const DividerThemeData(space: 1),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        visualDensity: VisualDensity.standard,
        splashFactory: InkSparkle.splashFactory,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          elevation: 1,
          indicatorShape: StadiumBorder(),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          elevation: 2,
          showCloseIcon: true,
        ),
        dialogTheme: DialogTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          showDragHandle: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        cardTheme: const CardTheme(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
        dividerTheme: const DividerThemeData(space: 1),
      ),
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
      body: IndexedStack(
        index: _currentIndex,
        children: <Widget>[
          const ScriptsScreen(),
          FavoritesScreen(bridge: _bridge, onOpenClient: _openCanisterClient),
          const IdentityHomePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.code), label: 'Scripts'),
          NavigationDestination(icon: Icon(Icons.favorite), label: 'Favorites'),
          NavigationDestination(icon: Icon(Icons.verified_user), label: 'Identities'),
        ],
        onDestinationSelected: (int index) {
          setState(() => _currentIndex = index);
        },
      ),
    );
  }
}
 
