import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/utils/responsive_grid_config.dart';

void main() {
  group('ResponsiveGridConfig', () {
    test('uses single compact column on narrow screens', () {
      final config = ResponsiveGridConfig.forWidth(390);
      expect(config.crossAxisCount, 1);
      expect(config.childAspectRatio, closeTo(1.35, 0.001));
    });

    test('switches to two compact columns on tablet widths', () {
      final config = ResponsiveGridConfig.forWidth(1000);
      expect(config.crossAxisCount, 2);
      expect(config.childAspectRatio, closeTo(1.6, 0.001));
    });

    test('expands to three columns on desktop widths', () {
      final config = ResponsiveGridConfig.forWidth(1600);
      expect(config.crossAxisCount, 3);
      expect(config.childAspectRatio, closeTo(1.75, 0.001));
    });
  });
}
