import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/script_repository.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';

class MockScriptRepository extends ScriptRepository {
  final Map<String, ScriptRecord> _scripts = {};

  @override
  Future<List<ScriptRecord>> loadScripts() async {
    return _scripts.values.toList();
  }

  @override
  Future<void> persistScripts(List<ScriptRecord> scripts) async {
    for (final script in scripts) {
      _scripts[script.id] = script;
    }
  }
}

class MockEnhancedBridge implements ScriptBridge {
  final Map<String, dynamic> _mockCanisterData = {
    'governance': {
      'proposals': [
        {'id': 1, 'title': 'Proposal 1', 'status': 'active', 'votes': 1000000000},
        {'id': 2, 'title': 'Proposal 2', 'status': 'executed', 'votes': 500000000},
        {'id': 3, 'title': 'Proposal 3', 'status': 'pending', 'votes': 750000000},
      ]
    },
    'ledger': {
      'transactions': [
        {'id': 'tx1', 'amount': 100000000, 'from': 'principal1', 'to': 'principal2', 'timestamp': 1704067200000000000, 'type': 'transfer'},
        {'id': 'tx2', 'amount': 50000000, 'from': 'principal2', 'to': 'principal3', 'timestamp': 1704067200000001000, 'type': 'stake'},
        {'id': 'tx3', 'amount': 200000000, 'from': 'principal3', 'to': 'principal1', 'timestamp': 1704067200000002000, 'type': 'transfer'},
        {'id': 'tx4', 'amount': 75000000, 'from': 'principal1', 'to': 'principal2', 'timestamp': 1704067200000003000, 'type': 'transfer'},
      ]
    }
  };

  @override
  String? callAnonymous({required String canisterId, required String method, required int kind, String args = '()', String? host}) {
    // Simulate different canister responses based on ID and method
    if (canisterId == 'rrkah-fqaaa-aaaaa-aaaaq-cai' && method == 'get_pending_proposals') {
      return json.encode({
        'ok': true,
        'data': _mockCanisterData['governance']['proposals'].where((p) => p['status'] == 'pending').toList()
      });
    }

    if (canisterId == 'ryjl3-tyaaa-aaaaa-aaaba-cai' && method == 'query_blocks') {
      return json.encode({
        'ok': true,
        'data': _mockCanisterData['ledger']['transactions']
      });
    }

    // Generic response for other calls
    return json.encode({
      'ok': true,
      'data': {
        'canister_id': canisterId,
        'method': method,
        'timestamp': DateTime.now().millisecondsSinceEpoch * 1000000, // nanoseconds
        'result': 'Mock response'
      }
    });
  }

  @override
  String? callAuthenticated({required String canisterId, required String method, required int kind, String? identityId, String? privateKeyB64, String args = '()', String? host}) {
    return callAnonymous(canisterId: canisterId, method: method, kind: kind, args: args, host: host);
  }

  @override
  String? luaExec({required String script, String? jsonArg}) {
    final arg = jsonArg != null ? json.decode(jsonArg) : null;

    // Mock TEA-style execution for enhanced output actions
    if (script.contains('init') && script.contains('view') && script.contains('update')) {
      return _mockTeaExecution(script, arg);
    }

    // Handle individual helper calls
    if (script.contains('icp_result_display')) {
      return json.encode({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {
            'type': 'result_display',
            'props': arg ?? {'data': 'Mock result data'}
          }
        }
      });
    }

    if (script.contains('icp_enhanced_list')) {
      return json.encode({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {
            'type': 'list',
            'props': {
              'enhanced': true,
              'items': arg?['items'] ?? [{'title': 'Mock Item'}],
              'title': arg?['title'] ?? 'Mock Results'
            }
          }
        }
      });
    }

    if (script.contains('icp_call') && script.contains('batch')) {
      return json.encode({
        'ok': true,
        'result': {
          'gov': {
            'ok': true,
            'data': _mockCanisterData['governance']['proposals']
          },
          'ledger': {
            'ok': true,
            'data': _mockCanisterData['ledger']['transactions']
          }
        }
      });
    }

    return json.encode({'ok': true, 'result': 'Mock execution result'});
  }

  String _mockTeaExecution(String script, dynamic arg) {
    // Simple TEA state management for testing
    final Map<String, dynamic> state = {
      'loaded_data': <dynamic>[],
      'filtered_data': <dynamic>[],
      'last_action': '',
    };

    // Extract init/update/view logic based on script patterns
    if (script.contains('load_sample_data')) {
      state['loaded_data'] = _mockCanisterData['ledger']['transactions'];
      state['last_action'] = 'Loaded sample data';
    }

    if (script.contains('filter_transfers')) {
      state['filtered_data'] = (state['loaded_data'] as List).where((tx) => tx['type'] == 'transfer').toList();
      state['last_action'] = 'Filtered transfers';
    }

    if (script.contains('format_and_display')) {
      final items = (state['filtered_data'] as List).map((tx) => {
        'title': 'Transaction ${tx['id']}',
        'subtitle': '${formatIcp(tx['amount'])} • ${tx['type']}',
        'data': tx
      }).toList();

      return json.encode({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {
            'type': 'list',
            'props': {
              'enhanced': true,
              'items': items,
              'title': 'Formatted Transactions'
            }
          }
        }
      });
    }

    return json.encode({
      'ok': true,
      'result': {
        'action': 'ui',
        'ui': {
          'type': 'text',
          'props': {'text': 'Mock TEA execution: ${state['last_action']}'}
        }
      }
    });
  }

  String formatIcp(int value) {
    return '${(value / 100000000).toStringAsFixed(8).replaceAll(RegExp(r'\.?0+$'), '')} ICP';
  }

  @override
  String? luaLint({required String script}) {
    return json.encode({'ok': true, 'errors': []});
  }

  @override
  String? luaAppInit({required String script, String? jsonArg, int budgetMs = 50}) {
    return json.encode({'ok': true, 'state': {}, 'result': null});
  }

  @override
  String? luaAppUpdate({required String script, required String msgJson, required String stateJson, int budgetMs = 50}) {
    final state = json.decode(stateJson);
    final msg = json.decode(msgJson);

    // Handle mock updates
    if (msg['type'] == 'load_data') {
      state['data'] = _mockCanisterData['ledger']['transactions'];
    } else if (msg['type'] == 'filter') {
      final field = msg['field'];
      final value = msg['value'];
      state['filtered'] = (state['data'] as List).where((item) => item[field].toString().contains(value)).toList();
    }

    return json.encode({'ok': true, 'state': state, 'result': null});
  }

  @override
  String? luaAppView({required String script, required String stateJson, int budgetMs = 50}) {
    final state = json.decode(stateJson);

    // Parse the script to determine which test scenario we're in
    if (script.contains('Complete Flow Demo')) {
      // Return the appropriate UI based on current state
      final children = [
        {
          'type': 'section',
          'props': {'title': 'Complete Flow Demo'},
          'children': [
            {'type': 'text', 'props': {'text': 'This demonstrates: Read → Transform → Display'}},
            {
              'type': 'row',
              'children': [
                {'type': 'button', 'props': {'label': 'Load Data', 'on_press': {'type': 'load_data'}}},
                {'type': 'button', 'props': {'label': 'Transform', 'on_press': {'type': 'transform'}}},
                {'type': 'button', 'props': {'label': 'View Enhanced', 'on_press': {'type': 'enhanced'}}},
              ]
            }
          ]
        }
      ];

      // Add result sections based on state
      if (state['raw_data'] != null) {
        children.add({
          'type': 'section',
          'props': {'title': 'Raw Results'},
          'children': [
            {
              'type': 'result_display',
              'props': {'data': state['raw_data'], 'title': 'Raw Canister Data'}
            }
          ]
        });
      }

      if (state['processed_data'] != null) {
        children.add({
          'type': 'section',
          'props': {'title': 'Processed Results'},
          'children': [
            {
              'type': 'list',
              'props': {
                'enhanced': true,
                'items': state['processed_data'],
                'title': 'Transformed Data',
                'searchable': true
              }
            }
          ]
        });
      }

      return json.encode({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {
            'type': 'column',
            'children': children
          }
        }
      });
    }

    if (script.contains('Batch Processing Demo')) {
      final children = [
        {
          'type': 'section',
          'props': {'title': 'Batch Processing Demo'},
          'children': [
            {'type': 'text', 'props': {'text': 'Demonstrates batch canister calls with data transformation'}},
            {'type': 'button', 'props': {'label': 'Execute Batch Calls', 'on_press': {'type': 'batch_call'}}}
          ]
        }
      ];

      if (state['batch_results'] != null) {
        children.add({
          'type': 'section',
          'props': {'title': 'Raw Batch Results'},
          'children': [
            {
              'type': 'result_display',
              'props': {'data': state['batch_results'], 'title': 'Canister Responses'}
            }
          ]
        });
      }

      if (state['processed_items'] != null && (state['processed_items'] as List).isNotEmpty) {
        children.add({
          'type': 'section',
          'props': {'title': 'Processed Results'},
          'children': [
            {
              'type': 'list',
              'props': {
                'enhanced': true,
                'items': state['processed_items'],
                'title': 'Combined Data View',
                'searchable': true
              }
            }
          ]
        });
      }

      return json.encode({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {
            'type': 'column',
            'children': children
          }
        }
      });
    }

    if (script.contains('Error Handling Demo')) {
      final children = [
        {
          'type': 'section',
          'props': {'title': 'Error Handling Demo'},
          'children': [
            {'type': 'button', 'props': {'label': 'Load Valid Data', 'on_press': {'type': 'load_valid'}}},
            {'type': 'button', 'props': {'label': 'Trigger Error', 'on_press': {'type': 'trigger_error'}}},
            {'type': 'button', 'props': {'label': 'Load Empty Data', 'on_press': {'type': 'load_empty'}}}
          ]
        }
      ];

      if (state['error_state'] != null) {
        children.add({
          'type': 'section',
          'props': {'title': 'Error State'},
          'children': [
            {
              'type': 'result_display',
              'props': {'error': state['error_state'], 'title': 'Error Display'}
            }
          ]
        });
      }

      if (state['data_state'] == 'valid') {
        children.add({
          'type': 'section',
          'props': {'title': 'Valid Data'},
          'children': [
            {
              'type': 'result_display',
              'props': {'data': {'status': 'success', 'data': 'Valid data loaded'}}
            }
          ]
        });
      }

      if (state['data_state'] == 'empty') {
        children.add({
          'type': 'section',
          'props': {'title': 'Empty Data'},
          'children': [
            {
              'type': 'result_display',
              'props': {'data': {}, 'title': 'Empty Result'}
            }
          ]
        });
      }

      return json.encode({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {
            'type': 'column',
            'children': children
          }
        }
      });
    }

    // Default fallback
    final data = state['filtered'] ?? state['data'] ?? [];
    final items = (data as List).map((item) => {
      'title': 'Item ${item['id'] ?? 'unknown'}',
      'subtitle': 'Type: ${item['type'] ?? 'unknown'}',
      'data': item
    }).toList();

    return json.encode({
      'ok': true,
      'result': {
        'action': 'ui',
        'ui': {
          'type': 'list',
          'props': {
            'enhanced': true,
            'items': items,
            'title': 'Mock Data View'
          }
        }
      }
    });
  }
}

void main() {
  group('E2E Output Actions Integration Tests', () {
    late ScriptRepository repository;
    late ScriptController controller;

    setUp(() async {
      repository = MockScriptRepository();
      controller = ScriptController(repository);
      await controller.ensureLoaded();
    });

    group('Read → Transform → Display Flow Tests', () {
      testWidgets('complete flow: canister call → data transformation → enhanced display', (WidgetTester tester) async {
        // Create a test script that demonstrates the complete flow
        const enhancedScript = '''
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
        { type = "button", props = { label = "View Enhanced", on_press = { type = "enhanced" } } },
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
      icp_enhanced_list({ items = state.processed_data, title = "Transformed Data", searchable = true })
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

  if t == "enhanced" then
    if state.processed_data then
      state.last_action = "Showing enhanced view"
    end
    return state, {}
  end

  state.last_action = "Unknown action: " .. t
  return state, {}
end
        ''';

        // Create and save the script
        final script = await controller.createScript(
          title: 'Enhanced Flow Test',
          luaSourceOverride: enhancedScript,
        );

        // Build the widget tree
        await tester.pumpWidget(
          MaterialApp(
            home: ScriptAppHost(
              runtime: ScriptAppRuntime(MockEnhancedBridge()),
              script: script.luaSource,
            ),
          ),
        );

        // Verify initial UI state
        expect(find.text('Complete Flow Demo'), findsOneWidget);
        expect(find.text('Load Data'), findsOneWidget);
        expect(find.text('Transform'), findsOneWidget);
        expect(find.text('View Enhanced'), findsOneWidget);

        // Step 1: Load Data (Read)
        await tester.tap(find.text('Load Data'));
        await tester.pumpAndSettle();

        expect(find.text('Raw Results'), findsOneWidget);
        expect(find.text('Raw Canister Data'), findsOneWidget);
        expect(find.byIcon(Icons.copy), findsWidgets); // Copy buttons should be visible

        // Step 2: Transform Data
        await tester.tap(find.text('Transform'));
        await tester.pumpAndSettle();

        expect(find.text('Processed Results'), findsOneWidget);
        expect(find.text('Transformed Data'), findsOneWidget);
        expect(find.text('Searchable'), findsOneWidget); // Enhanced list should be searchable

        // Step 3: Verify enhanced display features
        expect(find.text('Transfer tx1'), findsOneWidget);
        expect(find.text('Transfer tx3'), findsOneWidget); // Only transfers, no stakes
        expect(find.textContaining('ICP'), findsWidgets); // Formatted amounts
        expect(find.byIcon(Icons.search), findsOneWidget); // Search functionality

        // Test search functionality
        await tester.enterText(find.byType(TextField), 'tx1');
        await tester.pumpAndSettle();

        expect(find.text('Transfer tx1'), findsOneWidget);
        expect(find.text('Transfer tx3'), findsNothing); // Should be filtered out
      });

      testWidgets('batch canister calls with data transformation', (WidgetTester tester) async {
        const batchScript = '''
-- Batch canister calls with enhanced result processing
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
      icp_enhanced_list({ items = state.processed_items, title = "Combined Data View", searchable = true })
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
          luaSourceOverride: batchScript,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ScriptAppHost(
              runtime: ScriptAppRuntime(MockEnhancedBridge()),
              script: script.luaSource,
            ),
          ),
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
        expect(find.text('4/4'), findsOneWidget); // 4 items total (2 proposals + 2 transactions)

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
        expect(find.text('Transaction tx1'), findsNothing); // Should be filtered out
      });

      testWidgets('error handling and graceful degradation', (WidgetTester tester) async {
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
          luaSourceOverride: errorHandlingScript,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ScriptAppHost(
              runtime: ScriptAppRuntime(MockEnhancedBridge()),
              script: script.luaSource,
            ),
          ),
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