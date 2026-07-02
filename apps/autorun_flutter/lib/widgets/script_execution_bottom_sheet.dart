import 'package:flutter/material.dart';
import '../models/script_record.dart';
import '../rust/native_bridge.dart';
import '../services/script_runner.dart';
import '../theme/app_design_system.dart';
import 'script_app_host.dart';

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
    final emoji = (widget.script.emoji?.isNotEmpty ?? false)
        ? widget.script.emoji!
        : '📜';

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
          Text(
            emoji,
            style: const TextStyle(fontSize: 20),
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
