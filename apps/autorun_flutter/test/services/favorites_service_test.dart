import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icp_autorun/services/favorites_service.dart';

void main() {
  group('FavoritesService', () {
    late FavoritesService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = FavoritesService();
    });

    tearDown(() async {
      await service.clearFavorites();
    });

    group('toggleFavorite', () {
      test('should add script to favorites when not already favorited',
          () async {
        const scriptId = 'script-123';

        final isNowFavorite = await service.toggleFavorite(scriptId);

        expect(isNowFavorite, isTrue);
        expect(await service.isFavorite(scriptId), isTrue);
      });

      test('should remove script from favorites when already favorited',
          () async {
        const scriptId = 'script-123';

        await service.toggleFavorite(scriptId);
        final isNowFavorite = await service.toggleFavorite(scriptId);

        expect(isNowFavorite, isFalse);
        expect(await service.isFavorite(scriptId), isFalse);
      });

      test('should handle multiple scripts independently', () async {
        await service.toggleFavorite('script-1');
        await service.toggleFavorite('script-2');
        await service.toggleFavorite('script-3');

        // Remove one
        await service.toggleFavorite('script-2');

        expect(await service.isFavorite('script-1'), isTrue);
        expect(await service.isFavorite('script-2'), isFalse);
        expect(await service.isFavorite('script-3'), isTrue);
      });

      test('should handle rapid toggling', () async {
        const scriptId = 'rapid-script';

        await service.toggleFavorite(scriptId); // on
        await service.toggleFavorite(scriptId); // off
        await service.toggleFavorite(scriptId); // on
        await service.toggleFavorite(scriptId); // off
        final result = await service.toggleFavorite(scriptId); // on

        expect(result, isTrue);
        expect(await service.isFavorite(scriptId), isTrue);
      });

      test('should return the current favorite state after toggle', () async {
        const scriptId = 'script-xyz';

        // First toggle should return true (now favorited)
        expect(await service.toggleFavorite(scriptId), isTrue);

        // Second toggle should return false (no longer favorited)
        expect(await service.toggleFavorite(scriptId), isFalse);

        // Third toggle should return true again
        expect(await service.toggleFavorite(scriptId), isTrue);
      });
    });

    group('isFavorite', () {
      test('should return false for non-favorited script', () async {
        expect(await service.isFavorite('non-existent-id'), isFalse);
      });

      test('should return true for favorited script', () async {
        await service.toggleFavorite('test-id');

        expect(await service.isFavorite('test-id'), isTrue);
      });

      test('should handle empty script id', () async {
        expect(await service.isFavorite(''), isFalse);

        await service.toggleFavorite('');
        expect(await service.isFavorite(''), isTrue);
      });

      test('should be case-sensitive', () async {
        await service.toggleFavorite('Script-Id');

        expect(await service.isFavorite('Script-Id'), isTrue);
        expect(await service.isFavorite('script-id'), isFalse);
      });
    });

    group('getAllFavorites', () {
      test('should return empty set when no favorites', () async {
        final favorites = await service.getAllFavorites();

        expect(favorites, isEmpty);
      });

      test('should return all favorited scripts', () async {
        await service.toggleFavorite('script-1');
        await service.toggleFavorite('script-2');
        await service.toggleFavorite('script-3');

        final favorites = await service.getAllFavorites();

        expect(favorites.length, 3);
        expect(favorites, containsAll(['script-1', 'script-2', 'script-3']));
      });

      test('should return unmodifiable set', () async {
        await service.toggleFavorite('script-1');

        final favorites = await service.getAllFavorites();

        expect(() => favorites.add('new-script'), throwsUnsupportedError);
      });

      test('should not include removed favorites', () async {
        await service.toggleFavorite('script-1');
        await service.toggleFavorite('script-2');
        await service.toggleFavorite('script-3');

        await service.toggleFavorite('script-2'); // Remove

        final favorites = await service.getAllFavorites();

        expect(favorites.length, 2);
        expect(favorites, containsAll(['script-1', 'script-3']));
        expect(favorites, isNot(contains('script-2')));
      });
    });

    group('clearFavorites', () {
      test('should clear all favorites', () async {
        await service.toggleFavorite('script-1');
        await service.toggleFavorite('script-2');
        await service.toggleFavorite('script-3');

        await service.clearFavorites();

        expect(await service.getAllFavorites(), isEmpty);
      });

      test('should handle clearing empty favorites', () async {
        await service.clearFavorites();

        expect(await service.getAllFavorites(), isEmpty);
      });

      test('should emit empty set via stream after clearing', () async {
        await service.toggleFavorite('script-1');

        final stream = service.favoritesStream;
        final emittedValues = <Set<String>>[];
        final subscription = stream.listen(emittedValues.add);

        await service.clearFavorites();
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        expect(emittedValues.last, isEmpty);
      });
    });

    group('favoritesStream', () {
      test('should emit updates when favorite is added', () async {
        final emittedValues = <Set<String>>[];
        final subscription = service.favoritesStream.listen(emittedValues.add);

        await service.toggleFavorite('stream-script-1');
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        expect(emittedValues.length, greaterThanOrEqualTo(1));
        expect(emittedValues.last, contains('stream-script-1'));
      });

      test('should emit updates when favorite is removed', () async {
        await service.toggleFavorite('stream-script-1');

        final emittedValues = <Set<String>>[];
        final subscription = service.favoritesStream.listen(emittedValues.add);

        await service.toggleFavorite('stream-script-1'); // Remove
        await Future.delayed(const Duration(milliseconds: 50));

        await subscription.cancel();

        expect(emittedValues.last, isNot(contains('stream-script-1')));
      });

      test('should be a broadcast stream', () async {
        final stream = service.favoritesStream;

        // Should be able to listen multiple times
        final sub1 = stream.listen((_) {});
        final sub2 = stream.listen((_) {});

        await sub1.cancel();
        await sub2.cancel();
      });
    });

    group('persistence', () {
      test('should persist data across service instances', () async {
        await service.toggleFavorite('persistent-script-1');
        await service.toggleFavorite('persistent-script-2');

        // Create new service instance (same singleton)
        final newService = FavoritesService();

        expect(await newService.isFavorite('persistent-script-1'), isTrue);
        expect(await newService.isFavorite('persistent-script-2'), isTrue);
      });

      test('should persist removals', () async {
        await service.toggleFavorite('script-1');
        await service.toggleFavorite('script-2');

        await service.toggleFavorite('script-1'); // Remove

        final newService = FavoritesService();
        expect(await newService.isFavorite('script-1'), isFalse);
        expect(await newService.isFavorite('script-2'), isTrue);
      });
    });

    group('edge cases', () {
      test('should handle special characters in script id', () async {
        const specialId = 'script-with-special_chars.123!@#%^&*()';

        await service.toggleFavorite(specialId);

        expect(await service.isFavorite(specialId), isTrue);
      });

      test('should handle unicode in script id', () async {
        const unicodeId = '脚本-123-🎉';

        await service.toggleFavorite(unicodeId);

        expect(await service.isFavorite(unicodeId), isTrue);
      });

      test('should handle very long script id', () async {
        final longId = 'script-${'x' * 1000}';

        await service.toggleFavorite(longId);

        expect(await service.isFavorite(longId), isTrue);
      });

      test('should handle large number of favorites', () async {
        const count = 100;

        for (int i = 0; i < count; i++) {
          await service.toggleFavorite('script-$i');
        }

        final favorites = await service.getAllFavorites();
        expect(favorites.length, count);
      });
    });

    group('singleton behavior', () {
      test('should return the same instance', () {
        final instance1 = FavoritesService();
        final instance2 = FavoritesService();

        expect(identical(instance1, instance2), isTrue);
      });
    });
  });
}
