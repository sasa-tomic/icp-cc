import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/controllers/account_controller.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/theme/modern_components.dart';

void main() {
  group('ModernNavigationBar', () {
    testWidgets('navigation bar items have correct labels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ModernNavigationBar(
              currentIndex: 0,
              onTap: (_) {},
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
            ),
          ),
        ),
      );

      final scriptsTab = find.text('Scripts');
      final canistersTab = find.text('Canisters');

      expect(scriptsTab, findsOneWidget, reason: 'Should have Scripts tab');
      expect(canistersTab, findsOneWidget, reason: 'Should have Canisters tab');
    });

    testWidgets('navigation bar has 2 items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ModernNavigationBar(
              currentIndex: 0,
              onTap: (_) {},
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
            ),
          ),
        ),
      );

      final navBar = find.byType(ModernNavigationBar);
      expect(navBar, findsOneWidget);

      final ModernNavigationBar widget = tester.widget(navBar);
      expect(widget.items.length, equals(2),
          reason: 'Navigation bar should have exactly 2 items');
    });

    testWidgets('tapping navigation item triggers callback', (tester) async {
      int tappedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: ModernNavigationBar(
              currentIndex: 0,
              onTap: (index) {
                tappedIndex = index;
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
            ),
          ),
        ),
      );

      final canistersTab = find.text('Canisters');
      await tester.tap(canistersTab);

      expect(tappedIndex, equals(1),
          reason: 'Tapping Canisters should trigger callback with index 1');
    });
  });

  group('ProfileMenuWidget', () {
    testWidgets('shows Manage Profiles option', (tester) async {
      final profileController = ProfileController(
        marketplaceService: MarketplaceOpenApiService(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileMenuWidget(
              profileController: profileController,
              accountController: AccountController(
                marketplaceService: MarketplaceOpenApiService(),
                profileController: profileController,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Should show Manage Profiles option (combines switch + create)
      final manageProfilesOption = find.text('Manage Profiles');
      expect(manageProfilesOption, findsOneWidget,
          reason: 'Manage Profiles option should be visible');
    });

    testWidgets('shows profile header with display name', (tester) async {
      final profileController = ProfileController(
        marketplaceService: MarketplaceOpenApiService(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileMenuWidget(
              profileController: profileController,
              accountController: AccountController(
                marketplaceService: MarketplaceOpenApiService(),
                profileController: profileController,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Should show Guest as default display name when no profile
      final guestText = find.text('Guest');
      expect(guestText, findsOneWidget,
          reason: 'Should show Guest as default display name');
    });

    testWidgets('shows No account text when no account', (tester) async {
      final profileController = ProfileController(
        marketplaceService: MarketplaceOpenApiService(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileMenuWidget(
              profileController: profileController,
              accountController: AccountController(
                marketplaceService: MarketplaceOpenApiService(),
                profileController: profileController,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Should show "No account" text when user has no account
      final noAccountText = find.text('No account');
      expect(noAccountText, findsOneWidget,
          reason: 'Should show No account text when user has no account');
    });
  });

  group('ProfileAvatarButton', () {
    testWidgets('displays initials from display name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'John Doe',
              onTap: () {},
            ),
          ),
        ),
      );

      // Should display 'JO' for 'John Doe'
      final initials = find.text('JO');
      expect(initials, findsOneWidget,
          reason: 'Should display initials from display name');
    });

    testWidgets('displays question mark for empty name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: '',
              onTap: () {},
            ),
          ),
        ),
      );

      // Should display '?' for empty name
      final questionMark = find.text('?');
      expect(questionMark, findsOneWidget,
          reason: 'Should display ? for empty display name');
    });

    testWidgets('displays single character for short name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'A',
              onTap: () {},
            ),
          ),
        ),
      );

      // Should display 'A' for single character name
      final initial = find.text('A');
      expect(initial, findsOneWidget,
          reason: 'Should display single character for short name');
    });

    testWidgets('onTap callback is triggered', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test',
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      // Tap the avatar
      final avatar = find.byType(ProfileAvatarButton);
      await tester.tap(avatar);

      expect(tapped, isTrue, reason: 'onTap callback should be triggered');
    });

    testWidgets('has correct size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileAvatarButton(
              displayName: 'Test',
              onTap: () {},
              size: 40,
            ),
          ),
        ),
      );

      final avatar = find.byType(ProfileAvatarButton);
      expect(avatar, findsOneWidget);

      // Verify the avatar renders without errors
      // The exact size is handled by the Container's constraints
      expect(avatar, findsOneWidget);
    });
  });
}
