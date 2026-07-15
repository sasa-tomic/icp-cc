import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// WU-S1 — Guard against the justfile <-> app_config.dart dart-define key
/// mismatch (NEW-1 in `docs/specs/UX_REVIEW_ROUND2.md`).
///
/// Single source of truth: `apps/autorun_flutter/lib/config/app_config.dart`
/// declares the env-var name(s) the app actually reads at compile time
/// (`String.fromEnvironment('<KEY>', ...)`). The `justfile` run recipe(s)
/// MUST launch Flutter with `--dart-define=<KEY>=...` using the *same* key.
///
/// This test parses both files and asserts they agree, so a future recipe
/// edit cannot silently re-introduce the mismatch that pointed the dev
/// launcher at production.
void main() {
  group('WU-S1 justfile dart-define ↔ app_config.dart', () {
    // `flutter test` runs with `Directory.current` = the Flutter app dir
    // (`apps/autorun_flutter`). The repo root is two levels up.
    final repoRoot = Directory.current.parent.parent.path;
    final justfile = File('$repoRoot/justfile');
    final appConfig = File('$repoRoot/apps/autorun_flutter/lib/config/app_config.dart');

    test('justfile and app_config.dart exist at expected paths', () {
      expect(justfile.existsSync(), isTrue,
          reason: 'justfile not found at ${justfile.path}');
      expect(appConfig.existsSync(), isTrue,
          reason: 'app_config.dart not found at ${appConfig.path}');
    });

    test('app_config.dart exposes its dart-define key as a single source', () {
      // Extract every `String.fromEnvironment('<KEY>', ...)` literal so the
      // canonical key set is itself asserted by symbol, not by hand-typed
      // duplication.
      final source = appConfig.readAsStringSync();
      final envKeyPattern =
          RegExp(r"String\.fromEnvironment\(\s*'([^']+)'\s*(?:,|\))");
      final keys = envKeyPattern
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();

      expect(keys, contains('PUBLIC_API_ENDPOINT'),
          reason: 'app_config.dart must define the API endpoint env key');
    });

    test('every justfile --dart-define uses a key the app reads', () {
      // The canonical key set is every `String.fromEnvironment('KEY')` the
      // *compiled app* actually reads — scanned across all of `lib/`, not just
      // `app_config.dart`, because config defines live in multiple modules
      // (e.g. `IC_AGENT_PROXY_HOST` in the IC-agent web-access module).
      final libDir = Directory('${appConfig.parent.parent.parent.path}/lib');
      final canonical = _readAppEnvKeys(libDir);
      expect(canonical, isNotEmpty,
          reason: 'no String.fromEnvironment keys found under lib/');

      final source = justfile.readAsStringSync();
      final dartDefinePattern = RegExp(r'--dart-define=([A-Za-z_][A-Za-z0-9_]*)=');
      final definedKeys = dartDefinePattern
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();

      expect(definedKeys, isNotEmpty,
          reason: 'no --dart-define=KEY=... found in justfile — nothing to test');

      final unknown = definedKeys.difference(canonical);
      expect(
        unknown,
        isEmpty,
        reason:
            'justfile defines keys the app never reads: $unknown. '
            'The app reads: $canonical. '
            'This is the NEW-1 bug class: the app silently ignores the '
            'misnamed define and falls back to its baked-in default.',
      );
    });

    test('flutter-dev-local recipe points the app at the local API', () {
      // The specific failure mode NEW-1 reported: `flutter-dev-local` used a
      // mismatched key, silently routing to production. Pin the recipe name +
      // the correct key so a regression here cannot slip past code review.
      final libDir = Directory('${appConfig.parent.parent.parent.path}/lib');
      final canonical = _readAppEnvKeys(libDir);
      final source = justfile.readAsStringSync();
      final recipeBlock = _extractRecipeBlock(source, 'flutter-dev-local');

      expect(recipeBlock, isNotNull,
          reason: 'flutter-dev-local recipe not found in justfile');
      expect(
        recipeBlock,
        contains('--dart-define=PUBLIC_API_ENDPOINT=http://127.0.0.1:'),
        reason: 'flutter-dev-local must --dart-define the canonical key '
            '(${canonical.join(', ')}) to localhost. '
            'See docs/specs/UX_REVIEW_ROUND2.md NEW-1.',
      );
    });
  });
}

/// Extracts every `String.fromEnvironment('<KEY>', ...)` key across all Dart
/// files under `lib/` — the single source of truth for what env vars the
/// compiled app actually consumes at compile time. (Scanning the whole tree,
/// not just `app_config.dart`, keeps this honest as config defines spread
/// across modules — e.g. `IC_AGENT_PROXY_HOST` in the web-access module.)
Set<String> _readAppEnvKeys(Directory libDir) {
  final pattern = RegExp(r"String\.fromEnvironment\(\s*'([^']+)'\s*(?:,|\))");
  final keys = <String>{};
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    for (final match in pattern.allMatches(source)) {
      keys.add(match.group(1)!);
    }
  }
  return keys;
}

/// Returns the body (recipe name line through the next blank-line / next
/// `^name:`) of a single justfile recipe, or null if not present.
String? _extractRecipeBlock(String justfile, String recipeName) {
  final lines = justfile.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final recipeStart = RegExp('^$recipeName(\\b|\\s|:)');
    if (!recipeStart.hasMatch(line)) continue;
    // Found the recipe; collect it and its indented body.
    final buf = <String>[line];
    for (var j = i + 1; j < lines.length; j++) {
      final body = lines[j];
      // Recipe body lines are indented (or shebang / continuation). Stop at
      // the next unindented non-blank line (next recipe or assignment).
      if (body.trim().isEmpty) {
        buf.add(body);
        continue;
      }
      final isBody = body.startsWith(' ') ||
          body.startsWith('\t') ||
          body.startsWith('#!');
      if (!isBody) break;
      buf.add(body);
    }
    return buf.join('\n');
  }
  return null;
}
