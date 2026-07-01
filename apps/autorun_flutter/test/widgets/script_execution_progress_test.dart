import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_execution_progress.dart';
import 'package:icp_autorun/widgets/script_execution_progress_indicator.dart';
import 'package:icp_autorun/widgets/script_app_host.dart';
import 'package:icp_autorun/services/script_runner.dart';

void main() {
  group('ScriptExecutionProgress model', () {
    test('creates with default values', () {
      final progress = ScriptExecutionProgress();
      expect(progress.phase, ScriptExecutionPhase.idle);
      expect(progress.message, isEmpty);
      expect(progress.isCancellable, isFalse);
    });

    test('creates with specific values', () {
      final progress = ScriptExecutionProgress(
        phase: ScriptExecutionPhase.callingCanister,
        message: 'Calling ledger canister...',
        isCancellable: true,
      );
      expect(progress.phase, ScriptExecutionPhase.callingCanister);
      expect(progress.message, 'Calling ledger canister...');
      expect(progress.isCancellable, isTrue);
    });

    test('copyWith creates modified copy', () {
      final original = ScriptExecutionProgress(
        phase: ScriptExecutionPhase.initializing,
        message: 'Starting...',
      );
      final modified = original.copyWith(
        phase: ScriptExecutionPhase.processingResponse,
        message: 'Processing data...',
      );
      expect(original.phase, ScriptExecutionPhase.initializing);
      expect(modified.phase, ScriptExecutionPhase.processingResponse);
      expect(modified.message, 'Processing data...');
    });

    test('phase labels are human-readable', () {
      expect(ScriptExecutionPhase.idle.label, 'Idle');
      expect(ScriptExecutionPhase.initializing.label, 'Initializing');
      expect(ScriptExecutionPhase.callingCanister.label, 'Calling canister');
      expect(
          ScriptExecutionPhase.processingResponse.label, 'Processing response');
      expect(ScriptExecutionPhase.rendering.label, 'Rendering');
      expect(ScriptExecutionPhase.complete.label, 'Complete');
      expect(ScriptExecutionPhase.error.label, 'Error');
    });

    test('isInProgress returns true for active phases', () {
      expect(ScriptExecutionPhase.idle.isInProgress, isFalse);
      expect(ScriptExecutionPhase.initializing.isInProgress, isTrue);
      expect(ScriptExecutionPhase.callingCanister.isInProgress, isTrue);
      expect(ScriptExecutionPhase.processingResponse.isInProgress, isTrue);
      expect(ScriptExecutionPhase.rendering.isInProgress, isTrue);
      expect(ScriptExecutionPhase.complete.isInProgress, isFalse);
      expect(ScriptExecutionPhase.error.isInProgress, isFalse);
    });
  });

  group('ScriptExecutionProgressIndicator widget', () {
    testWidgets('displays progress message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptExecutionProgressIndicator(
            progress: ScriptExecutionProgress(
              phase: ScriptExecutionPhase.callingCanister,
              message: 'Querying canister...',
            ),
          ),
        ),
      ));

      expect(find.text('Querying canister...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows cancel button when cancellable', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptExecutionProgressIndicator(
            progress: ScriptExecutionProgress(
              phase: ScriptExecutionPhase.initializing,
              message: 'Loading...',
              isCancellable: true,
            ),
            onCancel: () {},
          ),
        ),
      ));

      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });

    testWidgets('hides cancel button when not cancellable', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptExecutionProgressIndicator(
            progress: ScriptExecutionProgress(
              phase: ScriptExecutionPhase.rendering,
              message: 'Rendering UI...',
              isCancellable: false,
            ),
          ),
        ),
      ));

      expect(find.byIcon(Icons.cancel), findsNothing);
    });

    testWidgets('cancel button triggers callback', (tester) async {
      bool cancelled = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptExecutionProgressIndicator(
            progress: ScriptExecutionProgress(
              phase: ScriptExecutionPhase.callingCanister,
              message: 'Calling...',
              isCancellable: true,
            ),
            onCancel: () {
              cancelled = true;
            },
          ),
        ),
      ));

      await tester.tap(find.byIcon(Icons.cancel));
      expect(cancelled, isTrue);
    });

    testWidgets('shows error state with red color', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptExecutionProgressIndicator(
            progress: ScriptExecutionProgress(
              phase: ScriptExecutionPhase.error,
              message: 'Connection failed',
            ),
          ),
        ),
      ));

      final text = tester.widget<Text>(find.text('Connection failed'));
      expect(text.style?.color, isNotNull);
    });

    testWidgets('shows complete state with check icon', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptExecutionProgressIndicator(
            progress: ScriptExecutionProgress(
              phase: ScriptExecutionPhase.complete,
              message: 'Done',
            ),
          ),
        ),
      ));

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('ScriptAppHost progress tracking', () {
    testWidgets('reports progress through notifier', (tester) async {
      final progressNotifier = ValueNotifier<ScriptExecutionProgress>(
        ScriptExecutionProgress(),
      );

      final fake = _FakeRuntime();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ScriptAppHost(
            runtime: fake,
            script: '/* ts bundle */',
            progressNotifier: progressNotifier,
          ),
        ),
      ));

      await tester.pump();
      await tester.pumpAndSettle();

      expect(progressNotifier.value.phase, ScriptExecutionPhase.complete);
    });
  });
}

class _FakeRuntime implements IScriptAppRuntime {
  @override
  Future<Map<String, dynamic>> init({
    required String script,
    Map<String, dynamic>? initialArg,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'state': <String, dynamic>{},
      'ui': <String, dynamic>{'type': 'message', 'content': 'Ready'},
    };
  }

  @override
  Future<Map<String, dynamic>> view({
    required String script,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'ui': <String, dynamic>{'type': 'message', 'content': 'Ready'},
    };
  }

  @override
  Future<Map<String, dynamic>> update({
    required String script,
    required Map<String, dynamic> msg,
    required Map<String, dynamic> state,
    int budgetMs = 50,
  }) async {
    return <String, dynamic>{
      'ok': true,
      'state': state,
    };
  }
}
