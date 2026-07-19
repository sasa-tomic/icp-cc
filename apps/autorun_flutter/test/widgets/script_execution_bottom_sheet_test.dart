import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/script_runner.dart';
import 'package:icp_autorun/widgets/script_execution_bottom_sheet.dart';
import 'package:icp_autorun/widgets/trust_badges.dart';

/// W7-19: the run panel must render the script's `imageUrl` artwork when
/// present (with the emoji/📦 as the load-failure fallback), mirroring the
/// list tile — instead of always showing the hard-coded emoji.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  ScriptRecord script({
    String? imageUrl,
    String? emoji,
    String? marketplaceId,
  }) =>
      ScriptRecord(
        id: 's1',
        title: 'Hello IC Starter (Marketplace)',
        emoji: emoji,
        imageUrl: imageUrl,
        bundle: 'print(1)',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
        metadata:
            marketplaceId == null ? const {} : {'marketplace_id': marketplaceId},
      );

  testWidgets(
      'run panel renders the artwork (CachedNetworkImage) when imageUrl is set',
      (tester) async {
    await tester.pumpWidget(wrap(ScriptExecutionBottomSheet(
      script: script(
        imageUrl: 'https://example.com/icon.png',
        emoji: '📦',
        marketplaceId: 'hello-ic-starter',
      ),
      runtime: _FakeRuntime(),
    )));

    // Title is rendered in the header.
    expect(find.text('Hello IC Starter (Marketplace)'), findsOneWidget);
    // The image widget is present (not just the emoji).
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    final cni = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(cni.imageUrl, 'https://example.com/icon.png');
  });

  testWidgets(
      'run panel falls back to the emoji when no imageUrl is set (no image widget)',
      (tester) async {
    await tester.pumpWidget(wrap(ScriptExecutionBottomSheet(
      script: script(emoji: '📦', marketplaceId: 'hello-ic-starter'),
      runtime: _FakeRuntime(),
    )));

    expect(find.byType(CachedNetworkImage), findsNothing);
    // Marketplace script with 📦 emoji → fallback shown.
    expect(find.text('📦'), findsOneWidget);
  });

  group('UX-H1 run-panel trust row', () {
    testWidgets(
      'run panel surfaces the SandboxedChip so the runtime promise is visible '
      'while the script executes',
      (tester) async {
        await tester.pumpWidget(wrap(ScriptExecutionBottomSheet(
          script: script(emoji: '📦', marketplaceId: 'hello-ic-starter'),
          runtime: _FakeRuntime(),
        )));

        expect(find.byType(SandboxedChip), findsOneWidget);
      },
    );

    testWidgets(
      'run panel surfaces the SignatureVerifiedChip when the bundle carries '
      'a verified checksum',
      (tester) async {
        await tester.pumpWidget(wrap(ScriptExecutionBottomSheet(
          script: ScriptRecord(
            id: 'verified',
            title: 'Verified Marketplace Script',
            bundle: 'print(1)',
            emoji: '📦',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 2),
            metadata: const {
              'marketplace_id': 'hello-ic-starter',
              'sha256_checksum': 'deadbeef',
            },
          ),
          runtime: _FakeRuntime(),
        )));

        expect(find.byType(SignatureVerifiedChip), findsOneWidget);
      },
    );
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
    return <String, dynamic>{'ok': true, 'state': state};
  }
}
