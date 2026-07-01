import 'dart:convert';

import 'package:icp_autorun/controllers/script_controller.dart';
import 'package:icp_autorun/services/script_runner.dart';

import '../../shared/mock_script_repository.dart';

class MockCanisterBridge implements ScriptBridge {
  final Map<String, dynamic> _mockCanisterData = {
    'governance': {
      'proposals': [
        {
          'id': 1,
          'title': 'Critical Network Upgrade',
          'status': 'active',
          'votes': 1000000000,
          'priority': 'high'
        },
        {
          'id': 2,
          'title': 'Minor Fee Adjustment',
          'status': 'active',
          'votes': 100000000,
          'priority': 'low'
        },
        {
          'id': 3,
          'title': 'Security Enhancement',
          'status': 'active',
          'votes': 500000000,
          'priority': 'high'
        },
        {
          'id': 4,
          'title': 'Documentation Update',
          'status': 'active',
          'votes': 50000000,
          'priority': 'low'
        }
      ]
    },
    'ledger': {
      'transactions': [
        {
          'id': 'tx1',
          'amount': 100000000,
          'from': 'principal1',
          'to': 'principal2',
          'timestamp': 1704067200000000000,
          'type': 'transfer'
        },
        {
          'id': 'tx2',
          'amount': 50000000,
          'from': 'principal2',
          'to': 'principal3',
          'timestamp': 1704067200000001000,
          'type': 'stake'
        },
        {
          'id': 'tx3',
          'amount': 200000000,
          'from': 'principal3',
          'to': 'principal1',
          'timestamp': 1704067200000002000,
          'type': 'transfer'
        },
        {
          'id': 'tx4',
          'amount': 75000000,
          'from': 'principal1',
          'to': 'principal2',
          'timestamp': 1704067200000003000,
          'type': 'transfer'
        },
      ]
    }
  };

  @override
  String? callAnonymous(
      {required String canisterId,
      required String method,
      required int kind,
      String args = '()',
      String? host}) {
    // Simulate different canister responses based on ID and method
    if (canisterId == 'rrkah-fqaaa-aaaaa-aaaaq-cai' &&
        method == 'get_pending_proposals') {
      return json.encode({
        'ok': true,
        'data': _mockCanisterData['governance']['proposals']
            .where((p) => p['status'] == 'pending')
            .toList()
      });
    }

    if (canisterId == 'ryjl3-tyaaa-aaaaa-aaaba-cai' &&
        method == 'query_blocks') {
      return json.encode(
          {'ok': true, 'data': _mockCanisterData['ledger']['transactions']});
    }

    // Generic response for other calls
    return json.encode({
      'ok': true,
      'data': {
        'canister_id': canisterId,
        'method': method,
        'timestamp':
            DateTime.now().millisecondsSinceEpoch * 1000000, // nanoseconds
        'result': 'Mock response'
      }
    });
  }

  @override
  String? callAuthenticated(
      {required String canisterId,
      required String method,
      required int kind,
      String? keypairId,
      String? privateKeyB64,
      String args = '()',
      String? host}) {
    return callAnonymous(
        canisterId: canisterId,
        method: method,
        kind: kind,
        args: args,
        host: host);
  }

  @override
  String? jsExec({required String script, String? jsonArg}) {
    final arg = jsonArg != null ? json.decode(jsonArg) : null;

    // Mock TEA-style execution for advanced output actions
    if (script.contains('init') &&
        script.contains('view') &&
        script.contains('update')) {
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

    if (script.contains('icp_searchable_list')) {
      return json.encode({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {
            'type': 'list',
            'props': {
              'searchable': true,
              'items': arg?['items'] ??
                  [
                    {'title': 'Mock Item'}
                  ],
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
      state['filtered_data'] = (state['loaded_data'] as List)
          .where((tx) => tx['type'] == 'transfer')
          .toList();
      state['last_action'] = 'Filtered transfers';
    }

    if (script.contains('format_and_display')) {
      final items = (state['filtered_data'] as List)
          .map((tx) => {
                'title': 'Transaction ${tx['id']}',
                'subtitle': '${formatIcp(tx['amount'])} • ${tx['type']}',
                'data': tx
              })
          .toList();

      return json.encode({
        'ok': true,
        'result': {
          'action': 'ui',
          'ui': {
            'type': 'list',
            'props': {
              'searchable': true,
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
  String? jsLint({required String script}) {
    return json.encode({'ok': true, 'errors': []});
  }

  @override
  String? jsAppInit(
      {required String script, String? jsonArg, int budgetMs = 50}) {
    // Provide immediate initial UI so the host can render the first frame before calling view().
    // Match the test script by title substring.
    String title = 'Demo';
    if (script.contains('Complete Flow Demo')) {
      title = 'Complete Flow Demo';
    } else if (script.contains('Batch Processing Demo')) {
      title = 'Batch Processing Demo';
    } else if (script.contains('Error Handling Demo')) {
      title = 'Error Handling Demo';
    } else if (script.contains('Follow-up Call Demo')) {
      title = 'Follow-up Call Demo';
    } else if (script.contains('Dynamic Call Generation')) {
      title = 'Dynamic Call Generation';
    } else if (script.contains('Conditional Call Logic')) {
      title = 'Conditional Call Logic';
    }
    return json.encode({
      'ok': true,
      'state': <String, dynamic>{},
      'ui': <String, dynamic>{
        'type': 'column',
        'children': <dynamic>[
          <String, dynamic>{
            'type': 'section',
            'props': <String, dynamic>{'title': title},
            'children': <dynamic>[],
          }
        ],
      },
      'result': null,
    });
  }

  @override
  String? jsAppUpdate(
      {required String script,
      required String msgJson,
      required String stateJson,
      int budgetMs = 50}) {
    final state = json.decode(stateJson);
    final msg = json.decode(msgJson);

    // Handle mock updates matching the TEA scripts in this test
    final String t = (msg['type'] ?? '').toString();
    if (t == 'load_data') {
      // Populate raw_data to match the view() expectations
      state['raw_data'] = _mockCanisterData['ledger']['transactions'];
      return json.encode({'ok': true, 'state': state, 'result': null});
    }
    if (t == 'batch_call') {
      // Simulate batch canister calls and processing
      state['batch_results'] = {
        'gov': {
          'ok': true,
          'data': [
            {'id': 1, 'status': 'active', 'votes': 1000000000},
            {'id': 2, 'status': 'executed', 'votes': 500000000},
          ],
        },
        'ledger': {
          'ok': true,
          'data': [
            {'id': 'tx1', 'amount': 100000000, 'type': 'transfer'},
            {'id': 'tx2', 'amount': 50000000, 'type': 'stake'},
          ],
        },
      };
      final List<dynamic> items = <dynamic>[];
      for (final dynamic proposal in state['batch_results']['gov']['data']) {
        items.add({
          'title': 'Proposal ${proposal['id']}',
          'subtitle': '${proposal['status']} • ${proposal['votes']} votes',
          'data': proposal,
          'category': 'governance',
        });
      }
      for (final dynamic tx in state['batch_results']['ledger']['data']) {
        items.add({
          'title': 'Transaction ${tx['id']}',
          'subtitle': "${tx['type']} • ${formatIcp(tx['amount'] as int)}",
          'data': tx,
          'category': 'ledger',
        });
      }
      state['processed_items'] = items;
      state['last_action'] = 'Executed batch calls and processed results';
      return json.encode({'ok': true, 'state': state, 'result': null});
    }
    if (t == 'load_valid') {
      state['data_state'] = 'valid';
      state['error_state'] = null;
      return json.encode({'ok': true, 'state': state, 'result': null});
    }
    if (t == 'trigger_error') {
      state['error_state'] = 'Simulated error for testing';
      state['data_state'] = 'error';
      return json.encode({'ok': true, 'state': state, 'result': null});
    }
    if (t == 'load_empty') {
      state['data_state'] = 'empty';
      state['error_state'] = null;
      return json.encode({'ok': true, 'state': state, 'result': null});
    }
    if (t == 'transform') {
      final List<dynamic> raw = (state['raw_data'] as List?) ?? <dynamic>[];
      final List<dynamic> processed = raw
          .where((e) => (e['type'] ?? '') == 'transfer')
          .map((tx) => <String, dynamic>{
                'title': 'Transfer ${tx['id']}',
                'subtitle': '${tx['type']} • ${formatIcp(tx['amount'] as int)}',
                'data': tx,
              })
          .toList();
      state['processed_data'] = processed;
      return json.encode({'ok': true, 'state': state, 'result': null});
    }
    if (t == 'searchable') {
      // No-op, used only to toggle view mode in script
      return json.encode({'ok': true, 'state': state, 'result': null});
    }

    // Handle new test scenarios
    if (t == 'load_proposals') {
      final proposals = _mockCanisterData['governance']['proposals'] as List;
      state['initial_data'] = proposals
          .map((p) => {
                'title': p['title'] as String,
                'subtitle':
                    '${p['status']} • ${formatIcp(p['votes'])} votes • Priority: ${p['priority']}',
                'data': p,
                'id': p['id'],
                'status': p['status'],
                'priority': p['priority']
              })
          .toList();
      return json.encode({'ok': true, 'state': state, 'result': null});
    }

    if (t == 'analyze_and_call') {
      final proposals = state['initial_data'] as List? ?? [];
      final highPriority =
          proposals.where((p) => p['priority'] == 'high').toList();

      state['analysis_result'] = {
        'high_priority': highPriority
            .map((p) => {
                  'title': p['title'],
                  'subtitle': p[
                      'subtitle'], // Use the pre-formatted subtitle from load_proposals
                  'data': p,
                  'category': 'governance'
                })
            .toList(),
        'total_proposals': proposals.length,
        'high_priority_count': highPriority.length
      };

      state['follow_up_results'] = {
        'votes': highPriority
            .map((p) => {
                  'yes_votes': (p['data']['votes'] as int) ~/
                      2, // Access original data from the data field
                  'no_votes': (p['data']['votes'] as int) ~/ 3,
                  'total_voters': 42 + (p['data']['id'] as int),
                  'voting_deadline':
                      1704067200 + ((p['data']['id'] as int) * 86400)
                })
            .toList(),
        'timestamps': highPriority.map((p) => 1704067200000000000).toList()
      };

      return json.encode({'ok': true, 'state': state, 'result': null});
    }

    if (t == 'analyze_market') {
      state['market_data'] = [
        {
          'title': 'ICP-USD',
          'subtitle':
              '${formatIcp(125000000)} • +2.5% • Vol: ${formatIcp(1000000000)}',
          'symbol': 'ICP-USD',
          'price': 125000000,
          'change': 2.5,
          'volume': 1000000000,
          'market': 'main'
        },
        {
          'title': 'BTC-ICP',
          'subtitle':
              '${formatIcp(0.00015.toInt())} • -1.2% • Vol: ${formatIcp(500000000)}',
          'symbol': 'BTC-ICP',
          'price': 0.00015,
          'change': -1.2,
          'volume': 500000000,
          'market': 'main'
        },
        {
          'title': 'ETH-ICP',
          'subtitle':
              '${formatIcp(0.0089.toInt())} • +0.8% • Vol: ${formatIcp(750000000)}',
          'symbol': 'ETH-ICP',
          'price': 0.0089,
          'change': 0.8,
          'volume': 750000000,
          'market': 'alt'
        },
        {
          'title': 'DOT-ICP',
          'subtitle':
              '${formatIcp(0.34.toInt())} • +5.2% • Vol: ${formatIcp(200000000)}',
          'symbol': 'DOT-ICP',
          'price': 0.34,
          'change': 5.2,
          'volume': 200000000,
          'market': 'main'
        },
        {
          'title': 'ADA-ICP',
          'subtitle':
              '${formatIcp(2.1.toInt())} • -0.5% • Vol: ${formatIcp(150000000)}',
          'symbol': 'ADA-ICP',
          'price': 2.1,
          'change': -0.5,
          'volume': 150000000,
          'market': 'alt'
        }
      ];

      final marketData = state['market_data'] as List;
      final signals = <dynamic>[];
      final callsToMake = <dynamic>[];

      for (var i = 0; i < marketData.length; i++) {
        final asset = marketData[i];
        if ((asset['change'] as double) > 2.0 ||
            (asset['change'] as double) < -1.0) {
          signals.add({
            'title':
                '${asset['symbol']} - ${((asset['change'] as double) > 0) ? 'BUY' : 'SELL'}',
            'subtitle':
                '${formatIcp((asset['price'] as num).toInt())} • ${asset['change']}% • Vol: ${formatIcp((asset['volume'] as num).toInt())}',
            'data': asset,
            'signal_type':
                ((asset['change'] as double) > 2) ? 'STRONG' : 'WEAK',
            'action_required': true,
            'alert_level': 'HIGH',
            'action': ((asset['change'] as double) > 2.0)
                ? 'BUY_ORDER'
                : 'SELL_ORDER',
            'order_size': (asset['volume'] as num).toInt() ~/ 100
          });

          callsToMake.add({
            'type': 'canister_call',
            'canister': 'exchange',
            'method': ((asset['change'] as double) > 2.0)
                ? 'place_buy_order'
                : 'place_sell_order',
            'args': {
              'symbol': asset['symbol'],
              'amount': signals.last['order_size'],
              'price_type': 'market',
              'timestamp': 1704067200
            }
          });
        }
      }

      state['analysis'] = {
        'signals': signals,
        'total_assets': marketData.length,
        'signal_count': signals.length,
        'market_trend': 'BULLISH',
        'analysis_timestamp': 1704067200
      };

      state['executed_calls'] = callsToMake
          .map((call) => {
                'title': 'Trade: ${call['args']['symbol']} - ${call['method']}',
                'subtitle':
                    'Amount: ${call['args']['amount']} • Status: executed',
                'call_id': 'call_${callsToMake.indexOf(call)}',
                'status': 'executed',
                'transaction_hash':
                    '0x${(1000000 + callsToMake.indexOf(call)).toString()}',
                'executed_at': 1704067200,
                'details': call,
                'result': {
                  'success': true,
                  'filled_amount': call['args']['amount'],
                  'avg_price': 125001250,
                  'fees': 10000
                }
              })
          .toList();

      state['portfolio_state'] = 'updated';
      return json.encode({'ok': true, 'state': state, 'result': null});
    }

    if (t == 'check_services') {
      state['service_status'] = [
        {
          'title': 'governance',
          'subtitle': 'Status: healthy • Response: 120ms • Uptime: 99.9%',
          'status': 'healthy',
          'response_time': 120,
          'uptime': 99.9,
          'last_check': 1704067200
        },
        {
          'title': 'ledger',
          'subtitle': 'Status: degraded • Response: 2500ms • Uptime: 95.2%',
          'status': 'degraded',
          'response_time': 2500,
          'uptime': 95.2,
          'last_check': 1704067200
        },
        {
          'title': 'exchange',
          'subtitle': 'Status: healthy • Response: 80ms • Uptime: 99.8%',
          'status': 'healthy',
          'response_time': 80,
          'uptime': 99.8,
          'last_check': 1704067200
        },
        {
          'title': 'nns',
          'subtitle': 'Status: maintenance • Response: N/A • Uptime: 0%',
          'status': 'maintenance',
          'response_time': null,
          'uptime': 0,
          'last_check': 1704067200
        },
        {
          'title': 'cycles_minting',
          'subtitle': 'Status: healthy • Response: 150ms • Uptime: 99.5%',
          'status': 'healthy',
          'response_time': 150,
          'uptime': 99.5,
          'last_check': 1704067200
        }
      ];

      state['call_attempts'] = <dynamic>[];
      state['successful_calls'] = <dynamic>[];
      state['failed_calls'] = <dynamic>[];
      state['retry_queue'] = <dynamic>[];

      final services = state['service_status'] as List;
      for (var i = 0; i < services.length; i++) {
        final service = services[i];
        state['call_attempts'].add({
          'title': 'Call to ${service['title']}',
          'subtitle':
              'Decision: ${(service['status'] == 'healthy' && (((service['response_time'] as int?) ?? 0) < 1000)) ? 'OPTIMIZE_CALL' : (service['status'] == 'degraded' || (((service['response_time'] as int?) ?? 0) > 2000)) ? 'DIAGNOSTIC_CALL' : (service['status'] == 'maintenance') ? 'DEFERRED' : 'MONITOR_ONLY'}',
          'service': service['title'],
          'status': service['status'],
          'decision': (service['status'] == 'healthy' &&
                  (((service['response_time'] as int?) ?? 0) < 1000))
              ? 'OPTIMIZE_CALL'
              : (service['status'] == 'degraded' ||
                      (((service['response_time'] as int?) ?? 0) > 2000))
                  ? 'DIAGNOSTIC_CALL'
                  : (service['status'] == 'maintenance')
                      ? 'DEFERRED'
                      : 'MONITOR_ONLY',
          'reason': service['status'] == 'healthy'
              ? 'Service healthy, optimizing performance'
              : service['status'] == 'degraded'
                  ? 'Service degraded, running diagnostics'
                  : service['status'] == 'maintenance'
                      ? 'Service under maintenance, deferring calls'
                      : 'Unknown status, monitoring only',
          'timestamp': 1704067200
        });

        if (service['status'] == 'healthy' &&
            (((service['response_time'] as int?) ?? 0) < 1000)) {
          state['successful_calls'].add({
            'title': 'Success: ${service['title']} optimization',
            'subtitle': 'Method: optimize_performance • Status: success',
            'call_id': 'conditional_$i',
            'service': service['title'],
            'method': 'optimize_performance',
            'args': {
              'target_response_time':
                  ((service['response_time'] as int?) ?? 0) * 0.8
            },
            'timestamp': 1704067200,
            'status': 'success',
            'response': {
              'ok': true,
              'data': {
                'optimization_applied': true,
                'performance_improvement': 12
              }
            }
          });
        }
      }

      return json.encode({'ok': true, 'state': state, 'result': null});
    }

    // Legacy/simple flows used in default branch
    if (t == 'filter') {
      final field = msg['field'];
      final value = msg['value'];
      final List<dynamic> data = (state['data'] as List?) ?? <dynamic>[];
      state['filtered'] =
          data.where((item) => item[field].toString().contains(value)).toList();
      return json.encode({'ok': true, 'state': state, 'result': null});
    }

    return json.encode({'ok': true, 'state': state, 'result': null});
  }

  @override
  String? jsAppView(
      {required String script, required String stateJson, int budgetMs = 50}) {
    final state = json.decode(stateJson);

    // Parse the script to determine which test scenario we're in
    if (script.contains('Follow-up Call Demo')) {
      return _mockFollowUpCallView(state);
    } else if (script.contains('Dynamic Call Generation')) {
      return _mockDynamicCallView(state);
    } else if (script.contains('Conditional Call Logic')) {
      return _mockConditionalCallView(state);
    } else if (script.contains('Complete Flow Demo')) {
      // Return the appropriate UI based on current state
      final children = [
        {
          'type': 'section',
          'props': {'title': 'Complete Flow Demo'},
          'children': [
            {
              'type': 'text',
              'props': {'text': 'This demonstrates: Read → Transform → Display'}
            },
            {
              'type': 'row',
              'children': [
                {
                  'type': 'button',
                  'props': {
                    'label': 'Load Data',
                    'on_press': {'type': 'load_data'}
                  }
                },
                {
                  'type': 'button',
                  'props': {
                    'label': 'Transform',
                    'on_press': {'type': 'transform'}
                  }
                },
                {
                  'type': 'button',
                  'props': {
                    'label': 'View Searchable',
                    'on_press': {'type': 'searchable'}
                  }
                },
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
                'searchable': true,
                'items': state['processed_data'],
                'title': 'Transformed Data'
              }
            }
          ]
        });
      }

      return json.encode({
        'ok': true,
        'ui': {'type': 'column', 'children': children}
      });
    }

    if (script.contains('Batch Processing Demo')) {
      final children = [
        {
          'type': 'section',
          'props': {'title': 'Batch Processing Demo'},
          'children': [
            {
              'type': 'text',
              'props': {
                'text':
                    'Demonstrates batch canister calls with data transformation'
              }
            },
            {
              'type': 'button',
              'props': {
                'label': 'Execute Batch Calls',
                'on_press': {'type': 'batch_call'}
              }
            }
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
              'props': {
                'data': state['batch_results'],
                'title': 'Canister Responses'
              }
            }
          ]
        });
      }

      if (state['processed_items'] != null &&
          (state['processed_items'] as List).isNotEmpty) {
        children.add({
          'type': 'section',
          'props': {'title': 'Processed Results'},
          'children': [
            {
              'type': 'list',
              'props': {
                'searchable': true,
                'items': state['processed_items'],
                'title': 'Combined Data View'
              }
            }
          ]
        });
      }

      return json.encode({
        'ok': true,
        'ui': {'type': 'column', 'children': children}
      });
    }

    if (script.contains('Error Handling Demo')) {
      final children = [
        {
          'type': 'section',
          'props': {'title': 'Error Handling Demo'},
          'children': [
            {
              'type': 'button',
              'props': {
                'label': 'Load Valid Data',
                'on_press': {'type': 'load_valid'}
              }
            },
            {
              'type': 'button',
              'props': {
                'label': 'Trigger Error',
                'on_press': {'type': 'trigger_error'}
              }
            },
            {
              'type': 'button',
              'props': {
                'label': 'Load Empty Data',
                'on_press': {'type': 'load_empty'}
              }
            }
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
              'props': {
                'data': {'status': 'success', 'data': 'Valid data loaded'}
              }
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
              'props': {'data': null, 'title': 'Empty Result'}
            }
          ]
        });
      }

      return json.encode({
        'ok': true,
        'ui': {'type': 'column', 'children': children}
      });
    }

    // Default fallback
    final data = state['filtered'] ?? state['data'] ?? [];
    final items = (data as List)
        .map((item) => {
              'title': 'Item ${item['id'] ?? 'unknown'}',
              'subtitle': 'Type: ${item['type'] ?? 'unknown'}',
              'data': item
            })
        .toList();

    return json.encode({
      'ok': true,
      'ui': {
        'type': 'list',
        'props': {'searchable': true, 'items': items, 'title': 'Mock Data View'}
      }
    });
  }

  String _mockFollowUpCallView(Map<String, dynamic> state) {
    final children = [
      {
        'type': 'section',
        'props': {'title': 'Follow-up Call Demo'},
        'children': [
          {
            'type': 'text',
            'props': {'text': 'Demonstrates: Read → Transform → Call'}
          },
          {
            'type': 'row',
            'children': [
              {
                'type': 'button',
                'props': {
                  'label': 'Load Proposals',
                  'on_press': {'type': 'load_proposals'}
                }
              },
              {
                'type': 'button',
                'props': {
                  'label': 'Analyze & Call',
                  'on_press': {'type': 'analyze_and_call'}
                }
              },
            ]
          }
        ]
      }
    ];

    // Show results based on state
    if (state['initial_data'] != null) {
      children.add({
        'type': 'section',
        'props': {'title': 'Initial Proposals'},
        'children': [
          {
            'type': 'list',
            'props': {
              'searchable': true,
              'items': state['initial_data'],
              'title': 'Raw Proposal Data'
            }
          }
        ]
      });
    }

    if (state['analysis_result'] != null &&
        state['analysis_result']['high_priority'] != null) {
      children.add({
        'type': 'section',
        'props': {'title': 'Analysis Results'},
        'children': [
          {
            'type': 'text',
            'props': {
              'text':
                  'High priority proposals found: ${state['analysis_result']['high_priority'].length}'
            }
          },
          {
            'type': 'list',
            'props': {
              'searchable': true,
              'items': state['analysis_result']['high_priority'],
              'title': 'High Priority Proposals'
            }
          }
        ]
      });
    }

    if (state['follow_up_results'] != null &&
        state['follow_up_results']['votes'] != null) {
      children.add({
        'type': 'section',
        'props': {'title': 'Follow-up Call Results'},
        'children': [
          {
            'type': 'text',
            'props': {'text': 'Vote data retrieved successfully'}
          },
          {
            'type': 'result_display',
            'props': {
              'data': state['follow_up_results'],
              'title': 'Follow-up Canister Calls'
            }
          }
        ]
      });
    }

    return json.encode({
      'ok': true,
      'ui': {'type': 'column', 'children': children}
    });
  }

  String _mockDynamicCallView(Map<String, dynamic> state) {
    final children = [
      {
        'type': 'section',
        'props': {'title': 'Dynamic Call Generation'},
        'children': [
          {
            'type': 'text',
            'props': {
              'text': 'Read market data → analyze → generate dynamic calls'
            }
          },
          {
            'type': 'button',
            'props': {
              'label': 'Analyze Market',
              'on_press': {'type': 'analyze_market'}
            }
          }
        ]
      }
    ];

    if (state['market_data'] != null &&
        (state['market_data'] as List).isNotEmpty) {
      children.add({
        'type': 'section',
        'props': {'title': 'Market Data'},
        'children': [
          {
            'type': 'list',
            'props': {
              'searchable': true,
              'items': state['market_data'],
              'title': 'Current Market Prices'
            }
          }
        ]
      });
    }

    if (state['analysis'] != null && state['analysis']['signals'] != null) {
      children.add({
        'type': 'section',
        'props': {'title': 'Analysis & Signals'},
        'children': [
          {
            'type': 'text',
            'props': {
              'text':
                  'Trading signals detected: ${state['analysis']['signals'].length}'
            }
          },
          {
            'type': 'list',
            'props': {
              'searchable': true,
              'items': state['analysis']['signals'],
              'title': 'Generated Trading Signals'
            }
          }
        ]
      });
    }

    if (state['executed_calls'] != null &&
        (state['executed_calls'] as List).isNotEmpty) {
      children.add({
        'type': 'section',
        'props': {'title': 'Executed Trades'},
        'children': [
          {
            'type': 'text',
            'props': {
              'text':
                  'Dynamic calls executed: ${state['executed_calls'].length}'
            }
          },
          {
            'type': 'result_display',
            'props': {
              'data': state['executed_calls'],
              'title': 'Trade Execution Results'
            }
          }
        ]
      });
    }

    return json.encode({
      'ok': true,
      'ui': {'type': 'column', 'children': children}
    });
  }

  String _mockConditionalCallView(Map<String, dynamic> state) {
    final children = [
      {
        'type': 'section',
        'props': {'title': 'Conditional Call Logic'},
        'children': [
          {
            'type': 'text',
            'props': {
              'text': 'Read service status → conditional calls → error recovery'
            }
          },
          {
            'type': 'button',
            'props': {
              'label': 'Check Services',
              'on_press': {'type': 'check_services'}
            }
          }
        ]
      }
    ];

    if (state['service_status'] != null &&
        (state['service_status'] as List).isNotEmpty) {
      children.add({
        'type': 'section',
        'props': {'title': 'Service Status'},
        'children': [
          {
            'type': 'list',
            'props': {
              'searchable': true,
              'items': state['service_status'],
              'title': 'Service Health Check'
            }
          }
        ]
      });
    }

    if (state['call_attempts'] != null &&
        (state['call_attempts'] as List).isNotEmpty) {
      children.add({
        'type': 'section',
        'props': {'title': 'Call Attempts'},
        'children': [
          {
            'type': 'text',
            'props': {
              'text': 'Total attempts: ${state['call_attempts'].length}'
            }
          },
          {
            'type': 'list',
            'props': {
              'searchable': true,
              'items': state['call_attempts'],
              'title': 'Conditional Call Log'
            }
          }
        ]
      });
    }

    if (state['successful_calls'] != null &&
        (state['successful_calls'] as List).isNotEmpty) {
      children.add({
        'type': 'section',
        'props': {'title': 'Successful Calls'},
        'children': [
          {
            'type': 'text',
            'props': {
              'text':
                  'Successfully executed: ${state['successful_calls'].length}'
            }
          },
          {
            'type': 'result_display',
            'props': {
              'data': state['successful_calls'],
              'title': 'Successful Operations'
            }
          }
        ]
      });
    }

    return json.encode({
      'ok': true,
      'ui': {'type': 'column', 'children': children}
    });
  }
}


Future<ScriptController> bootstrapMockScriptController() async {
  final repository = MockScriptRepository();
  final controller = ScriptController(repository);
  await controller.ensureLoaded();
  return controller;
}
