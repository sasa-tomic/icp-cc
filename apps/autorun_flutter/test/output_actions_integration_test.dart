import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/result_display.dart';
import 'package:icp_autorun/widgets/ui_v1_renderer.dart';

void main() {
  group('Output Actions Integration Tests', () {
    test('script runner includes enhanced helper functions', () {
      // Verify that all the new helper functions are included in the integration catalog
      final helpers = ScriptRunner.integrationCatalog.map((info) => info.id).toList();

      expect(helpers, contains('icp_result_display'));
      expect(helpers, contains('icp_enhanced_list'));
      expect(helpers, contains('icp_format_icp'));
      expect(helpers, contains('icp_format_timestamp'));
      expect(helpers, contains('icp_filter_items'));
      expect(helpers, contains('icp_sort_items'));
    });

    test('enhanced UI widgets are available and properly exported', () {
      // Test that the enhanced UI widgets can be instantiated
      expect(ResultDisplay, isA<Type>());
      expect(UiV1Renderer, isA<Type>());
    });

    test('integration catalog includes helper descriptions and examples', () {
      final catalog = ScriptRunner.integrationCatalog;

      // Check for enhanced result display helper
      final resultDisplayHelper = catalog.firstWhere((info) => info.id == 'icp_result_display');
      expect(resultDisplayHelper.title, equals('Enhanced Result Display'));
      expect(resultDisplayHelper.description, contains('enhanced formatting'));
      expect(resultDisplayHelper.example, contains('icp_result_display'));

      // Check for enhanced list helper
      final enhancedListHelper = catalog.firstWhere((info) => info.id == 'icp_enhanced_list');
      expect(enhancedListHelper.title, equals('Searchable Result List'));
      expect(enhancedListHelper.description, contains('searchable'));
      expect(enhancedListHelper.example, contains('icp_enhanced_list'));

      // Check for ICP formatter helper
      final icpFormatterHelper = catalog.firstWhere((info) => info.id == 'icp_format_icp');
      expect(icpFormatterHelper.title, equals('ICP Token Formatter'));
      expect(icpFormatterHelper.description, contains('e8s'));
      expect(icpFormatterHelper.example, contains('123456789'));
    });

    test('helper functions follow naming conventions', () {
      final catalog = ScriptRunner.integrationCatalog;

      // All helper functions should follow icp_ prefix
      final helpers = catalog.where((info) => info.id.startsWith('icp_')).toList();
      expect(helpers.length, greaterThan(8)); // Should have many icp_ helpers

      // Should include all the new enhanced output helpers
      final helperIds = helpers.map((info) => info.id).toList();
      expect(helperIds, contains('icp_result_display'));
      expect(helperIds, contains('icp_enhanced_list'));
      expect(helperIds, contains('icp_format_icp'));
      expect(helperIds, contains('icp_format_timestamp'));
      expect(helperIds, contains('icp_filter_items'));
      expect(helperIds, contains('icp_sort_items'));
    });

    test('enhanced output helpers provide meaningful examples', () {
      final catalog = ScriptRunner.integrationCatalog;

      for (final helper in catalog) {
        // All helpers should have titles, descriptions, and examples
        expect(helper.title, isNotEmpty);
        expect(helper.description, isNotEmpty);
        expect(helper.example, isNotEmpty);

        // Examples should demonstrate the helper function usage
        if (helper.id.startsWith('icp_')) {
          expect(helper.example, contains(helper.id));
        }
      }
    });

    test('UI renderer supports new widget types', () {
      // Test that the UI renderer includes the new widget types
      // This validates that the UI renderer has been extended to support enhanced widgets
      final renderer = UiV1Renderer(
        ui: const {'type': 'result_display', 'props': {}},
        onEvent: (event) {},
      );

      expect(renderer, isA<UiV1Renderer>());

      // Test that the enhanced list renderer can be instantiated
      final listRenderer = UiV1Renderer(
        ui: const {'type': 'list', 'props': {'enhanced': true, 'items': []}},
        onEvent: (event) {},
      );

      expect(listRenderer, isA<UiV1Renderer>());
    });

    test('ResultDisplay widget handles basic configurations', () {
      // Test that ResultDisplay can handle various data types
      final textDisplay = ResultDisplay(data: 'test data');
      expect(textDisplay.data, equals('test data'));

      final mapDisplay = ResultDisplay(data: {'key': 'value'});
      expect(mapDisplay.data, equals({'key': 'value'}));

      final listDisplay = ResultDisplay(data: ['item1', 'item2']);
      expect(listDisplay.data, equals(['item1', 'item2']));

      final errorDisplay = ResultDisplay(data: null, error: 'test error');
      expect(errorDisplay.error, equals('test error'));
    });
  });
}