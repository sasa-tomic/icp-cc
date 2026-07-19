// ignore_for_file: lines_longer_than_80_chars

/// `path_provider` substrate for the Web e2e harness.
///
/// The conditional export in `lib/services/json_store.dart` picks the IO
/// branch (`file_json_store.dart`) under `flutter test -d chrome` because the
/// test code compiles for the Dart VM (chrome is just the renderer), so
/// `dart.library.html` is false. This means `FileJsonStore` is selected
/// even on the chrome target, and it (plus `flutter_cache_manager` for image
/// caching) calls `getApplicationSupportDirectory()` / `getTemporaryDirectory()`
/// via the `path_provider` plugin's platform channel — which throws
/// `MissingPluginException` because no platform impl is registered.
///
/// `FileJsonStore` itself already has a fallback that catches that exception
/// and uses a temp dir, so the JSON store works. But two issues remain:
/// 1. `flutter_cache_manager` (used by `cached_network_image`) propagates the
///    exception as an unhandled test failure even when later caught — the
///    "MissingPluginException thrown running a test" framework error.
/// 2. `getTemporaryDirectory` (also `flutter_cache_manager`) hits the same
///    missing-plugin issue.
///
/// Fix: install a fake [PathProviderPlatform] that returns a stable temp dir
/// for every method. The same dir is reused across calls so caches and stores
/// agree on a single location.
library;

import 'dart:io' show Directory;

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Fake [PathProviderPlatform] that backs every method with a stable temp dir
/// created lazily on first use. One dir per [FakePathProvider] instance — pass
/// the same instance to [PathProviderPlatform.instance] for the whole suite.
class FakePathProvider extends PathProviderPlatform {
  FakePathProvider() : super();

  Directory? _root;

  Future<Directory> _rootDir() async {
    final cached = _root;
    if (cached != null) return cached;
    final dir =
        await Directory.systemTemp.createTemp('icp_autorun_substrate_');
    _root = dir;
    return dir;
  }

  @override
  Future<String?> getTemporaryPath() async => (await _rootDir()).path;

  @override
  Future<String?> getApplicationSupportPath() async => (await _rootDir()).path;

  @override
  Future<String?> getLibraryPath() async => (await _rootDir()).path;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      (await _rootDir()).path;

  @override
  Future<String?> getApplicationCachePath() async => (await _rootDir()).path;

  @override
  Future<String?> getExternalStoragePath() async => (await _rootDir()).path;

  @override
  Future<List<String>?> getExternalCachePaths() async =>
      <String>[(await _rootDir()).path];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      <String>[(await _rootDir()).path];

  @override
  Future<String?> getDownloadsPath() async => (await _rootDir()).path;
}

/// Install the fake [PathProviderPlatform]. Idempotent; safe to call from
/// `setUpAll` / `setUp`. Returns the temp [Directory] used so callers can
/// tear it down on suite end (optional — the OS reaps `/tmp`).
Directory? installSubstratePathProvider() {
  // Idempotent: a prior call may have installed a fake already. Replace it
  // with a fresh one so each suite gets an isolated dir.
  final fake = FakePathProvider();
  PathProviderPlatform.instance = fake;
  return fake._root;
}
