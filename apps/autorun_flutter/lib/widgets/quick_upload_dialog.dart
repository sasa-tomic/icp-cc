import 'package:flutter/material.dart';

import '../controllers/identity_controller.dart';
import '../models/identity_record.dart';
import '../models/script_record.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/script_signature_service.dart';
import '../services/secure_identity_repository.dart';
import '../utils/principal.dart';
import 'error_display.dart';
import 'identity_selector.dart';

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
  late final IdentityController _identityController;
  late final bool _ownsIdentityController;

  List<IdentityRecord> _identities = <IdentityRecord>[];
  IdentityRecord? _selectedIdentity;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _authorController;
  late final TextEditingController _tagsController;
  late final TextEditingController _priceController;

  String _selectedCategory = 'Example';
  bool _isUploading = false;
  String? _error;

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

  @override
  void initState() {
    super.initState();

    _marketplaceService =
        widget.marketplaceService ?? MarketplaceOpenApiService();
    _identityController = widget.identityController ??
        IdentityController(
          secureRepository: SecureIdentityRepository(),
        );
    _ownsIdentityController = widget.identityController == null;
    _identityController.addListener(_onIdentitiesChanged);
    _identityController.ensureLoaded();
    _identities = List<IdentityRecord>.from(_identityController.identities);

    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _authorController = TextEditingController();
    _tagsController = TextEditingController();
    _priceController = TextEditingController(text: '0.0');

    _initializeFromScript();
  }

  void _onIdentitiesChanged() {
    if (!mounted) {
      return;
    }
    final List<IdentityRecord> updated =
        List<IdentityRecord>.from(_identityController.identities);
    IdentityRecord? selected = _selectedIdentity;
    if (selected != null &&
        !updated.any((IdentityRecord identity) => identity.id == selected.id)) {
      selected = null;
    }
    setState(() {
      _identities = updated;
      _selectedIdentity = selected;
    });
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

  @override
  void dispose() {
    _identityController.removeListener(_onIdentitiesChanged);
    if (_ownsIdentityController) {
      _identityController.dispose();
    }
    _titleController.dispose();
    _descriptionController.dispose();
    _authorController.dispose();
    _tagsController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _uploadScript() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedIdentity == null) {
      setState(() {
        _error = identitySelectionErrorText;
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _error = null;
    });

    try {
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

      final IdentityRecord identity = _selectedIdentity!;
      final String signature = await ScriptSignatureService.signScriptUpload(
        authorIdentity: identity,
        title: title,
        description: description,
        category: _selectedCategory,
        luaSource: luaSource,
        version: version,
        tags: tags,
      );
      final String authorPrincipal = PrincipalUtils.textFromRecord(identity);

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
              child: Form(
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
                            'Author Identity (Required)',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Select an identity to sign this script. This is required to publish to the marketplace.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                          const SizedBox(height: 12),
                          IdentitySelectorField(
                            identities: _identities,
                            selectedIdentity: _selectedIdentity,
                            onChanged: (IdentityRecord? value) {
                              setState(() {
                                _selectedIdentity = value;
                                if (value != null &&
                                    _error == identitySelectionErrorText) {
                                  _error = null;
                                }
                              });
                            },
                            requirementMessage: identityRequirementMessage,
                          ),
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

                      const SizedBox(height: 20),

                      // Upload button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isUploading ? null : _uploadScript,
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.upload),
                          label: Text(_isUploading
                              ? 'Uploading...'
                              : 'Upload to Marketplace'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
