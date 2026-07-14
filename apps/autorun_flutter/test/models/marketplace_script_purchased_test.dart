import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';

/// Coverage for the entitlement fields on [MarketplaceScript]:
/// - `purchased` parses when present (true/false) and defaults to null when
///   absent (legacy list responses, search responses, etc.).
/// - `isDownloadable` correctly gates on `price == 0 || purchased == true`.
/// - `copyWith` round-trips `purchased`.
void main() {
  group('MarketplaceScript.purchased parsing', () {
    MarketplaceScript buildFrom(Map<String, dynamic> overrides) {
      return MarketplaceScript.fromJson({
        'id': 'script-1',
        'title': 'T',
        'description': 'D',
        'category': 'C',
        'bundle': 'print(1)',
        'price': 0.0,
        'createdAt': '2024-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
        ...overrides,
      });
    }

    test('parses purchased: true', () {
      final script = buildFrom({'purchased': true, 'price': 9.99});
      expect(script.purchased, isTrue);
    });

    test('parses purchased: false', () {
      final script = buildFrom({'purchased': false, 'price': 9.99});
      expect(script.purchased, isFalse);
    });

    test('purchased is null when the field is absent (legacy list response)',
        () {
      final script = buildFrom({'price': 9.99});
      expect(script.purchased, isNull,
          reason: 'absence must mean "unknown", not false');
    });

    test('toJson omits purchased when null (back-compat wire shape)', () {
      final script = buildFrom({'price': 9.99});
      expect(script.purchased, isNull);
      final json = script.toJson();
      expect(json.containsKey('purchased'), isFalse,
          reason: 'null purchased must not be serialised to "purchased": null');
    });

    test('toJson includes purchased when set', () {
      final script = buildFrom({'purchased': true, 'price': 9.99});
      expect(script.toJson()['purchased'], isTrue);
    });
  });

  group('MarketplaceScript.isDownloadable', () {
    test('free scripts are always downloadable regardless of purchased', () {
      expect(
        MarketplaceScript(
          id: 's',
          title: 't',
          description: 'd',
          category: 'c',
          bundle: 'b',
          price: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ).isDownloadable,
        isTrue,
      );
    });

    test('paid + purchased is downloadable', () {
      expect(
        MarketplaceScript(
          id: 's',
          title: 't',
          description: 'd',
          category: 'c',
          bundle: 'b',
          price: 9.99,
          purchased: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ).isDownloadable,
        isTrue,
      );
    });

    test('paid + purchased:false is NOT downloadable (renders Buy CTA)', () {
      expect(
        MarketplaceScript(
          id: 's',
          title: 't',
          description: 'd',
          category: 'c',
          bundle: 'b',
          price: 9.99,
          purchased: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ).isDownloadable,
        isFalse,
      );
    });

    test('paid + purchased:null (unknown) is NOT downloadable (safe default)',
        () {
      expect(
        MarketplaceScript(
          id: 's',
          title: 't',
          description: 'd',
          category: 'c',
          bundle: 'b',
          price: 9.99,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ).isDownloadable,
        isFalse,
        reason: 'a paid script with no entitlement signal must NOT be '
            'downloadable — the client must confirm via the signed '
            'checkEntitlement endpoint (W7-2) before offering the download '
            'affordance.',
      );
    });
  });

  group('MarketplaceScript.copyWith.purchased', () {
    test('round-trips purchased through copyWith', () {
      final original = MarketplaceScript(
        id: 's',
        title: 't',
        description: 'd',
        category: 'c',
        bundle: 'b',
        price: 9.99,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(original.purchased, isNull);

      final purchased = original.copyWith(purchased: true);
      expect(purchased.purchased, isTrue);

      // copyWith with no purchased arg preserves the existing value.
      final renamed = purchased.copyWith(title: 'new');
      expect(renamed.purchased, isTrue);
    });
  });
}
