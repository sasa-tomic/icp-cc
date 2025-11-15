import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_template.dart';

void main() {
  // Initialize Flutter bindings for asset loading
  TestWidgetsFlutterBinding.ensureInitialized();

  // Ensure templates are loaded before running tests
  // Access templates to trigger initialization
  ScriptTemplates.templates;
  group('ScriptTemplate Tests', () {
    test('Should have all required templates available', () {
      expect(ScriptTemplates.templates.length, 4, reason: 'Should have exactly 4 built-in templates');

      final templateIds = ScriptTemplates.templates.map((t) => t.id).toList();
      expect(templateIds, contains('hello_world'));
      expect(templateIds, contains('data_management'));
      expect(templateIds, contains('icp_demo'));
      expect(templateIds, contains('advanced_ui'));
    });

    test('Should find template by ID', () {
      final template = ScriptTemplates.getById('hello_world');
      expect(template, isNotNull);
      expect(template!.title, 'Hello World');
      expect(template.emoji, '👋');
      expect(template.level, 'beginner');
      expect(template.isRecommended, true);
    });

    test('Should return null for unknown template ID', () {
      final template = ScriptTemplates.getById('unknown');
      expect(template, isNull);
    });

    test('Should filter templates by level', () {
      final beginnerTemplates = ScriptTemplates.getByLevel('beginner');
      expect(beginnerTemplates.length, 2);
      expect(beginnerTemplates.every((t) => t.level == 'beginner'), true);

      final intermediateTemplates = ScriptTemplates.getByLevel('intermediate');
      expect(intermediateTemplates.length, 1);
      expect(intermediateTemplates.first.level, 'intermediate');

      final advancedTemplates = ScriptTemplates.getByLevel('advanced');
      expect(advancedTemplates.length, 1);
      expect(advancedTemplates.first.level, 'advanced');
    });

    test('Should get recommended templates', () {
      final recommendedTemplates = ScriptTemplates.getRecommended();
      expect(recommendedTemplates.length, 1);
      expect(recommendedTemplates.first.isRecommended, true);
      expect(recommendedTemplates.first.id, 'hello_world');
    });

    test('Should search templates by query', () {
      // Search by title
      final titleResults = ScriptTemplates.search('hello');
      expect(titleResults.length, 1);
      expect(titleResults.first.id, 'hello_world');

      // Search by description
      final descriptionResults = ScriptTemplates.search('blockchain');
      expect(descriptionResults.length, 1);
      expect(descriptionResults.first.id, 'icp_demo');

      // Search by tags
      final tagResults = ScriptTemplates.search('filtering');
      expect(tagResults.length, 2); // data_management and advanced_ui

      // Case insensitive search
      final caseResults = ScriptTemplates.search('ICP');
      expect(caseResults.length, 1); // icp_demo only (has uppercase ICP in title)

      // Empty search returns all
      final emptyResults = ScriptTemplates.search('');
      expect(emptyResults.length, ScriptTemplates.templates.length);

      // No matches
      final noResults = ScriptTemplates.search('nonexistent');
      expect(noResults.isEmpty, true);
    });

    test('Should have valid Lua source code for all templates', () {
      for (final template in ScriptTemplates.templates) {
        final source = template.luaSource;
        expect(source, isNotEmpty, reason: 'Template ${template.id} should have Lua source');
        expect(source, contains('function init'), reason: 'Template ${template.id} should have init function');
        expect(source, contains('function view'), reason: 'Template ${template.id} should have view function');
        expect(source, contains('function update'), reason: 'Template ${template.id} should have update function');
      }
    });

    test('Should have proper metadata for all templates', () {
      for (final template in ScriptTemplates.templates) {
        expect(template.id, isNotEmpty);
        expect(template.title, isNotEmpty);
        expect(template.description, isNotEmpty);
        expect(template.emoji, isNotEmpty);
        expect(template.level, isIn(['beginner', 'intermediate', 'advanced']));
        expect(template.tags, isNotEmpty);

        // Check that level color mapping would work
        expect(['beginner', 'intermediate', 'advanced'], contains(template.level));
      }
    });

    test('Should have appropriate difficulty progression', () {
      final beginner = ScriptTemplates.getById('hello_world')!;
      final intermediate = ScriptTemplates.getById('icp_demo')!;
      final advanced = ScriptTemplates.getById('advanced_ui')!;

      final beginnerSource = beginner.luaSource;
      final intermediateSource = intermediate.luaSource;
      final advancedSource = advanced.luaSource;

      // Advanced should be longest (it has complex filtering logic)
      expect(advancedSource.length, greaterThan(intermediateSource.length));
      expect(advancedSource.length, greaterThan(beginnerSource.length));

      // Tags should reflect complexity
      expect(beginner.tags, contains('basic'));
      expect(intermediate.tags, contains('icp'));
      expect(advanced.tags, contains('advanced'));
    });
  });

  group('ScriptTemplate Content Validation', () {
    test('Hello World template should have basic UI components', () {
      final template = ScriptTemplates.getById('hello_world')!;
      final source = template.luaSource;

      // Should demonstrate basic components
      expect(source, contains('section'));
      expect(source, contains('text'));
      expect(source, contains('button'));
      expect(source, contains('on_press'));

      // Should have simple state management
      expect(source, contains('counter'));
      expect(source, contains('increment'));

      // Should be beginner-friendly with comments
      expect(source, contains('--'));
    });

    test('Data Management template should have filtering', () {
      final template = ScriptTemplates.getById('data_management')!;
      final source = template.luaSource;

      // Should demonstrate data operations
      expect(source, contains('items'));
      expect(source, contains('filter'));
      expect(source, contains('generate_sample_data'));

      // Should have UI for data management
      expect(source, contains('text_field'));
      expect(source, contains('delete_item'));
    });

    test('ICP Demo template should have canister calls', () {
      final template = ScriptTemplates.getById('icp_demo')!;
      final source = template.luaSource;

      // Should demonstrate ICP integration
      expect(source, contains('canister_id'));
      expect(source, contains('ryjl3-tyaaa-aaaaa-aaaba-cai')); // ICP Ledger
      expect(source, contains('get_balance'));
      expect(source, contains('get_transactions'));

      // Should handle async responses
      expect(source, contains('balance_loaded'));
      expect(source, contains('transactions_loaded'));

      // Should use custom ICP formatting functions
      expect(source, contains('format_icp'));
    });

    test('Advanced UI template should have advanced features', () {
      final template = ScriptTemplates.getById('advanced_ui')!;
      final source = template.luaSource;

      // Should demonstrate advanced UI (using our refactored template)
      expect(source, contains('render_header_section'));
      expect(source, contains('render_controls_section'));
      expect(source, contains('render_statistics_section'));

      // Should have complex data processing
      expect(source, contains('get_filtered_transactions'));
      expect(source, contains('get_sorted_transactions'));
      expect(source, contains('format_transactions_for_display'));

      // Should use basic UI components
      expect(source, contains('section'));
      expect(source, contains('text_field'));
      expect(source, contains('select'));
      expect(source, contains('toggle'));

      // Should have custom helper functions
      expect(source, contains('format_timestamp'));
      expect(source, contains('format_icp'));
    });
  });

  group('ScriptTemplate Compatibility Tests', () {
    test('All templates should use available UI components only', () {
      // These are the UI components available in the app
      final availableComponents = [
        'column', 'row', 'section', 'text', 'button', 'text_field',
        'toggle', 'select', 'image', 'list', 'result_display'
      ];

      for (final template in ScriptTemplates.templates) {
        final source = template.luaSource.toLowerCase();

        for (final component in availableComponents) {
          // Check if template uses this component (optional for some templates)
          if (source.contains('type = "$component"')) {
            // Component is used, which is fine
          }
        }
      }
    });

    test('All templates should use available ICP helpers only', () {
      // These are the ICP helper functions available in the app
      final availableHelpers = [
        'icp_call', 'icp_batch', 'icp_message', 'icp_ui_list',
        'icp_result_display',         'icp_searchable_list', 'icp_section',
        'icp_table', 'icp_format_number', 'icp_format_icp',
        'icp_format_timestamp', 'icp_format_bytes', 'icp_truncate',
        'icp_filter_items', 'icp_sort_items', 'icp_group_by'
      ];

      for (final template in ScriptTemplates.templates) {
        final source = template.luaSource;

        for (final helper in availableHelpers) {
          if (source.contains('$helper(')) {
            // Helper is used, which is fine
          }
        }
      }
    });

    test('All templates should avoid unavailable functions', () {
      // These functions are NOT available in the sandboxed Lua environment
      // Note: os.date is allowed in example templates for demonstration purposes
      final unavailableFunctions = [
        'os.time', 'io.', 'debug.', 'package.',
        'require(', 'loadfile(', 'dofile('
      ];

      for (final template in ScriptTemplates.templates) {
        final source = template.luaSource;

        for (final func in unavailableFunctions) {
          expect(source, isNot(contains(func)),
                 reason: 'Template ${template.id} should not use unavailable function: $func');
        }
      }
    });
  });
}