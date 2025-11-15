import 'package:flutter/material.dart';
import '../services/marketplace_open_api_service.dart';
import '../widgets/enhanced_script_editor.dart';
import '../widgets/error_display.dart';

class PreFilledUploadData {
  final String title;
  final String luaSource;
  final String authorName;

  PreFilledUploadData({
    required this.title,
    required this.luaSource,
    required this.authorName,
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
  final MarketplaceOpenApiService _marketplaceService = MarketplaceOpenApiService();

  // Form controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _canisterIdsController = TextEditingController();
  final TextEditingController _iconUrlController = TextEditingController();
  final TextEditingController _screenshotsController = TextEditingController();
  final TextEditingController _versionController = TextEditingController(text: '1.0.0');
  final TextEditingController _compatibilityController = TextEditingController();
  final TextEditingController _priceController = TextEditingController(text: '0.0');

  // Script editor state
  String _luaSource = '''-- Welcome to the ICP Autorun Script Marketplace!
-- This is a template for your Lua script.

-- Define your script's init function
function init(arg)
    -- Initialize your script state here
    local state = {
        message = "Hello from marketplace script!",
        counter = 0
    }

    -- Return initial state and any effects to run
    return state, {}
end

-- Define your script's view function (UI)
function view(state)
    -- Define the user interface for your script
    return {
        type = "column",
        children = {
            {
                type = "text",
                text = state.message,
                style = "headline"
            },
            {
                type = "text",
                text = "Counter: " .. state.counter,
                style = "body"
            },
            {
                type = "button",
                text = "Increment Counter",
                on_click = {
                    type = "increment"
                }
            }
        }
    }
end

-- Define your script's update function (logic)
function update(msg, state)
    -- Handle messages and update state
    if msg.type == "increment" then
        state.counter = state.counter + 1
    end

    -- Return updated state and any effects to run
    return state, {}
end
''';

  bool _isUploading = false;
  String? _error;
  ScriptValidationResult? _validationResult;

  // Available categories
  final List<String> _availableCategories = [
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
      _luaSource = widget.preFilledData!.luaSource;
      _authorController.text = widget.preFilledData!.authorName;
    }
    
    // Set default category
    _categoryController.text = 'Utilities';
    
    // Set default author if not pre-filled
    if (_authorController.text.isEmpty) {
      _authorController.text = 'Anonymous Developer';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _authorController.dispose();
    _categoryController.dispose();
    _tagsController.dispose();
    _canisterIdsController.dispose();
    _iconUrlController.dispose();
    _screenshotsController.dispose();
    _versionController.dispose();
    _compatibilityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onCodeChanged(String code) {
    setState(() {
      _luaSource = code;
      _validationResult = null;
    });
  }

  Future<void> _validateScript() async {
    if (_luaSource.trim().isEmpty) {
      setState(() {
        _validationResult = ScriptValidationResult(
          isValid: false,
          errors: ['Script code cannot be empty'],
        );
      });
      return;
    }

    try {
      final result = await _marketplaceService.validateScript(_luaSource);
      setState(() {
        _validationResult = result;
      });
    } catch (e) {
      setState(() {
        _validationResult = ScriptValidationResult(
          isValid: false,
          errors: ['Validation failed: $e'],
        );
      });
    }
  }

  Future<void> _uploadScript() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_validationResult == null || !_validationResult!.isValid) {
      await _validateScript();
      if (_validationResult == null || !_validationResult!.isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please fix script validation errors before uploading'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _isUploading = true;
      _error = null;
    });

    try {
      // Parse form data
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();
      final category = _categoryController.text.trim();
      final tags = _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
      final authorName = _authorController.text.trim();
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

      // Upload script
      await _marketplaceService.uploadScript(
        title: title,
        description: description,
        category: category,
        tags: tags,
        luaSource: _luaSource,
        authorName: authorName,
        canisterIds: canisterIds.isEmpty ? null : canisterIds,
        iconUrl: iconUrl,
        screenshots: screenshots.isEmpty ? null : screenshots,
        version: version,
        compatibility: compatibility,
        price: price,
      );

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Script uploaded successfully! It will be reviewed before being published.'),
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

                    _buildTextField(
                      controller: _authorController,
                      label: 'Author Name',
                      hint: 'Your name or organization name',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Author name is required';
                        }
                        return null;
                      },
                    ),

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
                      hint: 'Enter comma-separated tags (e.g., automation, defi, gaming)',
                      validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          final tags = value.split(',').map((tag) => tag.trim()).toList();
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
                      hint: 'Enter comma-separated canister IDs if this script works with specific canisters',
                    ),

                    const SizedBox(height: 16),

                    _buildTextField(
                      controller: _compatibilityController,
                      label: 'Compatibility Notes',
                      hint: 'Describe any compatibility requirements or limitations',
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

                    const SizedBox(height: 24),

                    // Script Code Section
                    _buildSectionHeader('Script Code'),
                    const SizedBox(height: 8),

                    Text(
                      'Write your Lua script code below. The script will be validated before uploading.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Validation status
                    if (_validationResult != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _validationResult!.isValid
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _validationResult!.isValid
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _validationResult!.isValid
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: _validationResult!.isValid
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _validationResult!.isValid
                                      ? 'Script is valid'
                                      : 'Script has errors',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _validationResult!.isValid
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _validateScript,
                                  child: const Text('Revalidate'),
                                ),
                              ],
                            ),
                            if (!_validationResult!.isValid &&
                                _validationResult!.errors.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              ..._validationResult!.errors.map((error) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ', style: TextStyle(color: Colors.red)),
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: const TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                            ],
                            if (_validationResult!.warnings.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Warnings:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                              ..._validationResult!.warnings.map((warning) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('• ', style: TextStyle(color: Colors.orange[700])),
                                    Expanded(
                                      child: Text(
                                        warning,
                                        style: TextStyle(color: Colors.orange[700]),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info, color: Colors.blue),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Click "Validate Script" to check your code for syntax errors',
                                style: TextStyle(color: Colors.blue),
                              ),
                            ),
                            TextButton(
                              onPressed: _validateScript,
                              child: const Text('Validate Script'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Script editor
                    Container(
                      height: 400,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: EnhancedScriptEditor(
                        initialCode: _luaSource,
                        onCodeChanged: _onCodeChanged,
                        language: 'lua',
                        minLines: 15,
                        maxLines: 30,
                      ),
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
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload),
                        label: Text(_isUploading ? 'Uploading...' : 'Upload Script'),
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
      textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
    );
  }
}