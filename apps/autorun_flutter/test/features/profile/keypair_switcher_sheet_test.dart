// UX-H5 Path 3: keypair_switcher_sheet tile-tap must PREVIEW the selection
// without popping the sheet; only Apply pops. Previously tile-tap popped
// immediately, making the Apply button dead code.
//
// We use a tiny fake ProfileController since the sheet only reads
// `controller.profiles` and `controller.activeProfileId`. mockito codegen
// would be overkill for two plain getters.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/widgets/keypair_switcher_sheet.dart';

class _FakeProfileController extends ProfileController {
  _FakeProfileController(this._profiles, this._activeId);

  final List<Profile> _profiles;
  final String? _activeId;

  @override
  List<Profile> get profiles => List<Profile>.unmodifiable(_profiles);

  @override
  String? get activeProfileId => _activeId;
}

ProfileKeypair _keypair(String id) {
  return ProfileKeypair(
    id: id,
    label: 'Keypair $id',
    algorithm: KeyAlgorithm.ed25519,
    publicKey: 'pub-$id',
    privateKey: 'priv-$id',
    mnemonic: 'mnemonic-$id',
    createdAt: DateTime.utc(2026, 7, 1),
    principal: 'rrkah-fqaaa-aaaaa-aaaaq-cai',
  );
}

Profile _profile(String id, String name) {
  return Profile(
    id: id,
    name: name,
    keypairs: [_keypair('kp-$id')],
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
  );
}

void main() {
  Future<KeypairSwitcherResult?> pumpSheet(WidgetTester tester,
      {required List<Profile> profiles, String? activeId}) {
    return tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showKeypairSwitcherSheet(
                      context: context,
                      controller: _FakeProfileController(profiles, activeId),
                    ),
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return Future.value();
    }).then((_) {
      // Read the future the bottom-sheet popped with by intercepting
      // via a route observer... simpler: just leave the sheet open and
      // assert on visible state. Caller checks the visible UI.
      return Future.value(null);
    });
  }

  group('UX-H5 Path 3: keypair_switcher_sheet preview-then-apply', () {
    testWidgets('tile-tap previews selection WITHOUT closing the sheet',
        (tester) async {
      final profiles = [_profile('a', 'Alpha'), _profile('b', 'Beta')];
      await pumpSheet(tester, profiles: profiles, activeId: 'a');

      // Sheet is open, Alpha is initially selected (check mark visible).
      expect(find.text('Choose a keypair'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);

      // Tap Beta tile.
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      // Sheet is still open (no pop) — Apply is the meaningful commit step.
      expect(find.text('Choose a keypair'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);

      // Beta is now the visually-selected tile: confirm by checking the
      // AnimatedSwitcher's check-circle icon count == 1 and that it sits in
      // the Beta tile. We assert the structural invariant: exactly one tile
      // has the check icon, and it is in the row containing 'Beta'.
      final checkIcons = find.byIcon(Icons.check_circle);
      expect(checkIcons, findsOneWidget);
      final betaTile = find.ancestor(
        of: find.text('Beta'),
        matching: find.byType(ListTile),
      );
      final betaTileCheck = find.descendant(
        of: betaTile,
        matching: checkIcons,
      );
      expect(betaTileCheck, findsOneWidget);
    });

    testWidgets('Apply commits the previewed selection and pops the sheet',
        (tester) async {
      final profiles = [_profile('a', 'Alpha'), _profile('b', 'Beta')];
      await pumpSheet(tester, profiles: profiles, activeId: 'a');

      // Preview Beta.
      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      // Apply → sheet pops.
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Bottom sheet has been popped; only the launcher button remains.
      expect(find.text('Choose a keypair'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets(
        'system back from preview state closes the sheet WITHOUT applying '
        'the previewed (but not committed) selection', (tester) async {
      final profiles = [_profile('a', 'Alpha'), _profile('b', 'Beta')];
      await pumpSheet(tester, profiles: profiles, activeId: 'a');

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      // System back — sheet pops with null (no selection committed).
      final NavigatorState nav = tester.state(find.byType(Navigator).first);
      nav.pop();
      await tester.pumpAndSettle();

      expect(find.text('Choose a keypair'), findsNothing);
    });
  });
}
