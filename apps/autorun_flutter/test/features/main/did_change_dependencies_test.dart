import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/profile_controller.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:icp_autorun/widgets/profile_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/fake_secure_keypair_repository.dart';

void main() {
  group('MainHomePage didChangeDependencies', () {
    late ProfileController profileController;
    late FakeProfileRepository fakeRepository;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeRepository = FakeProfileRepository([]);
    });

    tearDown(() {
      profileController.dispose();
    });

    testWidgets('should not call setState during build when loading profiles',
        (tester) async {
      final completer = Completer<void>();

      profileController = ProfileController(
        profileRepository: fakeRepository,
        marketplaceService: MarketplaceOpenApiService(),
      );

      await tester.pumpWidget(
        ProfileScope(
          controller: profileController,
          child: MaterialApp(
            home: _TestWidgetWithDeferredLoad(
              onLoad: () async {
                await profileController.ensureLoaded();
                completer.complete();
              },
            ),
          ),
        ),
      );

      await completer.future;
      await tester.pump();

      expect(find.text('Test Widget'), findsOneWidget);
    });

    testWidgets(
        'ensureLoaded with addPostFrameCallback does not throw during didChangeDependencies',
        (tester) async {
      profileController = ProfileController(
        profileRepository: fakeRepository,
        marketplaceService: MarketplaceOpenApiService(),
      );

      await tester.pumpWidget(
        ProfileScope(
          controller: profileController,
          child: MaterialApp(
            home: _TestWidgetWithDeferredEnsureLoaded(
              profileController: profileController,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Loaded'), findsOneWidget);
    });

    testWidgets('multiple didChangeDependencies calls do not cause issues',
        (tester) async {
      profileController = ProfileController(
        profileRepository: fakeRepository,
        marketplaceService: MarketplaceOpenApiService(),
      );

      await tester.pumpWidget(
        ProfileScope(
          controller: profileController,
          child: MaterialApp(
            home: _TestWidgetWithDeferredEnsureLoaded(
              profileController: profileController,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(
        ProfileScope(
          controller: profileController,
          child: MaterialApp(
            home: _TestWidgetWithDeferredEnsureLoaded(
              profileController: profileController,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Loaded'), findsOneWidget);
    });
  });
}

class _TestWidgetWithDeferredLoad extends StatefulWidget {
  final Future<void> Function() onLoad;

  const _TestWidgetWithDeferredLoad({required this.onLoad});

  @override
  State<_TestWidgetWithDeferredLoad> createState() =>
      _TestWidgetWithDeferredLoadState();
}

class _TestWidgetWithDeferredLoadState
    extends State<_TestWidgetWithDeferredLoad> {
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onLoad();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Test Widget')));
  }
}

class _TestWidgetWithDeferredEnsureLoaded extends StatefulWidget {
  final ProfileController profileController;

  const _TestWidgetWithDeferredEnsureLoaded({
    required this.profileController,
  });

  @override
  State<_TestWidgetWithDeferredEnsureLoaded> createState() =>
      _TestWidgetWithDeferredEnsureLoadedState();
}

class _TestWidgetWithDeferredEnsureLoadedState
    extends State<_TestWidgetWithDeferredEnsureLoaded> {
  bool _loaded = false;
  String _status = 'Loading';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadProfile();
      });
    }
  }

  Future<void> _loadProfile() async {
    await widget.profileController.ensureLoaded();
    if (mounted) {
      setState(() {
        _status = 'Loaded';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(_status)));
  }
}
