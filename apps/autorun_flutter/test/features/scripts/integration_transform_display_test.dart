import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/services/script_runner.dart';

import '_scripts_test_harness.dart';
import 'integration_transform_helpers.dart';

void main() {
  group('E2E Output Actions Integration Tests', () {
    late ScriptController controller;

    setUp(() async {
      controller = await bootstrapMockScriptController();
    });

    group('Read → Transform → Display Flow Tests', () {
      testWidgets(
          'complete flow: canister call → data transformation → searchable display',
          (WidgetTester tester) async {
        // Create a test script that demonstrates the complete flow
        const searchableScript = '''
function init(arg)
  return {
    raw_data = {},
    processed_data = {},
    view_mode = "raw"
  }, {}
end

function view(state)
  local children = {
    { type = "section", props = { title = "Complete Flow Demo" }, children = {
      { type = "text", props = { text = "This demonstrates: Read → Transform → Display" } },
      { type = "row", children = {
        { type = "button", props = { label = "Load Data", on_press = { type = "load_data" } } },
        { type = "button", props = { label = "Transform", on_press = { type = "transform" } } },
        { type = "button", props = { label = "View Searchable", on_press = { type = "searchable" } } },
      } }
    } }
  }

  -- Show results
  if state.raw_data and #state.raw_data > 0 then
    table.insert(children, { type = "section", props = { title = "Raw Results" }, children = {
      { type = "result_display", props = { data = state.raw_data, title = "Raw Canister Data" } }
    }})
  end

  if state.processed_data and #state.processed_data > 0 then
    table.insert(children, { type = "section", props = { title = "Processed Results" }, children = {
      icp_searchable_list({ items = state.processed_data, title = "Transformed Data", searchable = true })
    }})
  end

  return { type = "column", children = children }
end

function update(msg, state)
  local t = msg.type

  if t == "load_data" then
    -- Simulate canister call to get data
    local mock_result = {
      ok = true,
      data = {
        {id = "tx1", amount = 100000000, type = "transfer", timestamp = 1704067200000000000},
        {id = "tx2", amount = 50000000, type = "stake", timestamp = 1704067200000001000},
        {id = "tx3", amount = 200000000, type = "transfer", timestamp = 1704067200000002000}
      }
    }
    state.raw_data = mock_result.data
    state.last_action = "Loaded raw data"
    return state, {}
  end

  if t == "transform" then
    if state.raw_data then
      -- Transform data: filter transfers and format amounts
      local processed = {}
      for i, item in ipairs(state.raw_data) do
        if item.type == "transfer" then
          table.insert(processed, {
            title = "Transfer " .. item.id,
            subtitle = string.format("%s • %s", icp_format_timestamp(item.timestamp), icp_format_icp(item.amount)),
            data = item
          })
        end
      end
      state.processed_data = processed
      state.last_action = "Transformed data: filtered and formatted"
    end
    return state, {}
  end

  if t == "searchable" then
    if state.processed_data then
      state.last_action = "Showing searchable view"
    end
    return state, {}
  end

  state.last_action = "Unknown action: " .. t
  return state, {}
end
        ''';

        // Create and save the script
        final script = await controller.createScript(
          title: 'Searchable Flow Test',
          bundleOverride: searchableScript,
        );

        // Build the widget tree + allow async init/view to complete
        await pumpScriptApp(
          tester,
          runtime: ScriptAppRuntime(MockCanisterBridge()),
          bundle: script.bundle,
        );

        // Verify initial UI state
        expect(find.text('Complete Flow Demo'), findsOneWidget);
        expect(find.text('Load Data'), findsOneWidget);
        expect(find.text('Transform'), findsOneWidget);
        expect(find.text('View Searchable'), findsOneWidget);

        // Step 1: Load Data (Read)
        await tester.tap(find.text('Load Data'));
        await tester.pumpAndSettle();

        expect(find.text('Raw Results'), findsOneWidget);
        expect(find.text('Raw Canister Data'), findsOneWidget);
        expect(find.byIcon(Icons.copy),
            findsWidgets); // Copy buttons should be visible

        // Step 2: Transform Data
        await tester.tap(find.text('Transform'));
        await tester.pumpAndSettle();

        expect(find.text('Processed Results'), findsOneWidget);
        expect(find.text('Transformed Data'), findsOneWidget);
        expect(find.byIcon(Icons.search),
            findsOneWidget); // Searchable list should be searchable

        // Step 3: Verify searchable display features
        expect(find.text('Transfer tx1'), findsOneWidget);
        expect(find.text('Transfer tx3'),
            findsOneWidget); // Only transfers, no stakes
        expect(find.textContaining('ICP'), findsWidgets); // Formatted amounts
        expect(
            find.byIcon(Icons.search), findsOneWidget); // Search functionality

        // Test search functionality
        await tester.enterText(find.byType(TextField), 'tx1');
        await tester.pumpAndSettle();

        expect(find.text('Transfer tx1'), findsOneWidget);
        expect(
            find.text('Transfer tx3'), findsNothing); // Should be filtered out
      });

      testWidgets('batch canister calls with data transformation',
          (WidgetTester tester) async {
        const batchScript = '''
-- Batch canister calls with searchable result processing
local function process_batch_results(results)
  local items = {}

  -- Process governance proposals
  if results.gov and results.gov.ok then
    for i, proposal in ipairs(results.gov.data) do
      table.insert(items, {
        title = "Proposal " .. proposal.id,
        subtitle = proposal.status .. " • " .. proposal.votes .. " votes",
        data = proposal,
        category = "governance"
      })
    end
  end

  -- Process ledger transactions
  if results.ledger and results.ledger.ok then
    for i, tx in ipairs(results.ledger.data) do
      table.insert(items, {
        title = "Transaction " .. tx.id,
        subtitle = tx.type .. " • " .. icp_format_icp(tx.amount),
        data = tx,
        category = "ledger"
      })
    end
  end

  return items
end

function init(arg)
  return { batch_results = nil, processed_items = {}, last_action = nil }, {}
end

function view(state)
  local children = {
    { type = "section", props = { title = "Batch Processing Demo" }, children = {
      { type = "text", props = { text = "Demonstrates batch canister calls with data transformation" } },
      { type = "button", props = { label = "Execute Batch Calls", on_press = { type = "batch_call" } } }
    } }
  }

  if state.batch_results then
    table.insert(children, { type = "section", props = { title = "Raw Batch Results" }, children = {
      { type = "result_display", props = { data = state.batch_results, title = "Canister Responses" } }
    }})
  end

  if state.processed_items and #state.processed_items > 0 then
    table.insert(children, { type = "section", props = { title = "Processed Results" }, children = {
      icp_searchable_list({ items = state.processed_items, title = "Combined Data View", searchable = true })
    }})
  end

  if state.last_action then
    table.insert(children, { type = "text", props = { text = "Last action: " .. state.last_action } })
  end

  return { type = "column", children = children }
end

function update(msg, state)
  if msg.type == "batch_call" then
    -- Simulate batch canister calls
    state.batch_results = {
      gov = { ok = true, data = {
        {id = 1, status = "active", votes = 1000000000},
        {id = 2, status = "executed", votes = 500000000}
      }},
      ledger = { ok = true, data = {
        {id = "tx1", amount = 100000000, type = "transfer"},
        {id = "tx2", amount = 50000000, type = "stake"}
      }}
    }
    state.processed_items = process_batch_results(state.batch_results)
    state.last_action = "Executed batch calls and processed results"
    return state, {}
  end

  state.last_action = "Unknown action: " .. msg.type
  return state, {}
end
        ''';

        final script = await controller.createScript(
          title: 'Batch Flow Test',
          bundleOverride: batchScript,
        );

        await pumpScriptApp(
          tester,
          runtime: ScriptAppRuntime(MockCanisterBridge()),
          bundle: script.bundle,
        );

        // Initial state
        expect(find.text('Batch Processing Demo'), findsOneWidget);
        expect(find.text('Execute Batch Calls'), findsOneWidget);

        // Execute batch calls
        await tester.tap(find.text('Execute Batch Calls'));
        await tester.pumpAndSettle();

        // Verify raw results are displayed
        expect(find.text('Raw Batch Results'), findsOneWidget);
        expect(find.text('Canister Responses'), findsOneWidget);

        // Verify processed results
        expect(find.text('Processed Results'), findsOneWidget);
        expect(find.text('Combined Data View'), findsOneWidget);
        expect(find.text('4/4'),
            findsOneWidget); // 4 items total (2 proposals + 2 transactions)

        // Verify data transformation worked
        expect(find.text('Proposal 1'), findsOneWidget);
        expect(find.text('Proposal 2'), findsOneWidget);
        expect(find.text('Transaction tx1'), findsOneWidget);
        expect(find.text('Transaction tx2'), findsOneWidget);

        // Verify formatting
        expect(find.textContaining('votes'), findsWidgets);
        expect(find.textContaining('ICP'), findsWidgets);

        // Test search across combined data
        await tester.enterText(find.byType(TextField), 'Proposal');
        await tester.pumpAndSettle();

        expect(find.text('2/4'), findsOneWidget); // Should show 2 proposals
        expect(find.text('Proposal 1'), findsOneWidget);
        expect(find.text('Proposal 2'), findsOneWidget);
        expect(find.text('Transaction tx1'),
            findsNothing); // Should be filtered out
      });

      testWidgets('error handling and graceful degradation',
          (WidgetTester tester) async {
        const errorHandlingScript = '''
function init(arg)
  return { data_state = "none", error_state = nil }, {}
end

function view(state)
  local children = {
    { type = "section", props = { title = "Error Handling Demo" }, children = {
      { type = "button", props = { label = "Load Valid Data", on_press = { type = "load_valid" } } },
      { type = "button", props = { label = "Trigger Error", on_press = { type = "trigger_error" } } },
      { type = "button", props = { label = "Load Empty Data", on_press = { type = "load_empty" } } }
    } }
  }

  if state.error_state then
    table.insert(children, { type = "section", props = { title = "Error State" }, children = {
      { type = "result_display", props = { error = state.error_state, title = "Error Display" } }
    }})
  end

  if state.data_state == "valid" then
    table.insert(children, { type = "section", props = { title = "Valid Data" }, children = {
      { type = "result_display", props = { data = {status = "success", data = "Valid data loaded"} } }
    }})
  end

  if state.data_state == "empty" then
    table.insert(children, { type = "section", props = { title = "Empty Data" }, children = {
      { type = "result_display", props = { data = {}, title = "Empty Result" } }
    }})
  end

  return { type = "column", children = children }
end

function update(msg, state)
  if msg.type == "load_valid" then
    state.data_state = "valid"
    state.error_state = nil
    return state, {}
  end

  if msg.type == "trigger_error" then
    state.error_state = "Simulated error for testing"
    state.data_state = "error"
    return state, {}
  end

  if msg.type == "load_empty" then
    state.data_state = "empty"
    state.error_state = nil
    return state, {}
  end

  return state, {}
end
        ''';

        final script = await controller.createScript(
          title: 'Error Handling Test',
          bundleOverride: errorHandlingScript,
        );

        await pumpScriptApp(
          tester,
          runtime: ScriptAppRuntime(MockCanisterBridge()),
          bundle: script.bundle,
        );

        expect(find.text('Error Handling Demo'), findsOneWidget);

        // Test error scenario
        await tester.tap(find.text('Trigger Error'));
        await tester.pumpAndSettle();

        expect(find.text('Error State'), findsOneWidget);
        expect(find.text('Error Display'), findsOneWidget);
        expect(find.text('Simulated error for testing'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);

        // Test valid data scenario
        await tester.tap(find.text('Load Valid Data'));
        await tester.pumpAndSettle();

        expect(find.text('Valid Data'), findsOneWidget);
        expect(find.text('success'), findsOneWidget);
        expect(find.text('Valid data loaded'), findsOneWidget);

        // Test empty data scenario
        await tester.tap(find.text('Load Empty Data'));
        await tester.pumpAndSettle();

        expect(find.text('Empty Data'), findsOneWidget);
        expect(find.text('Empty Result'), findsOneWidget);
        expect(find.text('No data'), findsOneWidget);
      });
    });
  });
}
