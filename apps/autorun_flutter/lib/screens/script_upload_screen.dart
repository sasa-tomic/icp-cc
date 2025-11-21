import 'package:flutter/material.dart';
import '../services/marketplace_open_api_service.dart';
import '../widgets/error_display.dart';
import '../services/script_signature_service.dart';
import '../controllers/profile_controller.dart';
import '../models/profile_keypair.dart';
import '../utils/principal.dart';
import '../widgets/profile_scope.dart';

class PreFilledUploadData {
  final String title;
  final String luaSource;

  PreFilledUploadData({
    required this.title,
    required this.luaSource,
  });
}

class ScriptUploadScreen extends StatefulWidget {
  const ScriptUploadScreen({super.key, this.preFilledData});

  final PreFilledUploadData? preFilledData;

  @override
  State<ScriptUploadScreen> createState() => _ScriptUploadScreenState();
}

class _ScriptUploadScreenState extends State<ScriptUploadScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final MarketplaceOpenApiService _marketplaceService =
      MarketplaceOpenApiService();

  // Form controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _canisterIdsController = TextEditingController();
  final TextEditingController _iconUrlController = TextEditingController();
  final TextEditingController _screenshotsController = TextEditingController();
  final TextEditingController _versionController =
      TextEditingController(text: '1.0.0');
  final TextEditingController _compatibilityController =
      TextEditingController();
  final TextEditingController _priceController =
      TextEditingController(text: '0.0');

  bool _isUploading = false;
  String? _error;

  // Available categories
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

    // Pre-fill data if provided
    if (widget.preFilledData != null) {
      _titleController.text = widget.preFilledData!.title;
    }

    // Set default category
    _categoryController.text = 'Example';
  }

  Widget _buildKeypairCard(ProfileController controller) {
    final ProfileKeypair? keypair = controller.activeKeypair;
    if (keypair == null) {
      return Card(
        elevation: 0,
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
    final String principal = PrincipalUtils.textFromRecord(keypair);
    // With the new system, all keypairs have an account (draft or registered)
    return Card(
      elevation: 0,
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

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _uploadScript() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check if keypair is selected
    final ProfileController profileController =
        ProfileScope.of(context, listen: false);
    final ProfileKeypair? activeKeypair = profileController.activeKeypair;
    if (activeKeypair == null) {
      setState(() {
        _error = 'No keypair selected. Go to the Profiles tab to select one.';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _error = null;
    });

    try {
      // Parse form data
      final title = _titleController.text.trim();
      // Generate slug from title: lowercase, replace non-alphanumeric with hyphens
      final slug = title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final description = _descriptionController.text.trim();
      final category = _categoryController.text.trim();
      final tags = _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
      final canisterIds = _canisterIdsController.text
          .split(',')
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList();
      final iconUrl = _iconUrlController.text.trim().isEmpty
          ? null
          : _iconUrlController.text.trim();
      final screenshots = _screenshotsController.text
          .split(',')
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList();
      final version = _versionController.text.trim();
      final compatibility = _compatibilityController.text.trim().isEmpty
          ? null
          : _compatibilityController.text.trim();
      final price = double.tryParse(_priceController.text.trim()) ?? 0.0;
      final timestamp = DateTime.now().toUtc().toIso8601String();

      // Generate a default Lua script since API requires non-empty lua_source
      final defaultLuaSource = '''-- Default Script for $title
function init(arg)
  return {
    message = "Hello from $title!",
    description = "$description"
  }, {}
end

function view(state)
  return {
    type = "column",
    children = {
      {
        type = "text",
        props = {
          text = state.message,
          style = "title"
        }
      },
      {
        type = "text",
        props = {
          text = state.description,
          style = "body"
        }
      }
    }
  }
end

function update(msg, state)
  return state, {}
end''';

      // Sign the script upload
      final signature = await ScriptSignatureService.signScriptUpload(
        authorKeypair: activeKeypair,
        title: title,
        description: description,
        category: category,
        luaSource: defaultLuaSource,
        version: version,
        tags: tags,
        compatibility: compatibility,
        timestampIso: timestamp,
      );

      final authorPrincipal = PrincipalUtils.textFromRecord(activeKeypair);

      // Upload script with signature
      await _marketplaceService.uploadScript(
        slug: slug,
        title: title,
        description: description,
        category: category,
        tags: tags,
        luaSource: defaultLuaSource,
        canisterIds: canisterIds.isEmpty ? null : canisterIds,
        iconUrl: iconUrl,
        screenshots: screenshots.isEmpty ? null : screenshots,
        version: version,
        compatibility: compatibility,
        price: price,
        authorPrincipal: authorPrincipal,
        authorPublicKey: activeKeypair.publicKey,
        signature: signature,
        timestampIso: timestamp,
      );

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Script published successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate back
      Navigator.of(context).pop();
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
    final ProfileController profileController = ProfileScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Script'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Progress indicator
            if (_isUploading)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Uploading script...'),
                  ],
                ),
              ),

            // Error display
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: ErrorDisplay(
                  error: _error!,
                  onRetry: null,
                ),
              ),

            // Form content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Basic Information Section
                    _buildSectionHeader('Basic Information'),
                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _titleController,
                      label: 'Title',
                      hint: 'Enter a descriptive title for your script',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Title is required';
                        }
                        if (value.trim().length < 3) {
                          return 'Title must be at least 3 characters';
                        }
                        if (value.trim().length > 100) {
                          return 'Title must be less than 100 characters';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _descriptionController,
                      label: 'Description',
                      hint: 'Describe what your script does and how to use it',
                      maxLines: 4,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Description is required';
                        }
                        if (value.trim().length < 10) {
                          return 'Description must be at least 10 characters';
                        }
                        if (value.trim().length > 1000) {
                          return 'Description must be less than 1000 characters';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Keypair Selection Section
                    _buildSectionHeader('Keypair Context'),
                    const SizedBox(height: 8),
                    _buildKeypairCard(profileController),
                    const SizedBox(height: 24),

                    // Category and Tags Section
                    _buildSectionHeader('Category and Tags'),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _categoryController.text,
                      decoration: const InputDecoration(
                        labelText: 'Category',
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
                          _categoryController.text = value;
                        }
                      },
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Category is required';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _tagsController,
                      label: 'Tags',
                      hint:
                          'Enter comma-separated tags (e.g., automation, defi, gaming)',
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          final tags = value
                              .split(',')
                              .map((tag) => tag.trim())
                              .toList();
                          if (tags.length > 10) {
                            return 'Maximum 10 tags allowed';
                          }
                          for (final tag in tags) {
                            if (tag.length > 20) {
                              return 'Tags must be less than 20 characters each';
                            }
                          }
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    // ICP Integration Section
                    _buildSectionHeader('ICP Integration (Optional)'),
                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _canisterIdsController,
                      label: 'Canister IDs',
                      hint:
                          'Enter comma-separated canister IDs if this script works with specific canisters',
                    ),

                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _compatibilityController,
                      label: 'Compatibility Notes',
                      hint:
                          'Describe any compatibility requirements or limitations',
                      maxLines: 2,
                    ),

                    const SizedBox(height: 24),

                    // Media Section
                    _buildSectionHeader('Media (Optional)'),
                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _iconUrlController,
                      label: 'Icon URL',
                      hint: 'URL to an icon image for your script',
                    ),

                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _screenshotsController,
                      label: 'Screenshots',
                      hint: 'Enter comma-separated URLs to screenshots',
                    ),

                    const SizedBox(height: 24),

                    // Pricing Section
                    _buildSectionHeader('Pricing'),
                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _priceController,
                      label: 'Price (in ICP)',
                      hint: 'Set to 0 for free scripts',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Price is required';
                        }
                        final price = double.tryParse(value.trim());
                        if (price == null) {
                          return 'Invalid price format';
                        }
                        if (price < 0) {
                          return 'Price cannot be negative';
                        }
                        if (price > 1000) {
                          return 'Price cannot exceed 1000 ICP';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _versionController,
                      label: 'Version',
                      hint: 'Initial version (e.g., 1.0.0)',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Version is required';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 32),

                    // Upload button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isUploading ? null : _uploadScript,
                        icon: _isUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload),
                        label: Text(
                            _isUploading ? 'Uploading...' : 'Upload Script'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 2,
          width: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      textInputAction:
          maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
    );
  }
}
