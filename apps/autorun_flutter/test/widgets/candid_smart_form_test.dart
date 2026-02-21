import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/widgets/candid_smart_form.dart';

void main() {
  group('CandidSmartForm', () {
    group('scalar types', () {
      testWidgets('renders TextField for text type', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['text'],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('text'), findsOneWidget);
      });

      testWidgets('renders number input for nat type', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['nat'],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.keyboardType, TextInputType.number);
      });

      testWidgets('renders Switch for bool type', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['bool'],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        expect(find.byType(Switch), findsOneWidget);
      });

      testWidgets('renders DropdownButton for variant type', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['variant { active; inactive; pending }'],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        expect(find.byType(DropdownButton<String>), findsOneWidget);
      });
    });

    group('record types', () {
      testWidgets('renders nested fields for simple record', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Material(
                child: CandidSmartForm(
                  key: formKey,
                  argTypes: const ['record { name : text; age : nat }'],
                  onJsonChanged: (_) {},
                ),
              ),
            ),
          ),
        ));

        expect(find.text('name'), findsOneWidget);
        expect(find.text('age'), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(2));
      });

      testWidgets('renders bool Switch inside record', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Material(
                child: CandidSmartForm(
                  key: formKey,
                  argTypes: const ['record { name : text; active : bool }'],
                  onJsonChanged: (_) {},
                ),
              ),
            ),
          ),
        ));

        expect(find.byType(Switch), findsOneWidget);
        expect(find.text('active'), findsOneWidget);
      });
    });

    group('vec types', () {
      testWidgets('renders JSON editor for vec text', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['vec text'],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        expect(find.byType(TextField), findsOneWidget);
        final hint = tester
            .widget<TextField>(find.byType(TextField))
            .decoration
            ?.hintText;
        expect(hint, contains('['));
      });
    });

    group('opt types', () {
      testWidgets('renders nullable field for opt type', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['opt text'],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        expect(find.text('optional'), findsOneWidget);
      });
    });

    group('JSON output', () {
      testWidgets('outputs correct JSON for text input', (tester) async {
        String? output;
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['text'],
              onJsonChanged: (json) => output = json,
            ),
          ),
        ));

        await tester.enterText(find.byType(TextField), 'hello');
        await tester.pump();

        expect(output, '"hello"');
      });

      testWidgets('outputs correct JSON for bool Switch', (tester) async {
        String? output;
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['bool'],
              onJsonChanged: (json) => output = json,
            ),
          ),
        ));

        await tester.tap(find.byType(Switch));
        await tester.pump();

        expect(output, 'true');
      });

      testWidgets('outputs correct JSON for number input', (tester) async {
        String? output;
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['nat64'],
              onJsonChanged: (json) => output = json,
            ),
          ),
        ));

        await tester.enterText(find.byType(TextField), '42');
        await tester.pump();

        expect(output, '42');
      });

      testWidgets('outputs correct JSON for variant selection', (tester) async {
        String? output;
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['variant { active; inactive }'],
              onJsonChanged: (json) => output = json,
            ),
          ),
        ));

        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('inactive').last);
        await tester.pumpAndSettle();

        expect(output, '{"inactive":null}');
      });

      testWidgets('outputs correct JSON for record with multiple fields',
          (tester) async {
        String? output;
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Material(
                child: CandidSmartForm(
                  key: formKey,
                  argTypes: const [
                    'record { name : text; age : nat64; active : bool }'
                  ],
                  onJsonChanged: (json) => output = json,
                ),
              ),
            ),
          ),
        ));

        final textFields = find.byType(TextField);
        await tester.enterText(textFields.at(0), 'Alice');
        await tester.pump();
        await tester.enterText(textFields.at(1), '30');
        await tester.pump();
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(output, contains('"name":"Alice"'));
        expect(output, contains('"age":30'));
        expect(output, contains('"active":true'));
      });
    });

    group('multiple args', () {
      testWidgets('renders array of fields for multiple args', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Material(
                child: CandidSmartForm(
                  key: formKey,
                  argTypes: const ['text', 'nat64', 'bool'],
                  onJsonChanged: (_) {},
                ),
              ),
            ),
          ),
        ));

        expect(find.byType(TextField), findsNWidgets(2));
        expect(find.byType(Switch), findsOneWidget);
      });

      testWidgets('outputs array JSON for multiple args', (tester) async {
        String? output;
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Material(
                child: CandidSmartForm(
                  key: formKey,
                  argTypes: const ['text', 'nat64'],
                  onJsonChanged: (json) => output = json,
                ),
              ),
            ),
          ),
        ));

        final textFields = find.byType(TextField);
        await tester.enterText(textFields.at(0), 'test');
        await tester.pump();
        await tester.enterText(textFields.at(1), '123');
        await tester.pump();

        expect(output, '["test",123]');
      });
    });

    group('unsupported types', () {
      testWidgets('falls back to JSON editor for func type', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['func (text) -> (text)'],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        expect(find.byType(TextField), findsOneWidget);
        final hint = tester
            .widget<TextField>(find.byType(TextField))
            .decoration
            ?.hintText;
        expect(hint, contains('JSON'));
      });
    });

    group('validation', () {
      testWidgets('accepts valid number input', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['nat64'],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        await tester.enterText(find.byType(TextField), '42');
        await tester.pump();

        expect(formKey.currentState?.hasErrors, isFalse);
      });

      testWidgets('number input has input filter', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const ['nat64'],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.inputFormatters, isNotEmpty);
      });
    });

    group('getJson', () {
      testWidgets('returns empty string for no args', (tester) async {
        final formKey = GlobalKey<CandidSmartFormState>();
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CandidSmartForm(
              key: formKey,
              argTypes: const [],
              onJsonChanged: (_) {},
            ),
          ),
        ));

        expect(formKey.currentState?.getJson(), '');
      });
    });
  });
}
