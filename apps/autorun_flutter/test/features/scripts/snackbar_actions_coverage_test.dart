import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/profile.dart';
import 'package:icp_autorun/models/script_template.dart';
import 'package:icp_autorun/screens/account_registration_prompt_dialog.dart';
import 'package:icp_autorun/screens/script_creation_screen.dart';
import 'package:icp_autorun/screens/scripts_screen.dart';
import 'package:icp_autorun/widgets/connectivity_scope.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';
import 'package:icp_autorun/widgets/quick_upload_dialog.dart';
import 'package:icp_autorun/widgets/script_execution_bottom_sheet.dart';
import 'package:icp_autorun/widgets/script_row_menus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/fake_connectivity_service.dart';
import '../../shared/fake_secure_keypair_repository.dart';
import '../../shared/mock_script_repository.dart';
import '../../shared/test_keypair_factory.dart';
import 'fake_marketplace_open_api.dart';

const String _tsBundle = '"use strict";\n'
    '(() => {\n'
    '  function init() { return { state: { n: 0 }, effects: [] }; }\n'
    '  function view(s) { return { type: "text", props: { text: "n=" + (s.n || 0) } }; }\n'
    '  function update(_m, s) { return { state: s, effects: [] }; }\n'
    '  globalThis.init = init;\n'
    '  globalThis.view = view;\n'
    '  globalThis.update = update;\n'
    '})();\n';

MarketplaceScript _freePublicScript() => MarketplaceScript(
      id: 'mk-downloader',
      title: 'Downloader',
      description: 'A script for testing the download then run snackbar.',
      category: 'Utilities',
      authorName: 'Tester',
      price: 0.0,
      bundle: _tsBundle,
      version: '1.0.0',
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
    );

Future<ProfileController> _profileControllerWith({String? username}) async {
  final keypair = await TestKeypairFactory.getEd25519Keypair();
  final profile = Profile(
    id: 'p1',
    name: 'Alice',
    keypairs: [keypair],
    username: username,
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 1),
  );
  final controller = ProfileController(profileRepository: FakeProfileRepository([profile]));
  await controller.ensureLoaded();
  await controller.setActiveProfile('p1');
  return controller;
}

Future<void> _driveCreateToPublishSnackbar(
  WidgetTester tester, {
  required ProfileController profileController,
}) async {
  await tester.pumpWidget(
    ProfileScope(
      controller: profileController,
      child: MaterialApp(
        home: ConnectivityScope(
          service: FakeConnectivityService(),
          child: ScriptsScreen(
            controller: ScriptController(MockScriptRepository()),
            marketplaceService: FakeMarketplaceOpenApi(scripts: [_freePublicScript()]),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));

  tester.state<ScriptsScreenState>(find.byType(ScriptsScreen)).createNewScript();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));

  await tester.tap(find.descendant(
    of: find.byType(ScriptCreationScreen),
    matching: find.text('Create Script'),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));

  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.text('Publish'), findsOneWidget);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ScriptTemplates.resetForTest();
    await ScriptTemplates.ensureInitialized();
  });

  testWidgets(
      'WU-2: Run snackbar action opens the execution sheet for the downloaded script',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakeMarketplaceOpenApi(scripts: [_freePublicScript()]);

    await tester.pumpWidget(
      MaterialApp(
        home: ConnectivityScope(
          service: FakeConnectivityService(),
          child: ScriptsScreen(
            controller: ScriptController(MockScriptRepository()),
            marketplaceService: fake,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final overflow = find.descendant(
      of: find.byType(MarketplaceScriptRowMenu),
      matching: find.byIcon(Icons.more_vert),
    );
    expect(overflow, findsOneWidget);
    await tester.tap(overflow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(fake.downloadCalls, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);

    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ScriptExecutionBottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ScriptExecutionBottomSheet),
        matching: find.text('Downloader (Marketplace)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'WU-3: Publish snackbar action opens QuickUploadDialog when an account is registered',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profileController = await _profileControllerWith(username: 'alice');

    await _driveCreateToPublishSnackbar(tester, profileController: profileController);

    await tester.tap(find.text("Publish"));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(QuickUploadDialog), findsOneWidget);
  });

  testWidgets(
      'WU-3: Publish snackbar action opens the registration prompt when no account is registered',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profileController = await _profileControllerWith(username: null);

    await _driveCreateToPublishSnackbar(tester, profileController: profileController);

    await tester.tap(find.text("Publish"));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(AccountRegistrationPromptDialog), findsOneWidget);
  });
}
