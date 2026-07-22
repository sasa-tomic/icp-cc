import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/ui_v1_renderer.dart';

/// Helper: pump [UiV1Renderer] inside a bounded-width scrollable parent
/// (mirrors how the host embeds it — SingleChildScrollView → Column(stretch)).
Future<void> pumpUi(
  WidgetTester tester, {
  required Map<String, dynamic> ui,
  UiEventHandler? onEvent,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: UiV1Renderer(
                ui: ui,
                onEvent: onEvent ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('UiV1Renderer basic nodes', () {
    testWidgets('column renders children vertically', (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'column',
          'children': [
            {'type': 'text', 'props': {'text': 'First'}},
            {'type': 'text', 'props': {'text': 'Second'}},
          ],
        },
      );
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });

    testWidgets('section renders title and children', (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'section',
          'props': {'title': 'My Section'},
          'children': [
            {'type': 'text', 'props': {'text': 'Content'}},
          ],
        },
      );
      expect(find.text('My Section'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('text renders plain text', (tester) async {
      await pumpUi(
        tester,
        ui: {'type': 'text', 'props': {'text': 'Hello world'}},
      );
      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('button fires on_press event', (tester) async {
      final events = <Map<String, dynamic>>[];
      await pumpUi(
        tester,
        ui: {
          'type': 'button',
          'props': {
            'label': 'Click me',
            'on_press': {'type': 'clicked'},
          },
        },
        onEvent: events.add,
      );
      await tester.tap(find.text('Click me'));
      expect(events, hasLength(1));
      expect(events.first['type'], 'clicked');
    });

    testWidgets('unsupported type shows error widget', (tester) async {
      await pumpUi(
        tester,
        ui: {'type': 'bogus'},
      );
      expect(find.textContaining('Unsupported node type'), findsOneWidget);
    });
  });

  group('UiV1Renderer row with form fields (DEFECT-1 regression)', () {
    testWidgets('row with select + button renders without layout exception',
        (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'column',
          'children': [
            {
              'type': 'row',
              'children': [
                {
                  'type': 'select',
                  'props': {
                    'label': 'Status',
                    'value': 'open',
                    'options': [
                      {'value': 'all', 'label': 'All'},
                      {'value': 'open', 'label': 'Open'},
                    ],
                    'on_change': {'type': 'set_status'},
                  },
                },
                {
                  'type': 'button',
                  'props': {
                    'label': 'Go',
                    'on_press': {'type': 'refresh'},
                  },
                },
              ],
            },
          ],
        },
      );
      // If the row rendered, the dropdown's current value text is visible.
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Go'), findsOneWidget);
    });

    testWidgets('row with two selects renders without layout exception',
        (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'column',
          'children': [
            {
              'type': 'row',
              'children': [
                {
                  'type': 'select',
                  'props': {
                    'label': 'A',
                    'value': '1',
                    'options': [
                      {'value': '1', 'label': 'One'},
                    ],
                  },
                },
                {
                  'type': 'select',
                  'props': {
                    'label': 'B',
                    'value': '2',
                    'options': [
                      {'value': '2', 'label': 'Two'},
                    ],
                  },
                },
              ],
            },
          ],
        },
      );
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
    });

    testWidgets('row with text_field renders without layout exception',
        (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'column',
          'children': [
            {
              'type': 'row',
              'children': [
                {
                  'type': 'text_field',
                  'props': {
                    'label': 'Search',
                    'value': '',
                    'on_change': {'type': 'search'},
                  },
                },
                {
                  'type': 'button',
                  'props': {
                    'label': 'Find',
                    'on_press': {'type': 'find'},
                  },
                },
              ],
            },
          ],
        },
      );
      expect(find.text('Find'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('row with only buttons renders normally', (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'row',
          'children': [
            {
              'type': 'button',
              'props': {'label': 'Yes', 'on_press': {'type': 'vote'}},
            },
            {
              'type': 'button',
              'props': {'label': 'No', 'on_press': {'type': 'vote'}},
            },
          ],
        },
      );
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
    });

    testWidgets('row with copyable text renders without layout exception (DEFECT-3 regression)',
        (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'column',
          'children': [
            {
              'type': 'row',
              'children': [
                {
                  'type': 'text',
                  'props': {
                    'text': 'Neuron ID: 753ai-something-long-principal-id-here',
                    'copy': true,
                    'copy_label': 'Copy ID',
                  },
                },
                {
                  'type': 'button',
                  'props': {
                    'label': 'Refresh',
                    'on_press': {'type': 'refresh'},
                  },
                },
              ],
            },
          ],
        },
      );
      expect(find.textContaining('Neuron ID:'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });
  });

  group('UiV1Renderer select options (DEFECT-2 hardening)', () {
    testWidgets('select with Map options shows error, does not crash',
        (tester) async {
      // alpha_vote bug: STATUS_FILTER_VALUE passed as JS object → arrives as
      // Map<String, dynamic> on the Dart side. Must not crash the whole app.
      await pumpUi(
        tester,
        ui: {
          'type': 'column',
          'children': [
            {
              'type': 'select',
              'props': {
                'label': 'Status',
                'value': '',
                'options': <String, dynamic>{
                  'all': '',
                  'open': '1',
                },
              },
            },
            {'type': 'text', 'props': {'text': 'Sibling survives'},
            },
          ],
        },
      );
      // The sibling text should still render — the broken select must not
      // take down the entire tree.
      expect(find.text('Sibling survives'), findsOneWidget);
    });

    testWidgets('select with array options renders dropdown items',
        (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'select',
          'props': {
            'label': 'Topic',
            'value': 'all',
            'options': [
              {'value': 'all', 'label': 'All topics'},
              {'value': 'gov', 'label': 'Governance'},
            ],
          },
        },
      );
      expect(find.text('All topics'), findsOneWidget);
    });
  });

  group('UiV1Renderer table', () {
    testWidgets('renders columns and rows', (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'table',
          'props': {
            'title': 'Votes',
            'columns': [
              {'key': 'name', 'label': 'Neuron'},
              {'key': 'vote', 'label': 'Vote'},
            ],
            'rows': [
              {'name': 'alpha', 'vote': 'Yes'},
              {'name': 'omega', 'vote': 'No'},
            ],
          },
        },
      );
      expect(find.text('Neuron'), findsOneWidget);
      expect(find.text('Vote'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('omega'), findsOneWidget);
    });

    testWidgets('table with non-list columns shows error', (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'table',
          'props': {
            'columns': <String, dynamic>{'key': 'name'},
            'rows': <Map<String, dynamic>>[],
          },
        },
      );
      expect(find.textContaining('columns'), findsOneWidget);
    });
  });

  group('UiV1Renderer list', () {
    testWidgets('renders list items with title + subtitle', (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'list',
          'props': {
            'title': 'Proposals',
            'items': [
              {'title': 'Proposal #1', 'subtitle': 'Governance'},
              {'title': 'Proposal #2', 'subtitle': 'Treasury'},
            ],
          },
        },
      );
      expect(find.text('Proposals'), findsOneWidget);
      expect(find.text('Proposal #1'), findsOneWidget);
      expect(find.text('Governance'), findsOneWidget);
    });
  });

  group('UiV1Renderer paginated_list', () {
    testWidgets('renders items and load-more button when has_more',
        (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'paginated_list',
          'props': {
            'title': 'Results',
            'items': [
              {'title': 'Item A'},
            ],
            'has_more': true,
            'loading': false,
          },
        },
      );
      expect(find.text('Item A'), findsOneWidget);
      expect(find.text('Load More'), findsOneWidget);
    });

    testWidgets('shows no-more-items footer when has_more is false',
        (tester) async {
      await pumpUi(
        tester,
        ui: {
          'type': 'paginated_list',
          'props': {
            'title': 'Results',
            'items': [
              {'title': 'Item A'},
            ],
            'has_more': false,
            'loading': false,
          },
        },
      );
      expect(find.text('No more items'), findsOneWidget);
    });
  });
}
