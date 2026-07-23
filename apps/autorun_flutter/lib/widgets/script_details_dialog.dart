import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/marketplace_script.dart';
import '../models/script_review.dart';
import '../services/marketplace_open_api_service.dart';
import '../theme/app_design_system.dart';
import 'keyboard_shortcuts.dart';
import 'script_details_helpers.dart';
import 'script_details_reviews_tab.dart';
import 'trust_badges.dart';

class ScriptDetailsDialog extends StatefulWidget {
  final MarketplaceScript script;
  final VoidCallback? onDownload;
  final VoidCallback? onRun;
  final bool isDownloading;
  final bool isDownloaded;

  const ScriptDetailsDialog({
    super.key,
    required this.script,
    this.onDownload,
    this.onRun,
    this.isDownloading = false,
    this.isDownloaded = false,
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
  // UXR5-2: the language DETECTED from the bundle by the backend
  // (`/preview` → `ScriptPreview.language`). Drives the preview-pane badge so
  // it always reflects real content, never a hardcoded claim. `null` while
  // loading or when the language is unknown → the badge is hidden (honest:
  // prefer NO badge over a wrong one).
  String? _previewLanguage;

  bool _isLoadingReviews = false;
  List<ScriptReview> _reviews = [];
  String? _reviewsError;

  int _selectedTabIndex = 0;

  /// Tabs whose content has already been fetched at least once. The Details
  /// tab (index 0) is fetched eagerly in [initState] because it is the first
  /// thing the user sees; Reviews (1) is fetched lazily the first time the
  /// user selects it, then cached here so re-selecting the tab does not
  /// re-fetch (UX-5: kill the double-load on dialog open).
  final Set<int> _loadedTabs = <int>{0};

  @override
  void initState() {
    super.initState();
    // Only the Details/preview tab loads eagerly — Reviews loads on first
    // selection (see [_selectTab]).
    _loadScriptPreview();
  }

  /// Switches the visible tab and, for Reviews, triggers its fetch the first
  /// time it is selected. Subsequent selections reuse the cached result (no
  /// re-fetch).
  void _selectTab(int index) {
    setState(() => _selectedTabIndex = index);
    if (_loadedTabs.add(index)) {
      if (index == 1) {
        _loadReviews();
      }
    }
  }

  /// ← keyboard shortcut (UX-9 part B). Moves one tab left, clamped at the
  /// first tab. Goes through [_selectTab] so lazy-load (UX-5) fires exactly as
  /// it does for a mouse tap on the tab.
  void _goToPrevTab() {
    if (_selectedTabIndex > 0) {
      _selectTab(_selectedTabIndex - 1);
    }
  }

  /// → keyboard shortcut (UX-9 part B). Moves one tab right, clamped at the
  /// last tab. Lazy-load integration is identical to a tab tap.
  void _goToNextTab() {
    // W7-8: the Versions tab was removed (no /versions backend route); the
    // tab strip is now Details (0) + Reviews (1), so the right edge is 1.
    if (_selectedTabIndex < 1) {
      _selectTab(_selectedTabIndex + 1);
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
      _previewLanguage = null;
    });

    try {
      // UX-6: prefer the lightweight preview endpoint — it returns a server-side
      // CAPPED excerpt instead of the full bundle.
      final preview =
          await _marketplaceService.getScriptPreview(widget.script.id);
      setState(() {
        _scriptPreview = preview.preview;
        // UXR5-2: badge reflects the backend's content-based detection.
        _previewLanguage = preview.language;
        _isLoadingPreview = false;
      });
    } catch (error) {
      // The preview endpoint should always be available; reaching here means the
      // backend doesn't serve /preview yet (or a transport failure). Fall back
      // to the legacy full-download + take(50) path so the dialog still works
      // against an older backend. All scripts are free, so there's no paid-
      // content concern.
      if (!suppressDebugOutput) {
        debugPrint('Preview endpoint unavailable: $error');
      }
      await _loadScriptPreviewViaFullDownload();
    }
  }

  /// Legacy fallback (UX-6): the full-download + take(50) path the dialog used
  /// to always run. Only reachable for FREE scripts when the lightweight
  /// preview endpoint is unavailable. Paid scripts never enter this path.
  Future<void> _loadScriptPreviewViaFullDownload() async {
    try {
      final bundle = await _marketplaceService.downloadScript(widget.script.id);
      final lines = bundle.split('\n');
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

  /// UXR5-2: the preview-pane language badge. Reads the backend-DETECTED
  /// `language` (single source of truth: `ScriptLanguage::detect` in the
  /// backend). This method is only the display mapping:
  ///  - `typescript` → "TypeScript" badge.
  ///  - `lua` → "Legacy Lua" badge (amber) — stale; cannot run in the
  ///    TS/QuickJS runtime. Honest about what it is AND that it is unsupported.
  ///  - unknown / loading → no badge (prefer silence over a wrong claim).
  ///
  /// Returns `null` when no badge should render; callers place `null` where a
  /// `Widget` is expected via `_badgeOrEmpty`.
  Widget _buildLanguageBadge(BuildContext context) {
    final label = _languageBadgeLabel(_previewLanguage);
    if (label == null) {
      return const SizedBox.shrink();
    }
    final isLegacy = _previewLanguage == 'lua';
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isLegacy
                ? Theme.of(context).colorScheme.error
                : null,
          ),
    );
  }

  /// Maps the detected language identifier to a badge label, or `null` when no
  /// badge should be shown. Kept private + next to [_buildLanguageBadge] so the
  /// display mapping is the single frontend source (the DETECTION itself is
  /// single-sourced in the backend).
  static String? _languageBadgeLabel(String? language) {
    switch (language) {
      case 'typescript':
        return 'TypeScript';
      case 'lua':
        return 'Legacy Lua';
      default:
        return null;
    }
  }

  /// The primary CTA: Run if already downloaded, else Download.
  VoidCallback? get _primaryAction {
    if (widget.isDownloaded && widget.onRun != null) return widget.onRun;
    if (widget.onDownload != null) return widget.onDownload;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: DetailsDialogShortcuts(
        onPrevTab: _goToPrevTab,
        onNextTab: _goToNextTab,
        onPrimaryAction: _primaryAction,
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
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Icon(Icons.code,
                                                color: Theme.of(context).colorScheme.onPrimary),
                                  ),
                                )
                              : Icon(Icons.code, color: Theme.of(context).colorScheme.onPrimary),
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
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  // Trust badges (UX-H1) — surface the signed +
                                  // sandboxed promise at the decision moment.
                                  const SandboxedChip(),
                                  if (widget.script.authorName != null &&
                                      widget.script.authorName!.isNotEmpty)
                                    SignedByChip(
                                      author: widget.script.authorName!,
                                      verified: widget.script
                                          .author?.isVerifiedDeveloper ??
                                          false,
                                    ),
                                  if (widget.script.uploadSignature != null &&
                                      widget.script.uploadSignature!.isNotEmpty)
                                    const SignatureVerifiedChip(),

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
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Close button. Tooltip surfaces the Esc binding so the
                        // shortcut is discoverable without the help sheet.
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          tooltip: 'Close (Esc)',
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
                          // W7-8: only Details (0) + Reviews (1) remain. The
                          // Versions tab (was index 2) was removed — the
                          // backend ships no `/versions` route, so the tab
                          // was permanently empty. Restore it together with
                          // a `/versions` backend route.
                          child: _selectedTabIndex == 0
                              ? (isNarrow
                                  ? _buildNarrowLayout()
                                  : _buildWideLayout())
                              : ScriptDetailsReviewsTab(
                                  script: widget.script,
                                  reviews: _reviews,
                                  isLoadingReviews: _isLoadingReviews,
                                  reviewsError: _reviewsError,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
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
                                            _buildLanguageBadge(context),
                                            const Spacer(),
                                            IconButton(
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(
                                                    text:
                                                        _scriptPreview ?? ''));
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'Preview copied to clipboard')),
                                                );
                                              },
                                              icon: const Icon(Icons.copy,
                                                  size: 16),
                                              visualDensity:
                                                  VisualDensity.compact,
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
        //
        // NF-1 (Round-6 UX review): the right-panel `Column` historically
        // overflowed by up to ~92px at small window heights (a non-flex
        // `Column` doesn't scroll — it clips with the yellow/black stripe).
        // The wrap below is the standard "scroll when too big, fill when too
        // small" pattern (same one `_buildPreviewGatedPane` uses):
        //   LayoutBuilder → SingleChildScrollView → ConstrainedBox(minHeight)
        //   → IntrinsicHeight → Column.
        // At normal window heights the inner `Spacer` still pushes the
        // "Compatible Canisters" block to the bottom of the panel (visually
        // identical to before). At small heights the `SingleChildScrollView`
        // lets the user scroll instead of clipping.
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          // Primary action: Buy CTA for paid + not-purchased
                          // scripts, Download for free or already-purchased
                          // scripts.
                          if (_buildPrimaryAction() case final action?) ...[
                            action,
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
                            formatDate(widget.script.updatedAt),
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
                              return _buildCanisterIdRow(canisterId);
                            }),
                            if (widget.script.canisterIds.length > 3)
                              Text(
                                '... and ${widget.script.canisterIds.length - 3} more',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontStyle: FontStyle.italic,
                                    ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
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
          // Primary action at the top on mobile
          if (_buildPrimaryAction() case final action?) ...[
            action,
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
            formatDate(widget.script.updatedAt),
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
                                    _buildLanguageBadge(context),
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
              return _buildCanisterIdRow(canisterId);
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

  /// The primary action button for the dialog:
  /// - Run if already downloaded + [onRun] provided.
  /// - Download otherwise (all scripts are free).
  ///
  /// Extracted so the wide + narrow layouts render the SAME button (DRY).
  Widget? _buildPrimaryAction() {
    // Run: shown when the script has already been downloaded and a Run
    // callback is available.
    if (widget.isDownloaded && widget.onRun != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.onRun,
          icon: const Icon(Icons.play_arrow, size: 20),
          label: const Text(
            'Run',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppDesignSystem.successColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      );
    }

    // Download.
    if (widget.onDownload != null) {
      return SizedBox(
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
                  widget.isDownloaded ? Icons.check_circle : Icons.download,
                  size: 20,
                ),
          label: Text(
            widget.isDownloading
                ? 'Downloading...'
                : widget.isDownloaded
                    ? 'Downloaded ✓'
                    : 'Download',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: widget.isDownloaded
                ? AppDesignSystem.successColor
                : Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      );
    }

    return null;
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

  /// W6-8: a "Compatible Canisters" id row. The OLD code clipped ids to
  /// `• ryjl3-tyaaa-aaaaa-aa…` so the user could neither read nor copy the full
  /// id. Now the FULL id is shown in a monospace font (wrapping when needed),
  /// and tapping the row copies it to the clipboard with a "Copied" SnackBar —
  /// mirroring the copy affordances on the Account screen. A small copy icon
  /// signals the row is actionable.
  Widget _buildCanisterIdRow(String canisterId) {
    return InkWell(
      key: ValueKey('canister_id_$canisterId'),
      onTap: () {
        Clipboard.setData(ClipboardData(text: canisterId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Canister ID copied to clipboard')),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(Icons.copy_rounded,
                size: 12, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                canisterId,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            ),
          ],
        ),
      ),
    );
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
      // Surface the ←/→ tab-traversal binding on hover so the shortcut is
      // discoverable without opening the ? help sheet (UX-9 part B).
        child: Tooltip(
          message: 'Switch tabs with ← / → arrows',
          child: Row(
            // W7-8: only Details + Reviews — the Versions tab was removed
            // (no /versions backend route; the tab was permanently empty).
            children: [
              _buildTab('Details', 0),
              _buildTab('Reviews', 1),
            ],
          ),
        ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _selectTab(index),
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
}
