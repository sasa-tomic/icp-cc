import 'package:flutter/material.dart';
import '../models/script_record.dart';
import '../services/marketplace_open_api_service.dart';
import '../widgets/enhanced_script_editor.dart';

class QuickUploadDialog extends StatefulWidget {
  final ScriptRecord? script; // Optional script to pre-fill from
  final String? preFilledTitle;
  final String? preFilledCode;

  const QuickUploadDialog({
    super.key,
    this.script,
    this.preFilledTitle,
    this.preFilledCode,
  });

  @override
  State<QuickUploadDialog> createState() => _QuickUploadDialogState();
}

class _QuickUploadDialogState extends State<QuickUploadDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final MarketplaceOpenApiService _marketplaceService = MarketplaceOpenApiService();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _authorController;
  late final TextEditingController _tagsController;
  late final TextEditingController _priceController;

  String _luaSource = '';
  String _selectedCategory = 'Utilities';
  bool _isUploading = false;
  String? _error;
  ScriptValidationResult? _validationResult;

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
    
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _authorController = TextEditingController();
    _tagsController = TextEditingController();
    _priceController = TextEditingController(text: '0.0');

    _initializeFromScript();
    
    // Validate script immediately if there's initial code
    if (_luaSource.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _validateScript();
      });
    }
  }

  void _initializeFromScript() {
    if (widget.script != null) {
      _titleController.text = widget.script!.title;
      _luaSource = widget.script!.luaSource;
      _authorController.text = 'Anonymous Developer';
      
      // Auto-generate description from script analysis
      _generateDescriptionFromScript();
      
      // Auto-detect category from script content
      _detectCategoryFromScript();
      
      // Auto-generate tags from script content
      _generateTagsFromScript();
    } else if (widget.preFilledTitle != null) {
      _titleController.text = widget.preFilledTitle!;
      _luaSource = widget.preFilledCode ?? '';
      _authorController.text = 'Anonymous Developer';
    }
  }

  void _generateDescriptionFromScript() {
    if (_luaSource.isEmpty) return;
    
    // Simple analysis to generate description
    String description = 'A Lua script for ';
    
    if (_luaSource.contains('icp_call') || _luaSource.contains('canister')) {
      description += 'interacting with ICP canisters';
    } else if (_luaSource.contains('defi') || _luaSource.contains('token') || _luaSource.contains('balance')) {
      description += 'DeFi operations and token management';
    } else if (_luaSource.contains('nft') || _luaSource.contains('mint') || _luaSource.contains('collection')) {
      description += 'NFT operations and digital collectibles';
    } else if (_luaSource.contains('game') || _luaSource.contains('score') || _luaSource.contains('player')) {
      description += 'gaming and entertainment';
    } else {
      description += 'automation and utility tasks';
    }
    
    description += '. This script provides a user-friendly interface for managing various operations.';
    
    _descriptionController.text = description;
  }

  void _detectCategoryFromScript() {
    if (_luaSource.isEmpty) return;
    
    final lowerCode = _luaSource.toLowerCase();
    
    if (lowerCode.contains('game') || lowerCode.contains('score') || lowerCode.contains('player')) {
      _selectedCategory = 'Gaming';
    } else if (lowerCode.contains('defi') || lowerCode.contains('token') || lowerCode.contains('swap') || lowerCode.contains('balance')) {
      _selectedCategory = 'DeFi';
    } else if (lowerCode.contains('nft') || lowerCode.contains('mint') || lowerCode.contains('collection')) {
      _selectedCategory = 'NFT';
    } else if (lowerCode.contains('finance') || lowerCode.contains('payment') || lowerCode.contains('wallet')) {
      _selectedCategory = 'Finance';
    } else if (lowerCode.contains('social') || lowerCode.contains('chat') || lowerCode.contains('message')) {
      _selectedCategory = 'Social';
    } else if (lowerCode.contains('dev') || lowerCode.contains('debug') || lowerCode.contains('test')) {
      _selectedCategory = 'Development';
    } else if (lowerCode.contains('learn') || lowerCode.contains('tutorial') || lowerCode.contains('education')) {
      _selectedCategory = 'Education';
    } else if (lowerCode.contains('business') || lowerCode.contains('work') || lowerCode.contains('productivity')) {
      _selectedCategory = 'Business';
    }
  }

  void _generateTagsFromScript() {
    if (_luaSource.isEmpty) return;
    
    final List<String> tags = [];
    final lowerCode = _luaSource.toLowerCase();
    
    // Auto-generate tags based on content
    if (lowerCode.contains('icp')) tags.add('ICP');
    if (lowerCode.contains('canister')) tags.add('Canister');
    if (lowerCode.contains('defi')) tags.add('DeFi');
    if (lowerCode.contains('nft')) tags.add('NFT');
    if (lowerCode.contains('game')) tags.add('Gaming');
    if (lowerCode.contains('automation')) tags.add('Automation');
    if (lowerCode.contains('utility')) tags.add('Utility');
    if (lowerCode.contains('token')) tags.add('Token');
    if (lowerCode.contains('wallet')) tags.add('Wallet');
    if (lowerCode.contains('swap')) tags.add('Swap');
    
    _tagsController.text = tags.take(5).join(', ');
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

  void _onCodeChanged(String code) {
    setState(() {
      _luaSource = code;
    });
    
    // Validate immediately after code changes
    if (code.trim().isNotEmpty) {
      _validateScript();
    } else {
      setState(() {
        _validationResult = ScriptValidationResult(
          isValid: false,
          errors: ['Script code cannot be empty'],
        );
      });
    }
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
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();
      final tags = _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
      final authorName = _authorController.text.trim();
      final price = double.tryParse(_priceController.text.trim()) ?? 0.0;

      await _marketplaceService.uploadScript(
        title: title,
        description: description,
        category: _selectedCategory,
        tags: tags,
        luaSource: _luaSource,
        authorName: authorName,
        price: price,
        version: '1.0.0',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Script uploaded successfully! It will be reviewed before being published.'),
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
                           style: Theme.of(context).textTheme.titleLarge?.copyWith(
                             fontWeight: FontWeight.bold,
                           ),
                         ),
                         Text(
                           'Share your script with the community',
                           style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                             color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                       // Basic Information Section
                       Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text(
                             'Basic Information',
                             style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                             keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                       
                       const SizedBox(height: 24),
                       
                       // Script Code Section
                       Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text(
                             'Script Code',
                             style: Theme.of(context).textTheme.titleMedium?.copyWith(
                               fontWeight: FontWeight.bold,
                             ),
                           ),
                           const SizedBox(height: 8),
                           
                           // Validation status - prominently displayed
                           if (_validationResult != null) ...[
                             Container(
                               width: double.infinity,
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(
                                 color: _validationResult!.isValid
                                     ? Colors.green.withValues(alpha: 0.1)
                                     : Colors.red.withValues(alpha: 0.1),
                                 borderRadius: BorderRadius.circular(12),
                                 border: Border.all(
                                   color: _validationResult!.isValid
                                       ? Colors.green
                                       : Colors.red,
                                   width: 2,
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
                                         size: 24,
                                       ),
                                       const SizedBox(width: 12),
                                       Expanded(
                                         child: Text(
                                           _validationResult!.isValid
                                               ? '✓ Script is valid and ready to upload'
                                               : '✗ Script has validation errors',
                                           style: TextStyle(
                                             fontSize: 16,
                                             fontWeight: FontWeight.bold,
                                             color: _validationResult!.isValid
                                                 ? Colors.green
                                                 : Colors.red,
                                           ),
                                         ),
                                       ),
                                     ],
                                   ),
                                   
                                   // Show errors if any
                                   if (!_validationResult!.isValid && 
                                       _validationResult!.errors.isNotEmpty) ...[
                                     const SizedBox(height: 12),
                                     ..._validationResult!.errors.map((error) => Padding(
                                       padding: const EdgeInsets.only(bottom: 4, left: 36),
                                       child: Text(
                                         '• $error',
                                         style: TextStyle(
                                           color: Colors.red.shade700,
                                           fontSize: 14,
                                         ),
                                       ),
                                     )),
                                   ],
                                   
                                   const SizedBox(height: 8),
                                   TextButton(
                                     onPressed: _validateScript,
                                     child: const Text('Revalidate'),
                                   ),
                                 ],
                               ),
                             ),
                           ] else ...[
                             Container(
                               width: double.infinity,
                               padding: const EdgeInsets.all(16),
                               decoration: BoxDecoration(
                                 color: Colors.orange.withValues(alpha: 0.1),
                                 borderRadius: BorderRadius.circular(12),
                                 border: Border.all(color: Colors.orange, width: 2),
                               ),
                               child: Row(
                                 children: [
                                   const Icon(Icons.warning, color: Colors.orange, size: 24),
                                   const SizedBox(width: 12),
                                   const Expanded(
                                     child: Text(
                                       'Script validation required',
                                       style: TextStyle(
                                         fontSize: 16,
                                         fontWeight: FontWeight.bold,
                                         color: Colors.orange,
                                       ),
                                     ),
                                   ),
                                   TextButton(
                                     onPressed: _validateScript,
                                     child: const Text('Validate Now'),
                                   ),
                                 ],
                               ),
                             ),
                           ],
                           
                           const SizedBox(height: 16),
                           
                           // Script editor
                           Container(
                             height: 350,
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
                               maxLines: 25,
                             ),
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
                          label: Text(_isUploading ? 'Uploading...' : 'Upload to Marketplace'),
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