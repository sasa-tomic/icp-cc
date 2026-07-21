import 'package:flutter/material.dart';

import '../controllers/profile_controller.dart';
import '../models/profile_keypair.dart';
import '../models/script_record.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/script_signature_service.dart';
import '../services/script_validation_service.dart';
import '../theme/app_design_system.dart';
import '../utils/friendly_error.dart';
import '../utils/principal.dart';
import '../widgets/profile_scope.dart';
import '../widgets/script_editor.dart';
import 'error_display.dart';

class QuickUploadDialog extends StatefulWidget {
  final ScriptRecord? script; // Optional script to pre-fill from
  final String? preFilledTitle;
  final String? preFilledCode;
  final ProfileController? profileController;
  final MarketplaceOpenApiService? marketplaceService;

  const QuickUploadDialog({
    super.key,
    this.script,
    this.preFilledTitle,
    this.preFilledCode,
    this.profileController,
    this.marketplaceService,
  });

  @override
  State<QuickUploadDialog> createState() => _QuickUploadDialogState();
}

class _QuickUploadDialogState extends State<QuickUploadDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final MarketplaceOpenApiService _marketplaceService;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;
  late final TextEditingController _priceController;

  String _selectedCategory = 'Example';
  bool _isUploading = false;
  /// Upload phase indicator. `null` = indeterminate (preparing); otherwise a
  /// phase checkpoint in [0, 1]: 0.5 = signing, 0.75 = uploading. Drives the
  /// CircularProgressIndicator value + the phase label. Never faked — only
  /// updated at real phase transitions.
  double? _uploadProgress;
  String? _error;
  Object? _errorObject;
  // Sandbox-validation failures are shown verbatim (with the specific
  // rejected primitive) so authors can fix the bundle before publishing.
  String? _validationError;

  final List<String> _availableCategories = [
    'Example',
    'Uncategorized',
    'Gaming',
    'Finance',
    'DeFi',
    'NFT',
    'Social',
    'Utilities',
    'Development',
    'Education',
    'Entertainment',
    'Business',
  ];

  ProfileController _profileController(BuildContext context,
      {bool listen = true}) {
    return widget.profileController ?? ProfileScope.of(context, listen: listen);
  }

  @override
  void initState() {
    super.initState();

    _marketplaceService =
        widget.marketplaceService ?? MarketplaceOpenApiService();

    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _tagsController = TextEditingController();
    _priceController = TextEditingController(text: '0.0');

    _initializeFromScript();
  }

  void _initializeFromScript() {
    if (widget.script != null) {
      _titleController.text = widget.script!.title;

      // Auto-generate description from script analysis
      _generateDescriptionFromScript();

      // Auto-detect category from script content
      _detectCategoryFromScript();

      // Auto-generate tags from script content
      _generateTagsFromScript();
    } else if (widget.preFilledTitle != null) {
      _titleController.text = widget.preFilledTitle!;
    }
  }

  void _generateDescriptionFromScript() {
    if (widget.script != null && widget.script!.bundle.isNotEmpty) {
      final lines = widget.script!.bundle.split('\n');
      final contentLines = lines
          .where(
              (line) => !line.trim().startsWith('//') && line.trim().isNotEmpty)
          .take(3)
          .toList();
      if (contentLines.isNotEmpty) {
        _descriptionController.text =
            'A TypeScript script with ${contentLines.length} main functions: ${widget.script!.title}';
        return;
      }
    }
    _descriptionController.text =
        'A TypeScript script for automation and utility tasks.';
  }

  void _detectCategoryFromScript() {
    _selectedCategory = 'Example';
  }

  void _generateTagsFromScript() {
    if (widget.script != null) {
      _tagsController.text = 'typescript, script';
      return;
    }
    _tagsController.text = 'automation, utility';
  }

  String _getBundle() {
    if (widget.script != null) {
      return widget.script!.bundle;
    }
    if (widget.preFilledCode != null) {
      return widget.preFilledCode!;
    }
    final title = _titleController.text.isNotEmpty
        ? _titleController.text
        : 'Untitled Script';
    final description = _descriptionController.text.isNotEmpty
        ? _descriptionController.text
        : 'A script for automation tasks';

    return '''// $title
// $description
"use strict";
(() => {
  function init() {
    return {
      state: { title: "$title", description: "$description" },
      effects: []
    };
  }
  function view(state) {
    return icp_message({ text: "Hello from " + state.title + "!", type: "info" });
  }
  function update(_msg, state) {
    return { state: state, effects: [] };
  }
  globalThis.init = init;
  globalThis.view = view;
  globalThis.update = update;
})();
''';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _uploadScript() async {
    // Validate the form first. The publish flow is now a single page, so the
    // primary action owns validation (previously it lived in the "Next" step).
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final ProfileController controller =
        _profileController(context, listen: false);
    final ProfileKeypair? keypair = controller.activeKeypair;
    if (keypair == null) {
      setState(() {
        _error = 'No keypair selected. Go to the Profiles tab to select one.';
      });
      return;
    }

    // Resolve the bundle that will be published before doing any signing work.
    final String bundle;
    if (widget.script?.bundle != null && widget.script!.bundle.isNotEmpty) {
      bundle = widget.script!.bundle;
    } else if (widget.preFilledCode != null &&
        widget.preFilledCode!.isNotEmpty) {
      bundle = widget.preFilledCode!;
    } else {
      // Generate a default TS bundle since API requires non-empty bundle
      bundle = _getBundle();
    }

    // Safety gate: refuse to sign/upload a bundle that fails the authoritative
    // sandbox validator. Without this, a user could publish a bundle containing
    // eval()/Intl.*/ESM imports that the runtime only rejects later (or never).
    final ValidationResult validation =
        await ScriptValidationService().validateScript(bundle);
    if (!validation.isValid) {
      final String bullets = validation.errors.isEmpty
          ? 'the bundle failed sandbox validation'
          : validation.errors.map((e) => '• $e').join('\n');
      setState(() {
        _validationError =
            'This script cannot be published because it failed sandbox validation:\n\n'
            '$bullets';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = null; // indeterminate while preparing
      _error = null;
      _errorObject = null;
      _validationError = null;
    });

    try {
      final String title = _titleController.text.trim();
      // Generate slug from title: lowercase, replace non-alphanumeric with hyphens
      final String slug = title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final String description = _descriptionController.text.trim();
      final List<String> tags = _tagsController.text
          .split(',')
          .map((String tag) => tag.trim())
          .where((String tag) => tag.isNotEmpty)
          .toList();
      final double price = double.tryParse(_priceController.text.trim()) ?? 0.0;
      const String version = '1.0.0';
      final String timestamp = DateTime.now().toUtc().toIso8601String();

      // Phase transition: signing the upload request.
      if (mounted) {
        setState(() {
          _uploadProgress = 0.5;
        });
      }

      final String signature = await ScriptSignatureService.signScriptUpload(
        authorKeypair: keypair,
        title: title,
        description: description,
        category: _selectedCategory,
        bundle: bundle,
        version: version,
        tags: tags,
        timestampIso: timestamp,
      );
      final String authorPrincipal = PrincipalUtils.textFromRecord(keypair);

      // Phase transition: uploading the signed request to the marketplace.
      if (mounted) {
        setState(() {
          _uploadProgress = 0.75;
        });
      }

      await _marketplaceService.uploadScript(
        slug: slug,
        title: title,
        description: description,
        category: _selectedCategory,
        tags: tags,
        bundle: bundle,
        price: price,
        version: version,
        authorPrincipal: authorPrincipal,
        authorPublicKey: keypair.publicKey,
        signature: signature,
        timestampIso: timestamp,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        AppDesignSystem.successSnackBar('Script published successfully!'),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _errorObject = e;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(e, context: 'Upload failed')),
            backgroundColor: AppDesignSystem.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = null;
        });
      }
    }
  }

  /// Phase label shown on the upload button while uploading. Drives from the
  /// real `_uploadProgress` checkpoints — never fabricated. `null`/`<0.5` is
  /// the preparing phase (form validation, bundle read), 0.5 is signing,
  /// 0.75 is the actual HTTP upload.
  String _uploadPhaseLabel() {
    final p = _uploadProgress;
    if (p == null || p < 0.5) return 'Preparing…';
    if (p < 0.75) return 'Signing…';
    return 'Uploading…';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        constraints: const BoxConstraints(
          minWidth: 800,
          maxWidth: 1200,
          minHeight: 600,
          maxHeight: 900,
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
                  Icon(
                    Icons.upload,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Upload to Marketplace',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        Text(
                          'Share your script with the community',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Form content
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_validationError != null) ...[
                        _buildValidationError(_validationError!),
                        const SizedBox(height: 16),
                      ],
                      if (_error != null) ...[
                        ErrorDisplay(
                          error: _error!,
                          errorObject: _errorObject,
                          onRetry: _isUploading ? null : _uploadScript,
                          retryText: 'Retry upload',
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Basic Information Section
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Basic Information',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: 'Title *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Title is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _descriptionController,
                            decoration: const InputDecoration(
                              labelText: 'Description *',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Description is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Keypair context',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _buildKeypairCard(_profileController(context)),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCategory,
                            decoration: const InputDecoration(
                              labelText: 'Category *',
                              border: OutlineInputBorder(),
                            ),
                            items: _availableCategories.map((category) {
                              return DropdownMenuItem(
                                value: category,
                                child: Text(category),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedCategory = value;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _tagsController,
                            decoration: const InputDecoration(
                              labelText: 'Tags (comma-separated)',
                              border: OutlineInputBorder(),
                              helperText: 'e.g., automation, defi, gaming',
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _priceController,
                            decoration: const InputDecoration(
                              labelText: 'Price (USD) *',
                              border: OutlineInputBorder(),
                              helperText: 'Set to 0 for free scripts',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Price is required';
                              }
                              final price = double.tryParse(value.trim());
                              if (price == null || price < 0) {
                                return 'Invalid price';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Inline collapsible code preview (collapsed by
                      // default) — replaces the old "Next: Review Code"
                      // step so publishing is a single action.
                      _buildCodePreviewExpander(),
                    ],
                  ),
                ),
              ),
            ),

            // Single primary action — the form and code preview live on one
            // page now, so there is no "Next" step.
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('quick-upload-submit'),
                  onPressed: _isUploading ? null : _uploadScript,
                  icon: _isUploading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            value: _uploadProgress,
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                            backgroundColor:
                                Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.3),
                          ),
                        )
                      : const Icon(Icons.upload),
                  label: Text(_isUploading
                      ? _uploadPhaseLabel()
                      : 'Upload to Marketplace'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Inline, collapsed-by-default code preview shown on the form page. Authors
  /// wrote the code, so the review step is opt-in rather than a forced extra
  /// tap; expanding it reveals the read-only TypeScript bundle.
  Widget _buildCodePreviewExpander() {
    return ExpansionTile(
      key: const Key('quick-upload-code-preview'),
      title: const Text('Preview code (optional)'),
      subtitle: Text(
        'Review the TypeScript bundle that will be published',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      leading: Icon(
        Icons.code,
        color: Theme.of(context).colorScheme.primary,
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8),
      children: [
        SizedBox(
          height: 320,
          child: ScriptEditor(
            initialCode: _getBundle(),
            onCodeChanged: (_) {}, // Read-only, ignore changes
            readOnly: true,
            showIntegrations: false,
            minLines: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildValidationError(String message) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('quick-upload-validation-error'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypairCard(ProfileController controller) {
    final ProfileKeypair? keypair = controller.activeKeypair;
    if (keypair == null) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No keypair selected. Go to the Profiles tab to select one.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Each keypair has an account (draft or registered)
    final String principal = PrincipalUtils.textFromRecord(keypair);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(
                Icons.verified_user,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    keypair.label.isEmpty ? 'Untitled keypair' : keypair.label,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    principal.length > 20
                        ? '${principal.substring(0, 20)}...'
                        : principal,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
