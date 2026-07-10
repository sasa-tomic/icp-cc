import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/download_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// A SharedPreferences store whose writes always fail, to prove that
/// `DownloadHistoryService` surfaces save errors instead of swallowing them.
///
/// Reads (`getAll`) keep working (backed by the in-memory map inherited from
/// [InMemorySharedPreferencesStore]); only persistence (`setValue`) throws —
/// isolating the `_saveHistory` failure path. (QS-10)
class _FailingWriteSharedPreferencesStore extends InMemorySharedPreferencesStore {
  _FailingWriteSharedPreferencesStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    throw StateError('simulated disk write failure');
  }
}

/// QS-10: `_saveHistory` previously swallowed write errors silently
/// (`/* Silently fail for now */`), so a persistence failure would drop the
/// user's download history with NO indication. These tests pin the new
/// behaviour — every mutating method rethrows when persistence fails, so
/// callers can surface a SnackBar.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // The service caches history in-memory on a singleton; clear it so each
    // test starts from a clean slate.
    await DownloadHistoryService().clearHistory();
  });

  tearDown(() async {
    // Restore a working store + reset the in-memory cache for other suites.
    SharedPreferences.setMockInitialValues({});
    await DownloadHistoryService().clearHistory();
  });

  group('QS-10: save failures are surfaced, not swallowed', () {
    test('addToHistory throws when persistence fails', () async {
      // Swap in a store whose writes always fail.
      SharedPreferencesStorePlatform.instance =
          _FailingWriteSharedPreferencesStore();

      // The mutation must propagate the save error instead of swallowing it.
      await expectLater(
        DownloadHistoryService().addToHistory(
          marketplaceScriptId: 'script-1',
          title: 'Test Script',
          authorName: 'Test Author',
          version: '1.0.0',
          localScriptId: 'local-1',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to save download history'),
          ),
        ),
      );
    });

    test('removeFromHistory throws when persistence fails', () async {
      // Seed history with a working store first.
      await DownloadHistoryService().addToHistory(
        marketplaceScriptId: 'script-1',
        title: 'Test Script',
        authorName: 'Test Author',
        localScriptId: 'local-1',
      );

      // Swap in a failing store for the mutating remove.
      SharedPreferencesStorePlatform.instance =
          _FailingWriteSharedPreferencesStore();

      await expectLater(
        DownloadHistoryService().removeFromHistory('script-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('clearHistory throws when persistence fails', () async {
      // Swap in a store whose writes always fail.
      SharedPreferencesStorePlatform.instance =
          _FailingWriteSharedPreferencesStore();

      await expectLater(
        DownloadHistoryService().clearHistory(),
        throwsA(isA<Exception>()),
      );
    });
  });
}
