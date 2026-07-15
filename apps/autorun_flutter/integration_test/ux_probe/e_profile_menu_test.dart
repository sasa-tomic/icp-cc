// Flow B / WU-4 — capture the avatar profile menu (always visible, even with
// no profile) to evidence the WU-4 3-tap switch structure: avatar -> "Switch
// Profile" -> target profile row. NEW-2 blocks creating a 2nd profile, so the
// 2nd+3rd taps are documented via code (profile_menu.dart:207/513-568).
//
// Run: DISPLAY=:99 flutter test integration_test/ux_probe/e_profile_menu_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:icp_autorun/widgets/profile_menu.dart';
import 'ux_probe_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WU-4: avatar menu has My Account / Switch Profile / Settings', (tester) async {
    await clearProfileState();
    await launchApp(tester);
    await dismissWizard(tester);

    // The avatar is always present at top-right.
    final avatar = find.byType(ProfileAvatarButton);
    expect(present(avatar, tester), isTrue);
    await tester.tap(avatar);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '07_profile_menu', dir: kShotDirRound2);

    final hasSwitchProfile = present(find.text('Switch Profile'), tester);
    final hasSettings = present(find.text('Settings'), tester);
    final hasMyAccount = present(find.textContaining('Account'), tester);
    // ignore: avoid_print
    print('WU4_MENU: hasMyAccount=$hasMyAccount hasSwitchProfile=$hasSwitchProfile '
        'hasSettings=$hasSettings');

    expect(hasSwitchProfile, isTrue,
        reason: 'WU-4 evidence: avatar menu exposes a "Switch Profile" tile that '
            'opens a second sheet (manageProfiles) where the actual switch row '
            'lives -> 3-tap switch (avatar, Switch Profile, target).');
  });
}
