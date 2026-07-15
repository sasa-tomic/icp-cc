import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/profile_keypair.dart';
import 'package:icp_autorun/screens/account_profile_screen.dart';

import '../../shared/test_keypair_factory.dart';
import 'account_profile_test_helpers.dart';

/// W7-19 (Fix 3): the public-key and IC-principal copy buttons must be
/// distinguishable for screen-reader users — distinct tooltips/labels instead
/// of two identical "Copy" buttons.
void main() {
  setUpAll(() {
    registerFallbackValue(_FakeProfileKeypair());
  });

  testWidgets('exposes distinct "Copy public key" and "Copy IC principal" '
      'tooltips for the local keypair card', (tester) async {
    final keypair = await TestKeypairFactory.getEd25519Keypair();
    // Local-only (no backend account) so the local key card — whose copy
    // buttons are the subject of this test — renders directly on screen.
    final profile = Profile(
      id: 'profile-1',
      name: 'Test',
      keypairs: [keypair],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final accountController = MockAccountController();
    final profileController = MockProfileController();
    when(() => accountController.refreshAccount(any()))
        .thenAnswer((_) async => null);
    when(() => profileController.findById(any())).thenReturn(profile);

    await tester.pumpWidget(MaterialApp(
      home: AccountProfileScreen(
        account: null,
        accountController: accountController,
        profile: profile,
        profileController: profileController,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Two distinct copy affordances (IconButton tooltip -> Tooltip message).
    expect(find.byTooltip('Copy public key'), findsOneWidget);
    expect(find.byTooltip('Copy IC principal'), findsOneWidget);
    // No generic, indistinguishable "Copy" tooltip remains.
    expect(find.byTooltip('Copy'), findsNothing);
  });
}

class _FakeProfileKeypair extends Fake implements ProfileKeypair {}
