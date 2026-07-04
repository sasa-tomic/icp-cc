import 'package:flutter/material.dart';

import '../models/marketplace_script.dart';
import '../services/marketplace_open_api_service.dart';
import '../theme/app_design_system.dart';
import 'diff_viewer_dialog.dart';
import 'script_details_helpers.dart';

/// Versions tab of [ScriptDetailsDialog].
///
/// The parent dialog owns the version-list load lifecycle (it fires
/// `_loadVersions()` lazily the first time this tab is selected and passes the
/// result here via these fields). This widget is stateful only because
/// [_showVersionDiff] runs an async download + dialog sequence that needs
/// `mounted` guards. It owns its own [MarketplaceOpenApiService] handle — that
/// class is a process-wide singleton (factory constructor), so this is the
/// *same* instance the parent uses; no behaviour change.
///
/// Extracted verbatim from `script_details_dialog.dart` (TD-11). The only
/// edits are: leading `_` dropped from the helpers that became this widget's
/// private methods, the list/state fields accessed via `widget.` (they moved
/// from the parent State to this Widget), and `_formatDate` → `formatDate`.
class ScriptDetailsVersionsTab extends StatefulWidget {
  const ScriptDetailsVersionsTab({
    super.key,
    required this.script,
    required this.versions,
    required this.isLoadingVersions,
    this.versionsError,
    this.installedVersion,
    this.installedScriptSource,
    this.onInstallVersion,
  });

  final MarketplaceScript script;
  final List<ScriptVersion> versions;
  final bool isLoadingVersions;
  final String? versionsError;
  final String? installedVersion;
  final String? installedScriptSource;
  final void Function(String version)? onInstallVersion;

  @override
  State<ScriptDetailsVersionsTab> createState() =>
      _ScriptDetailsVersionsTabState();
}

class _ScriptDetailsVersionsTabState extends State<ScriptDetailsVersionsTab> {
  final MarketplaceOpenApiService _marketplaceService =
      MarketplaceOpenApiService();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version History',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'All available versions of this script',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _buildVersionsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionsList() {
    if (widget.isLoadingVersions) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.versionsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.versionsError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (widget.versions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No version history',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Only one version available',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: widget.versions.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final version = widget.versions[index];
        return _buildVersionItem(version);
      },
    );
  }

  Widget _buildVersionItem(ScriptVersion version) {
    final isInstalled = widget.installedVersion == version.version;
    final canInstall =
        widget.onInstallVersion != null && !version.isLatest && !isInstalled;
    final canViewChanges = !isInstalled;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isInstalled
                  ? AppDesignSystem.successColor.withValues(alpha: 0.1)
                  : Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isInstalled
                  ? Icons.check_circle
                  : version.isLatest
                      ? Icons.new_releases
                      : Icons.code,
              color: isInstalled
                  ? AppDesignSystem.successColor
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'v${version.version}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (version.isLatest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Latest',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                    if (isInstalled) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppDesignSystem.successColor
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border:
                              Border.all(color: AppDesignSystem.successColor),
                        ),
                        child: Text(
                          'Installed',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppDesignSystem.successDark,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.download,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${version.downloads}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formatDate(version.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                if (version.changelog != null &&
                    version.changelog!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    version.changelog!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (canViewChanges)
            TextButton(
              onPressed: () => _showVersionDiff(version),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('View Changes'),
            ),
          if (canInstall)
            TextButton(
              onPressed: () => widget.onInstallVersion!(version.version),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Install'),
            ),
        ],
      ),
    );
  }

  Future<void> _showVersionDiff(ScriptVersion version) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final newSource = await _marketplaceService.downloadScript(
        widget.script.id,
        version: version.version,
      );

      final oldSource = widget.installedScriptSource ?? '';
      final oldVersion = widget.installedVersion ?? 'New Install';

      if (!mounted) return;
      Navigator.of(context).pop();

      showDialog(
        context: context,
        builder: (context) => DiffViewerDialog(
          oldCode: oldSource,
          newCode: newSource,
          oldVersion: oldVersion,
          newVersion: version.version,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load version diff: $e')),
      );
    }
  }
}
