import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/marketplace_script.dart';
import '../models/purchase_record.dart';
import '../services/marketplace_open_api_service.dart';
import 'diff_viewer_dialog.dart';

class ScriptDetailsDialog extends StatefulWidget {
  final MarketplaceScript script;
  final VoidCallback? onDownload;
  final bool isDownloading;
  final bool isDownloaded;
  final String? installedVersion;
  final String? installedScriptSource;
  final void Function(String version)? onInstallVersion;

  const ScriptDetailsDialog({
    super.key,
    required this.script,
    this.onDownload,
    this.isDownloading = false,
    this.isDownloaded = false,
    this.installedVersion,
    this.installedScriptSource,
    this.onInstallVersion,
  });

  @override
  State<ScriptDetailsDialog> createState() => _ScriptDetailsDialogState();
}

class _ScriptDetailsDialogState extends State<ScriptDetailsDialog> {
  final MarketplaceOpenApiService _marketplaceService =
      MarketplaceOpenApiService();
  bool _isLoadingPreview = false;
  String? _scriptPreview;
  String? _previewError;

  bool _isLoadingReviews = false;
  List<ScriptReview> _reviews = [];
  String? _reviewsError;

  bool _isLoadingVersions = false;
  List<ScriptVersion> _versions = [];
  String? _versionsError;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadScriptPreview();
    _loadReviews();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    setState(() {
      _isLoadingVersions = true;
      _versionsError = null;
    });

    try {
      final versions =
          await _marketplaceService.getScriptVersions(widget.script.id);
      setState(() {
        _versions = versions;
        _isLoadingVersions = false;
      });
    } catch (e) {
      setState(() {
        _versionsError = 'Failed to load versions: $e';
        _isLoadingVersions = false;
      });
    }
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoadingReviews = true;
      _reviewsError = null;
    });

    try {
      final reviews =
          await _marketplaceService.getScriptReviews(widget.script.id);
      setState(() {
        _reviews = reviews;
        _isLoadingReviews = false;
      });
    } catch (e) {
      setState(() {
        _reviewsError = 'Failed to load reviews: $e';
        _isLoadingReviews = false;
      });
    }
  }

  Future<void> _loadScriptPreview() async {
    setState(() {
      _isLoadingPreview = true;
      _previewError = null;
    });

    try {
      final luaSource =
          await _marketplaceService.downloadScript(widget.script.id);
      // Show first 50 lines as preview
      final lines = luaSource.split('\n');
      final previewLines = lines.take(50).join('\n');
      setState(() {
        _scriptPreview = previewLines;
        _isLoadingPreview = false;
      });
    } catch (e) {
      setState(() {
        _previewError = 'Failed to load preview: $e';
        _isLoadingPreview = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;

          return Container(
            width: isNarrow
                ? MediaQuery.of(context).size.width * 0.95
                : MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.85,
            constraints: BoxConstraints(
              minWidth: isNarrow ? 300 : 600,
              maxWidth: isNarrow ? 400 : 900,
              minHeight: 500,
              maxHeight: 800,
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Script icon
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: widget.script.iconUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  widget.script.iconUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.code,
                                          color: Colors.white),
                                ),
                              )
                            : const Icon(Icons.code, color: Colors.white),
                      ),
                      const SizedBox(width: 16),

                      // Script info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.script.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'by ${widget.script.authorName}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                // Category badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    widget.script.category,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Price
                                if (widget.script.price > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '\$${widget.script.price.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: Colors.green[800],
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[100],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'FREE',
                                      style: TextStyle(
                                        color: Colors.blue[800],
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),

                                const SizedBox(width: 8),

                                // Rating
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star,
                                        size: 16, color: Colors.amber),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.script.rating > 0
                                          ? widget.script.rating
                                              .toStringAsFixed(1)
                                          : 'No rating',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Close button
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
                  child: Column(
                    children: [
                      _buildTabBar(),
                      Expanded(
                        child: _selectedTabIndex == 0
                            ? (isNarrow
                                ? _buildNarrowLayout()
                                : _buildWideLayout())
                            : _selectedTabIndex == 1
                                ? _buildReviewsTab()
                                : _buildVersionsTab(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        // Left panel - Script info and preview
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description
                if (widget.script.description.isNotEmpty) ...[
                  Text(
                    'Description',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.script.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                ],

                // Tags
                if (widget.script.tags.isNotEmpty) ...[
                  Text(
                    'Tags',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: widget.script.tags.map((tag) {
                      return Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],

                // Code preview
                Text(
                  'Code Preview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.2),
                      ),
                    ),
                    child: _isLoadingPreview
                        ? const Center(
                            child: CircularProgressIndicator(),
                          )
                        : _previewError != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    _previewError!,
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Preview header
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.5),
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        topRight: Radius.circular(8),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Lua',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(
                                                text: _scriptPreview ?? ''));
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Preview copied to clipboard')),
                                            );
                                          },
                                          icon:
                                              const Icon(Icons.copy, size: 16),
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Copy preview',
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Preview content
                                  Expanded(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(12),
                                      child: SelectableText(
                                        _scriptPreview ?? '',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontFamily: 'monospace',
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const VerticalDivider(width: 1),

        // Right panel - Actions and stats
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Download button
                if (widget.onDownload != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          widget.isDownloading ? null : widget.onDownload,
                      icon: widget.isDownloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              widget.isDownloaded
                                  ? Icons.check_circle
                                  : Icons.download,
                              size: 20,
                            ),
                      label: Text(
                        widget.isDownloading
                            ? 'Downloading...'
                            : widget.isDownloaded
                                ? 'Downloaded ✓'
                                : widget.script.price > 0
                                    ? 'Purchase \$${widget.script.price.toStringAsFixed(2)}'
                                    : 'Download FREE',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.isDownloaded
                            ? Colors.green
                            : widget.script.price > 0
                                ? Colors.orange
                                : Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Stats
                const Text(
                  'Statistics',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                _buildStatItem(
                  context,
                  'Downloads',
                  '${widget.script.downloads}',
                  Icons.download,
                ),

                _buildStatItem(
                  context,
                  'Rating',
                  widget.script.rating > 0
                      ? '${widget.script.rating.toStringAsFixed(1)}/5.0'
                      : 'No rating',
                  Icons.star,
                ),

                if (widget.script.version != null)
                  _buildStatItem(
                    context,
                    'Version',
                    widget.script.version!,
                    Icons.tag,
                  ),

                _buildStatItem(
                  context,
                  'Updated',
                  _formatDate(widget.script.updatedAt),
                  Icons.update,
                ),

                const Spacer(),

                // Additional info
                if (widget.script.canisterIds.isNotEmpty) ...[
                  const Text(
                    'Compatible Canisters',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...widget.script.canisterIds.take(3).map((canisterId) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• ${canisterId.length > 20 ? '${canisterId.substring(0, 20)}...' : canisterId}',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                  if (widget.script.canisterIds.length > 3)
                    Text(
                      '... and ${widget.script.canisterIds.length - 3} more',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Download button at the top on mobile
          if (widget.onDownload != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.isDownloading ? null : widget.onDownload,
                icon: widget.isDownloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        widget.isDownloaded
                            ? Icons.check_circle
                            : Icons.download,
                        size: 20,
                      ),
                label: Text(
                  widget.isDownloading
                      ? 'Downloading...'
                      : widget.isDownloaded
                          ? 'Downloaded ✓'
                          : widget.script.price > 0
                              ? 'Purchase \$${widget.script.price.toStringAsFixed(2)}'
                              : 'Download FREE',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.isDownloaded
                      ? Colors.green
                      : widget.script.price > 0
                          ? Colors.orange
                          : Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Description
          if (widget.script.description.isNotEmpty) ...[
            Text(
              'Description',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.script.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
          ],

          // Tags
          if (widget.script.tags.isNotEmpty) ...[
            Text(
              'Tags',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.script.tags.map((tag) {
                return Chip(
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          // Stats
          Text(
            'Statistics',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  'Downloads',
                  '${widget.script.downloads}',
                  Icons.download,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Rating',
                  widget.script.rating > 0
                      ? '${widget.script.rating.toStringAsFixed(1)}/5.0'
                      : 'No rating',
                  Icons.star,
                ),
              ),
            ],
          ),

          if (widget.script.version != null)
            _buildStatItem(
              context,
              'Version',
              widget.script.version!,
              Icons.tag,
            ),

          _buildStatItem(
            context,
            'Updated',
            _formatDate(widget.script.updatedAt),
            Icons.update,
          ),

          const SizedBox(height: 20),

          // Code preview
          Text(
            'Code Preview',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 300, // Fixed height for mobile preview
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2),
              ),
            ),
            child: _isLoadingPreview
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _previewError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _previewError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Preview header
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Lua',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(
                                        text: _scriptPreview ?? ''));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Preview copied to clipboard')),
                                    );
                                  },
                                  icon: const Icon(Icons.copy, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Copy preview',
                                ),
                              ],
                            ),
                          ),

                          // Preview content
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: SelectableText(
                                _scriptPreview ?? '',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
          ),

          const SizedBox(height: 20),

          // Additional info
          if (widget.script.canisterIds.isNotEmpty) ...[
            Text(
              'Compatible Canisters',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            ...widget.script.canisterIds.take(3).map((canisterId) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${canisterId.length > 20 ? '${canisterId.substring(0, 20)}...' : canisterId}',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
            if (widget.script.canisterIds.length > 3)
              Text(
                '... and ${widget.script.canisterIds.length - 3} more',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(
      BuildContext context, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} year${(difference.inDays / 365).floor() == 1 ? '' : 's'} ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() == 1 ? '' : 's'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildTab('Details', 0),
          _buildTab('Reviews', 1),
          _buildTab('Versions', 2),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewsTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRatingSummary(),
          const SizedBox(height: 20),
          Expanded(
            child: _buildReviewsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                widget.script.rating > 0
                    ? widget.script.rating.toStringAsFixed(1)
                    : '-',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return Icon(
                    index < widget.script.rating.round()
                        ? Icons.star
                        : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.script.reviewCount} reviews',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: _buildRatingDistribution(),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingDistribution() {
    final distribution = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final review in _reviews) {
      if (review.rating >= 1 && review.rating <= 5) {
        distribution[review.rating] = (distribution[review.rating] ?? 0) + 1;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [5, 4, 3, 2, 1].map((star) {
        final count = distribution[star] ?? 0;
        final percentage = _reviews.isEmpty ? 0.0 : count / _reviews.length;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text(
                '$star',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
              Icon(Icons.star, size: 12, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildReviewsList() {
    if (_isLoadingReviews) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reviewsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _reviewsError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_reviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.rate_review_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No reviews yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to review this script!',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _reviews.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final review = _reviews[index];
        return _buildReviewItem(review);
      },
    );
  }

  Widget _buildReviewItem(ScriptReview review) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return Icon(
                    index < review.rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  );
                }),
              ),
              const SizedBox(width: 8),
              if (review.isVerifiedPurchase) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified,
                        size: 12,
                        color: Colors.green[700],
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Verified',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              Text(
                _formatDate(review.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVersionsTab() {
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
    if (_isLoadingVersions) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_versionsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _versionsError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_versions.isEmpty) {
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
      itemCount: _versions.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final version = _versions[index];
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
                  ? Colors.green.withValues(alpha: 0.1)
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
                  ? Colors.green
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
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Text(
                          'Installed',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
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
                      _formatDate(version.createdAt),
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
