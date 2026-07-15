import 'package:flutter/material.dart';
import '../controllers/script_controller.dart';
import '../models/script_record.dart';
import '../rust/native_bridge.dart';
import '../services/onboarding_progress_service.dart';
import '../services/script_integrity_service.dart';
import '../services/script_runner.dart';
import '../theme/app_design_system.dart';
import 'script_app_host.dart';
import 'script_leading_icon.dart';

class ScriptExecutionBottomSheet extends StatefulWidget {
  const ScriptExecutionBottomSheet({
    super.key,
    required this.script,
    required this.runtime,
    this.onExpand,
  });

  final ScriptRecord script;
  final IScriptAppRuntime runtime;
  final VoidCallback? onExpand;

  @override
  State<ScriptExecutionBottomSheet> createState() =>
      _ScriptExecutionBottomSheetState();
}

class _ScriptExecutionBottomSheetState
    extends State<ScriptExecutionBottomSheet> {
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.7,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppDesignSystem.sheetBorderRadius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: bottomPadding + 16,
              ),
              child: ScriptAppHost(
                runtime: widget.runtime,
                script: widget.script.bundle,
                initialArg: const <String, dynamic>{},
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          // W7-19: render the script's artwork (imageUrl) when present, with
          // the emoji/📦 as the load-failure fallback — mirrors the list tile
          // via the shared ScriptLeadingIcon. Previously this always showed
          // the emoji (hard-coded 📦 for marketplace installs).
          ScriptLeadingIcon(
            iconUrl: widget.script.imageUrl,
            emoji: widget.script.emoji,
            isMarketplace: widget.script.isFromMarketplace,
            radius: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.script.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_full),
            onPressed: widget.onExpand,
            tooltip: 'Expand to full screen',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }
}

Future<void> showScriptExecutionBottomSheet({
  required BuildContext context,
  required ScriptRecord script,
  IScriptAppRuntime? runtime,
  VoidCallback? onExpand,
}) async {
  final effectiveRuntime =
      runtime ?? ScriptAppRuntime(RustScriptBridge(const RustBridgeLoader()));

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ScriptExecutionBottomSheet(
      script: script,
      runtime: effectiveRuntime,
      onExpand: onExpand,
    ),
  );
}

/// Runs a local [script] end-to-end and shows its output — the single shared
/// implementation behind every "open a local script" entry point (the scripts
/// list one-tap run, and the download library tap).
///
/// 1. Verifies the SHA-256 checksum when the script carries one. Every
///    downloaded marketplace script does, so a corrupted or tampered bundle is
///    rejected *before* execution.
/// 2. Records the run (drives the run-count badge) and marks the first-script
///    onboarding step complete.
/// 3. Opens the shared [ScriptExecutionBottomSheet] (with [onExpand] wired to
///    the expand-to-full-screen action when supplied).
Future<void> runLocalScript(
  BuildContext context, {
  required ScriptRecord script,
  required ScriptController scriptController,
  IScriptAppRuntime? runtime,
  VoidCallback? onExpand,
}) async {
  final checksum = script.metadata['sha256_checksum'] as String?;
  if (checksum != null) {
    try {
      ScriptIntegrityService().verifyChecksum(
        script.bundle,
        checksum,
        scriptId: script.id,
      );
    } on ScriptIntegrityException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Script integrity check failed: ${e.message}'),
          backgroundColor: AppDesignSystem.errorColor,
        ),
      );
      return;
    }
  }

  await scriptController.recordScriptRun(script.id);
  await OnboardingProgressService().recordFirstScriptInteraction();

  if (!context.mounted) return;
  await showScriptExecutionBottomSheet(
    context: context,
    script: script,
    runtime: runtime,
    onExpand: onExpand,
  );
}
