import 'package:flutter/material.dart';

import '../controllers/identity_controller.dart';
import '../models/identity_record.dart';
import '../models/script_record.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/script_signature_service.dart';
import '../utils/principal.dart';
import '../widgets/identity_scope.dart';
import '../widgets/identity_switcher_sheet.dart';
import '../widgets/identity_profile_sheet.dart';
import '../models/identity_profile.dart';
import '../widgets/script_editor.dart';
import 'error_display.dart';

class QuickUploadDialog extends StatefulWidget {
  final ScriptRecord? script; // Optional script to pre-fill from
  final String? preFilledTitle;
  final String? preFilledCode;
  final IdentityController? identityController;
  final MarketplaceOpenApiService? marketplaceService;

  const QuickUploadDialog({
    super.key,
    this.script,
    this.preFilledTitle,
    this.preFilledCode,
    this.identityController,
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
  late final TextEditingController _authorController;
  late final TextEditingController _tagsController;
  late final TextEditingController _priceController;

  String _selectedCategory = 'Example';
  bool _isUploading = false;
  double _uploadProgress = 0.0; // Track upload progress 0.0 to 1.0
  String? _error;
  int _currentStep = 0; // 0 = form, 1 = code preview

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

  IdentityController _identityController(BuildContext context, {bool listen = true}) {
    return widget.identityController ?? IdentityScope.of(context, listen: listen);
  }

  @override
  void initState() {
    super.initState();

    _marketplaceService =
        widget.marketplaceService ?? MarketplaceOpenApiService();

    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _authorController = TextEditingController();
    _tagsController = TextEditingController();
    _priceController = TextEditingController(text: '0.0');

    _initializeFromScript();
  }

  void _initializeFromScript() {
    if (widget.script != null) {
      _titleController.text = widget.script!.title;
      _authorController.text = 'Anonymous Developer';

      // Auto-generate description from script analysis
      _generateDescriptionFromScript();

      // Auto-detect category from script content
      _detectCategoryFromScript();

      // Auto-generate tags from script content
      _generateTagsFromScript();
    } else if (widget.preFilledTitle != null) {
      _titleController.text = widget.preFilledTitle!;
      _authorController.text = 'Anonymous Developer';
    }
  }

  void _generateDescriptionFromScript() {
    // Generate a generic description since script source is not displayed
    String description =
        'A Lua script for automation and utility tasks. This script provides a user-friendly interface for managing various operations.';
    _descriptionController.text = description;
  }

  void _detectCategoryFromScript() {
    // Set default category since script source is not displayed
    _selectedCategory = 'Example';
  }

  void _generateTagsFromScript() {
    // Generate generic tags since script source is not displayed
    _tagsController.text = 'automation, utility';
  }

  String _generateLuaSource() {
    if (widget.script != null) {
      return widget.script!.luaSource;
    }
    if (widget.preFilledCode != null) {
      return widget.preFilledCode!;
    }
    // Generate default Lua script
    final title = _titleController.text.isNotEmpty
        ? _titleController.text
        : 'Untitled Script';
    final description = _descriptionController.text.isNotEmpty
        ? _descriptionController.text
        : 'A script for automation tasks';

    return '''-- $title
-- $description

function app_init()
  return {
    title = "$title",
    description = "$description"
  }
end

function app_view(state)
  return icp.message("Hello from $title!")
end

function app_update(state, action, params)
  return state
end''';
  }

  void _goToCodePreview() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _currentStep = 1;
      _error = null;
    });
  }

  void _goBackToForm() {
    setState(() {
      _currentStep = 0;
      _error = null;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _authorController.dispose();
    _tagsController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _uploadScript() async {
    // Validation is done in _goToCodePreview() before reaching this step
    final IdentityController controller =
        _identityController(context, listen: false);
    final IdentityRecord? identity = controller.activeIdentity;
    if (identity == null) {
      setState(() {
        _error = 'Select an identity from the session banner before uploading.';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _error = null;
    });

    try {
      // Simulate upload progress for better UX (files are small, so we fake it)
      final progressUpdates = [0.2, 0.4, 0.6];
      for (final progress in progressUpdates) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          setState(() {
            _uploadProgress = progress;
          });
        }
      }

      final String title = _titleController.text.trim();
      final String description = _descriptionController.text.trim();
      final List<String> tags = _tagsController.text
          .split(',')
          .map((String tag) => tag.trim())
          .where((String tag) => tag.isNotEmpty)
          .toList();
      final String authorName = _authorController.text.trim();
      final double price = double.tryParse(_priceController.text.trim()) ?? 0.0;
      const String version = '1.0.0';
      final String timestamp = DateTime.now().toUtc().toIso8601String();

      // Use the actual Lua source from the script, or pre-filled code, or generate default
      String luaSource;
      if (widget.script?.luaSource != null &&
          widget.script!.luaSource.isNotEmpty) {
        luaSource = widget.script!.luaSource;
      } else if (widget.preFilledCode != null &&
          widget.preFilledCode!.isNotEmpty) {
        luaSource = widget.preFilledCode!;
      } else {
        // Generate a default Lua script since API requires non-empty lua_source
        luaSource = '''-- Default Script
function init(arg)
  return {
    message = "Hello from $title!"
  }, {}
end

function view(state)
  return {
    type = "text",
    props = {
      text = state.message
    }
  }
end

function update(msg, state)
  return state, {}
end''';
      }

      // Update progress: signing
      if (mounted) {
        setState(() {
          _uploadProgress = 0.75;
        });
      }

      final String signature = await ScriptSignatureService.signScriptUpload(
        authorIdentity: identity,
        title: title,
        description: description,
        category: _selectedCategory,
        luaSource: luaSource,
        version: version,
        tags: tags,
        timestampIso: timestamp,
      );
      final String authorPrincipal = PrincipalUtils.textFromRecord(identity);

      // Update progress: uploading
      if (mounted) {
        setState(() {
          _uploadProgress = 0.9;
        });
      }

      await _marketplaceService.uploadScript(
        title: title,
        description: description,
        category: _selectedCategory,
        tags: tags,
        luaSource: luaSource,
        authorName: authorName,
        price: price,
        version: version,
        authorPrincipal: authorPrincipal,
        authorPublicKey: identity.publicKey,
        signature: signature,
        timestampIso: timestamp,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Script published successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $_error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
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
              child: _currentStep == 0
                  ? Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_error != null) ...[
                              ErrorDisplay(
                                error: _error!,
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
                          TextFormField(
                            controller: _authorController,
                            decoration: const InputDecoration(
                              labelText: 'Author Name *',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Author name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Identity context',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _buildIdentityCard(_identityController(context)),
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
                              labelText: 'Price (ICP) *',
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
                    ],
                  ),
                ),
              )
                  : _buildCodePreview(),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: _currentStep == 0
                  ? SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('quick-upload-next'),
                        onPressed: _goToCodePreview,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next: Review Code'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isUploading ? null : _goBackToForm,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Back'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
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
                                      color: Colors.white,
                                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                                    ),
                                  )
                                : const Icon(Icons.upload),
                            label: Text(_isUploading
                                ? 'Uploading ${(_uploadProgress * 100).toInt()}%'
                                : 'Upload to Marketplace'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodePreview() {
    final luaSource = _generateLuaSource();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            ErrorDisplay(
              error: _error!,
              onRetry: _isUploading ? null : _uploadScript,
              retryText: 'Retry upload',
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Review Generated Code',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'This is the Lua code that will be uploaded to the marketplace. Review it before publishing.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ScriptEditor(
              initialCode: luaSource,
              onCodeChanged: (_) {}, // Read-only, ignore changes
              language: 'lua',
              readOnly: true,
              showIntegrations: false,
              minLines: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard(IdentityController controller) {
    final IdentityRecord? identity = controller.activeIdentity;
    if (identity == null) {
      return Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No identity selected',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Publishing requires a signing identity. Switch identities from the button below.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _openIdentitySwitcher,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Choose identity'),
              ),
            ],
          ),
        ),
      );
    }
    final bool isComplete = controller.isProfileComplete(identity);
    final String principal = PrincipalUtils.textFromRecord(identity);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              identity.label.isEmpty ? 'Untitled identity' : identity.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              principal,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _openIdentitySwitcher,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Switch identity'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _promptForProfile(controller, identity),
                  icon: Icon(isComplete ? Icons.visibility_outlined : Icons.edit_note),
                  label: Text(isComplete ? 'View profile' : 'Complete profile'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openIdentitySwitcher() async {
    final IdentityController controller = _identityController(context, listen: false);
    final IdentitySwitcherResult? result =
        await showIdentitySwitcherSheet(context: context, controller: controller);
    if (!mounted || result == null) {
      return;
    }
    if (result.openIdentityManager) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Open the Identities tab on the home screen to manage identities.'),
        ),
      );
      return;
    }
    await controller.setActiveIdentity(result.identityId);
    if (mounted) {
      setState(() {
        _error = null;
      });
    }
    if (!mounted || result.identityId == null) {
      return;
    }
    final IdentityRecord? identity = controller.findById(result.identityId!);
    if (identity != null) {
      await _promptForProfile(controller, identity);
    }
  }

  Future<void> _promptForProfile(
    IdentityController controller,
    IdentityRecord identity,
  ) async {
    IdentityProfile? profile = controller.profileForRecord(identity);

    // Show loading indicator while fetching profile from server
    if (profile == null && mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading profile...'),
                ],
              ),
            ),
          ),
        ),
      );

      profile = await controller.ensureProfileLoaded(identity);

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
      }
    }

    if (!mounted) {
      return;
    }
    if (profile?.isComplete == true) {
      return;
    }
    final IdentityProfileDraft? draft = await showIdentityProfileSheet(
      context: context,
      identity: identity,
      existingProfile: profile,
    );
    if (!mounted) {
      return;
    }
    if (draft == null) {
      return;
    }
    await controller.saveProfile(identity: identity, draft: draft);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Identity profile saved')),
    );
  }
}
