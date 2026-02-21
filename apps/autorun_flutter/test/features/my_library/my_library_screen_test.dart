import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/screens/my_library_screen.dart';
import 'package:icp_autorun/services/download_history_service.dart';
import 'package:icp_autorun/services/favorites_service.dart';
import 'package:icp_autorun/services/script_repository.dart';
import 'package:icp_autorun/models/script_record.dart';

class _FakeScriptRepository implements ScriptRepository {
  final List<ScriptRecord> _scripts;
  final StreamController<List<ScriptRecord>> _controller =
      StreamController<List<ScriptRecord>>.broadcast();

  _FakeScriptRepository(this._scripts);

  @override
  Stream<List<ScriptRecord>> get scriptsStream => _controller.stream;

  @override
  Future<List<ScriptRecord>> loadScripts() async => List.from(_scripts);

  @override
  Future<void> persistScripts(List<ScriptRecord> scripts) async {
    _scripts.clear();
    _scripts.addAll(scripts);
    _controller.add(List.unmodifiable(scripts));
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  group('MyLibraryScreen', () {
    late DownloadHistoryService downloadHistoryService;
    late FavoritesService favoritesService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      downloadHistoryService = DownloadHistoryService();
      favoritesService = FavoritesService();
      await favoritesService.clearFavorites();
      await downloadHistoryService.clearHistory();
    });

    Widget wrapWithMaterial(Widget child) {
      return MaterialApp(home: child);
    }

    Future<void> pumpScreen(
      WidgetTester tester, {
      ScriptRepository? scriptRepository,
    }) async {
      await tester.pumpWidget(wrapWithMaterial(
        MyLibraryScreen(
          downloadHistoryService: downloadHistoryService,
          favoritesService: favoritesService,
          scriptRepository: scriptRepository ?? _FakeScriptRepository([]),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    group('displays content sections', () {
      testWidgets('shows Downloads section', (tester) async {
        await pumpScreen(tester);
        expect(find.text('Downloads'), findsOneWidget);
      });

      testWidgets('shows Favorites section', (tester) async {
        await pumpScreen(tester);
        expect(find.text('Favorites'), findsOneWidget);
      });

      testWidgets('shows My Scripts section', (tester) async {
        await pumpScreen(tester);
        expect(find.text('My Scripts'), findsOneWidget);
      });

      testWidgets('shows Recent Activity section', (tester) async {
        await pumpScreen(tester);
        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pump();
        expect(find.text('Recent Activity'), findsOneWidget);
      });
    });

    group('displays downloaded scripts', () {
      testWidgets('shows downloaded script in Downloads section',
          (tester) async {
        await downloadHistoryService.addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Test Script',
          authorName: 'Test Author',
          version: '1.0.0',
          localScriptId: 'local-1',
        );

        await pumpScreen(tester);
        expect(find.text('Test Script'), findsOneWidget);
        expect(find.text('by Test Author'), findsOneWidget);
      });

      testWidgets('shows empty state when no downloads', (tester) async {
        await pumpScreen(tester);
        expect(find.text('No downloads yet'), findsOneWidget);
      });

      testWidgets('shows download count in section header', (tester) async {
        await downloadHistoryService.addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Script One',
          authorName: 'Author',
          localScriptId: 'local-1',
        );
        await downloadHistoryService.addToHistory(
          marketplaceScriptId: 'script-2',
          title: 'Script Two',
          authorName: 'Author',
          localScriptId: 'local-2',
        );

        await pumpScreen(tester);
        expect(find.text('Downloads (2)'), findsOneWidget);
      });
    });

    group('displays favorite scripts', () {
      testWidgets('shows favorite count in section header', (tester) async {
        await favoritesService.toggleFavorite('script-1');
        await favoritesService.toggleFavorite('script-2');

        await pumpScreen(tester);
        expect(find.text('Favorites (2)'), findsOneWidget);
      });

      testWidgets('shows empty state when no favorites', (tester) async {
        await pumpScreen(tester);
        expect(find.text('No favorites yet'), findsOneWidget);
      });
    });

    group('displays local scripts', () {
      testWidgets('shows empty state when no local scripts', (tester) async {
        await pumpScreen(tester);
        expect(find.text('No scripts created'), findsOneWidget);
      });

      testWidgets('shows local script when present', (tester) async {
        final scripts = [
          ScriptRecord(
            id: 'local-1',
            title: 'My Local Script',
            luaSource: 'print("hello")',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        await pumpScreen(tester,
            scriptRepository: _FakeScriptRepository(scripts));
        expect(find.text('My Local Script'), findsOneWidget);
      });

      testWidgets('shows local script count in header', (tester) async {
        final scripts = [
          ScriptRecord(
            id: 'local-1',
            title: 'Script 1',
            luaSource: 'print("1")',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          ScriptRecord(
            id: 'local-2',
            title: 'Script 2',
            luaSource: 'print("2")',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        await pumpScreen(tester,
            scriptRepository: _FakeScriptRepository(scripts));
        expect(find.text('My Scripts (2)'), findsOneWidget);
      });
    });

    group('navigation', () {
      testWidgets('has AppBar with My Library title', (tester) async {
        await pumpScreen(tester);
        expect(find.text('My Library'), findsOneWidget);
      });
    });

    group('pull to refresh', () {
      testWidgets('has RefreshIndicator', (tester) async {
        await pumpScreen(tester);
        expect(find.byType(RefreshIndicator), findsOneWidget);
      });
    });

    group('section cards', () {
      testWidgets('each section is expandable', (tester) async {
        await pumpScreen(tester);
        final expansionTiles = find.byType(ExpansionTile);
        expect(expansionTiles, findsWidgets);
      });

      testWidgets('sections are expanded by default', (tester) async {
        await downloadHistoryService.addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Test Script',
          authorName: 'Author',
          localScriptId: 'local-1',
        );

        await pumpScreen(tester);
        expect(find.text('Test Script'), findsOneWidget);
      });
    });

    group('recent activity', () {
      testWidgets('shows empty state when no activity', (tester) async {
        await pumpScreen(tester);
        await tester.drag(find.byType(ListView), const Offset(0, -800));
        await tester.pump();
        expect(find.text('No recent activity'), findsOneWidget);
      });

      testWidgets('shows download as recent activity', (tester) async {
        await downloadHistoryService.addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Recent Script',
          authorName: 'Author',
          localScriptId: 'local-1',
        );

        await pumpScreen(tester);
        expect(find.text('Recent Script'), findsWidgets);
      });

      testWidgets('shows script execution as activity', (tester) async {
        final scripts = [
          ScriptRecord(
            id: 'local-1',
            title: 'Executed Script',
            luaSource: 'print("hello")',
            createdAt: DateTime.now().subtract(const Duration(days: 1)),
            updatedAt: DateTime.now(),
            lastRunAt: DateTime.now(),
            runCount: 5,
          ),
        ];

        await pumpScreen(tester,
            scriptRepository: _FakeScriptRepository(scripts));
        expect(find.text('Executed Script'), findsWidgets);
      });
    });
  });
}
