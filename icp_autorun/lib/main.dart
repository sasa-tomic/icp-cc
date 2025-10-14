import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'dart:convert';

import 'controllers/identity_controller.dart';
import 'rust/native_bridge.dart';
import 'models/identity_record.dart';
import 'services/identity_repository.dart';
import 'utils/principal.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IdentityApp());
}

class IdentityApp extends StatelessWidget {
  const IdentityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICP Identity Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const IdentityHomePage(),
    );
  }
}

class IdentityHomePage extends StatefulWidget {
  const IdentityHomePage({super.key});

  @override
  State<IdentityHomePage> createState() => _IdentityHomePageState();
}

class _IdentityHomePageState extends State<IdentityHomePage> {
  late final IdentityController _controller;
  final RustBridgeLoader _bridge = const RustBridgeLoader();
  String? _lastResult;

  @override
  void initState() {
    super.initState();
    _controller = IdentityController(IdentityRepository())
      ..addListener(_onControllerChanged);
    unawaited(_controller.ensureLoaded());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showCreationSheet() async {
    final IdentityRecord? record = await showModalBottomSheet<IdentityRecord>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) =>
          _IdentityCreationSheet(controller: _controller),
    );
    if (!mounted || record == null) {
      return;
    }
    await _showDetailsDialog(record, title: 'Identity Created');
  }

  Future<void> _showDetailsDialog(
    IdentityRecord record, {
    required String title,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _DialogSection(
                  label: 'Label',
                  value: record.label,
                  onCopy: () => _copyToClipboard('Label', record.label),
                ),
                _DialogSection(
                  label: 'Principal',
                  value: PrincipalUtils.textFromRecord(record),
                  onCopy: () => _copyToClipboard(
                    'Principal',
                    PrincipalUtils.textFromRecord(record),
                  ),
                ),
                _DialogSection(
                  label: 'Algorithm',
                  value: keyAlgorithmToString(record.algorithm),
                ),
                _DialogSection(
                  label: 'Seed phrase',
                  value: record.mnemonic,
                  onCopy: () =>
                      _copyToClipboard('Seed phrase', record.mnemonic),
                ),
                _DialogSection(
                  label: 'Public key (base64)',
                  value: record.publicKey,
                  onCopy: () =>
                      _copyToClipboard('Public key', record.publicKey),
                ),
                _DialogSection(
                  label: 'Private key (base64)',
                  value: record.privateKey,
                  onCopy: () =>
                      _copyToClipboard('Private key', record.privateKey),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied to clipboard')));
  }

  Future<void> _handleAction(
    _IdentityAction action,
    IdentityRecord record,
  ) async {
    switch (action) {
      case _IdentityAction.showDetails:
        await _showDetailsDialog(record, title: 'Identity details');
        break;
      case _IdentityAction.rename:
        await _showRenameDialog(record);
        break;
      case _IdentityAction.delete:
        await _confirmAndDelete(record);
        break;
    }
  }

  Future<void> _showRenameDialog(IdentityRecord record) async {
    final TextEditingController controller = TextEditingController(
      text: record.label,
    );
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rename identity'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'New label',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              textInputAction: TextInputAction.done,
              validator: (String? value) {
                // Allow empty label, but normalize whitespace
                return null;
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(controller.text.trim());
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result == null) {
      return;
    }
    await _controller.updateLabel(id: record.id, label: result);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Identity renamed')));
  }

  Future<void> _confirmAndDelete(IdentityRecord record) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete identity'),
          content: const Text(
            'This action will permanently delete this identity from this device. This cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _controller.deleteIdentity(record.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Identity deleted')));
  }

  @override
  Widget build(BuildContext context) {
    final List<IdentityRecord> identities = _controller.identities;
    final bool showLoading = _controller.isBusy && identities.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ICP Identity Manager'),
        actions: <Widget>[
          IconButton(
            onPressed: _controller.isBusy ? null : _controller.refresh,
            tooltip: 'Reload identities',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => _showCanisterClientSheet(),
            tooltip: 'Canister client',
            icon: const Icon(Icons.cloud),
          ),
        ],
      ),
      body: Builder(
        builder: (BuildContext context) {
          if (showLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (identities.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: _controller.refresh,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96, top: 8),
              itemCount: identities.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final IdentityRecord record = identities[index];
                final String principalText = PrincipalUtils.textFromRecord(record);
                final String principalPrefix = principalText.length >= 5
                    ? principalText.substring(0, 5)
                    : principalText;
                return Dismissible(
                  key: ValueKey<String>(record.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: const <Widget>[
                        Icon(Icons.delete),
                        SizedBox(width: 8),
                        Text('Delete'),
                      ],
                    ),
                  ),
                  confirmDismiss: (_) async {
                    await _confirmAndDelete(record);
                    return false;
                  },
                  child: ListTile(
                    title: Text(record.label),
                    subtitle: Text('$principalPrefix • ${_subtitleFor(record)}'),
                    leading: CircleAvatar(
                      child: Text(
                        record.label.isNotEmpty
                            ? record.label.substring(0, 1).toUpperCase()
                            : '#',
                      ),
                    ),
                    onTap: () => _copyToClipboard(
                      'Principal',
                      PrincipalUtils.textFromRecord(record),
                    ),
                    trailing: PopupMenuButton<_IdentityAction>(
                      onSelected: (_IdentityAction action) =>
                          _handleAction(action, record),
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<_IdentityAction>>[
                        const PopupMenuItem<_IdentityAction>(
                          value: _IdentityAction.showDetails,
                          child: Text('Show details'),
                        ),
                        const PopupMenuItem<_IdentityAction>(
                          value: _IdentityAction.rename,
                          child: Text('Rename'),
                        ),
                        const PopupMenuItem<_IdentityAction>(
                          value: _IdentityAction.delete,
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _controller.isBusy ? null : _showCreationSheet,
        icon: const Icon(Icons.add),
        label: const Text('New identity'),
      ),
    );
  }

  String _subtitleFor(IdentityRecord record) {
    final DateTime localTime = record.createdAt.toLocal();
    final String timestamp =
        '${localTime.year.toString().padLeft(4, '0')}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} '
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    final String algorithm = keyAlgorithmToString(
      record.algorithm,
    ).toUpperCase();
    return '$algorithm • $timestamp';
  }
  Future<void> _showCanisterClientSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return _CanisterClientSheet(bridge: _bridge);
      },
    );
  }

}

class _IdentityCreationSheet extends StatefulWidget {
  const _IdentityCreationSheet({required this.controller});

  final IdentityController controller;

  @override
  State<_IdentityCreationSheet> createState() => _IdentityCreationSheetState();
}

class _IdentityCreationSheetState extends State<_IdentityCreationSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _mnemonicController;
  KeyAlgorithm _algorithm = KeyAlgorithm.ed25519;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
    _mnemonicController = TextEditingController();
  }

  @override
  void dispose() {
    _labelController.dispose();
    _mnemonicController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final IdentityRecord record = await widget.controller.createIdentity(
        algorithm: _algorithm,
        label: _labelController.text.trim(),
        mnemonic: _mnemonicController.text.trim().isEmpty
            ? null
            : _mnemonicController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(record);
    } catch (error, stackTrace) {
      debugPrint('Failed to create identity: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create identity: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: <Widget>[
            Text(
              'Create a new identity',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Key algorithm',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<KeyAlgorithm>(
                  value: _algorithm,
                  items: const <DropdownMenuItem<KeyAlgorithm>>[
                    DropdownMenuItem<KeyAlgorithm>(
                      value: KeyAlgorithm.ed25519,
                      child: Text('Ed25519 (recommended)'),
                    ),
                    DropdownMenuItem<KeyAlgorithm>(
                      value: KeyAlgorithm.secp256k1,
                      child: Text('secp256k1 (dfx-compatible)'),
                    ),
                  ],
                  onChanged: (KeyAlgorithm? value) {
                    if (value != null) {
                      setState(() => _algorithm = value);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _mnemonicController,
              decoration: const InputDecoration(
                labelText: 'Seed phrase (optional)',
                hintText: 'Enter existing BIP39 seed phrase',
                helperText: 'Leave empty to generate a new seed phrase.',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              enableSuggestions: false,
              autocorrect: false,
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return null;
                }
                return bip39.validateMnemonic(value.trim())
                    ? null
                    : 'Invalid BIP39 seed phrase';
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt),
              label: const Text('Create identity'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.verified_user,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          const Text('No identities yet'),
          const SizedBox(height: 8),
          const Text('Tap "New identity" to generate your first ICP identity.'),
        ],
      ),
    );
  }
}

class _FavoritesList extends StatefulWidget {
  const _FavoritesList({required this.bridge, required this.onTapEntry});
  final RustBridgeLoader bridge;
  final void Function(String canisterId, String method) onTapEntry;

  @override
  State<_FavoritesList> createState() => _FavoritesListState();
}

class _WellKnownList extends StatelessWidget {
  const _WellKnownList({required this.onSelect});
  final void Function(String canisterId, String method) onSelect;

  static const List<Map<String, String>> _items = <Map<String, String>>[
    // NNS Registry
    {'label': 'NNS Registry', 'cid': 'rwlgt-iiaaa-aaaaa-aaaaa-cai', 'method': 'get_value'},
    // NNS Governance
    {'label': 'NNS Governance', 'cid': 'rrkah-fqaaa-aaaaa-aaaaq-cai', 'method': 'get_neuron_ids'},
    // NNS Ledger
    {'label': 'NNS Ledger', 'cid': 'ryjl3-tyaaa-aaaaa-aaaba-cai', 'method': 'account_balance_dfx'},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final e = _items[index];
        return ListTile(
          leading: const Icon(Icons.star_border),
          title: Text(e['label'] ?? ''),
          subtitle: Text('${e['cid']} • ${e['method']}'),
          onTap: () => onSelect(e['cid'] ?? '', e['method'] ?? ''),
        );
      },
    );
  }
}

class _CanisterClientSheet extends StatefulWidget {
  const _CanisterClientSheet({required this.bridge});
  final RustBridgeLoader bridge;

  @override
  State<_CanisterClientSheet> createState() => _CanisterClientSheetState();
}

class _CanisterClientSheetState extends State<_CanisterClientSheet> {
  final TextEditingController _canisterController = TextEditingController();
  final TextEditingController _hostController = TextEditingController(text: 'https://ic0.app');
  String? _candidRaw;
  List<Map<String, dynamic>> _methods = const <Map<String, dynamic>>[];
  bool _isFetching = false;

  @override
  void dispose() {
    _canisterController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _fetchAndParse() async {
    final String cid = _canisterController.text.trim();
    if (cid.isEmpty || _isFetching) return;
    setState(() => _isFetching = true);
    try {
      final String? did = await widget.bridge.fetchCandid(
        canisterId: cid,
        host: _hostController.text.trim().isEmpty ? null : _hostController.text.trim(),
      );
      if (did == null || did.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to fetch Candid')));
        return;
      }
      final String? parsedJson = widget.bridge.parseCandid(candidText: did);
      if (parsedJson == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to parse Candid')));
        return;
      }
      final Map<String, dynamic> parsed = json.decode(parsedJson) as Map<String, dynamic>;
      final List<dynamic> methods = (parsed['methods'] as List<dynamic>? ?? <dynamic>[]);
      setState(() {
        _candidRaw = did;
        _methods = methods
            .whereType<Map<String, dynamic>>()
            .map((m) => {
                  'name': m['name'] as String? ?? '',
                  'kind': m['kind'] as String? ?? '',
                  'args': (m['args'] as List<dynamic>? ?? const <dynamic>[])
                      .map((e) => e.toString())
                      .toList(),
                  'rets': (m['rets'] as List<dynamic>? ?? const <dynamic>[])
                      .map((e) => e.toString())
                      .toList(),
                })
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: <Widget>[
          Text('ICP Canister Client', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _canisterController,
            decoration: const InputDecoration(
              labelText: 'Canister ID',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Replica Host (optional)',
              hintText: 'https://ic0.app',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: _isFetching ? null : _fetchAndParse,
                  child: _isFetching
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Fetch & List Methods'),
                ),
              ),
              const SizedBox(width: 8),
              if (_candidRaw != null)
                OutlinedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Candid (raw)'),
                        content: SingleChildScrollView(child: SelectableText(_candidRaw!)),
                        actions: <Widget>[
                          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                        ],
                      ),
                    );
                  },
                  child: const Text('View Candid'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_methods.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Methods', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _methods.length,
                  separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final m = _methods[index];
                    final String name = m['name'] as String;
                    final String kind = (m['kind'] as String).toString();
                    final List<String> args = (m['args'] as List<dynamic>).cast<String>();
                    final List<String> rets = (m['rets'] as List<dynamic>).cast<String>();
                    final String sig = '(${args.join(', ')}) -> (${rets.join(', ')})';
                    return ListTile(
                      leading: Icon(
                        kind.toLowerCase().contains('update') ? Icons.sync_alt : Icons.search,
                      ),
                      title: Text(name),
                      subtitle: Text('$kind • $sig'),
                      trailing: Wrap(
                        spacing: 8,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Use method',
                            icon: const Icon(Icons.input),
                            onPressed: () {
                              Navigator.of(context).pop();
                              // In follow-ups we can prefill call UI with this method.
                            },
                          ),
                          IconButton(
                            tooltip: 'Favorite',
                            icon: const Icon(Icons.favorite_border),
                            onPressed: () {
                              final cid = _canisterController.text.trim();
                              if (cid.isEmpty) return;
                              widget.bridge.favoritesAdd(canisterId: cid, method: name);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to favorites')));
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          const SizedBox(height: 16),
          Text('Well-known canisters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _WellKnownList(onSelect: (cid, method) {
            _canisterController.text = cid;
            // Method is used for quick call later; here we just help selection.
          }),
          const SizedBox(height: 16),
          Text('Favorites', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _FavoritesList(
            bridge: widget.bridge,
            onTapEntry: (cid, method) {
              _canisterController.text = cid;
            },
          ),
        ],
      ),
    );
  }
}

class _FavoritesListState extends State<_FavoritesList> {
  List<Map<String, dynamic>> _entries = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final jsonStr = widget.bridge.favoritesList();
    if (jsonStr == null) return;
    final List<dynamic> arr = json.decode(jsonStr) as List<dynamic>;
    setState(() {
      _entries = arr
          .whereType<Map<String, dynamic>>()
          .map((e) => {
                'canister_id': e['canister_id'] as String? ?? '',
                'method': e['method'] as String? ?? '',
                'label': e['label'] as String?,
              })
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) {
      return const Text('No favorites yet');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _entries.length,
      separatorBuilder: (BuildContext _, int __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final e = _entries[index];
        final cid = e['canister_id'] as String;
        final method = e['method'] as String;
        final label = (e['label'] as String?) ?? '';
        return ListTile(
          title: Text(label.isNotEmpty ? label : method),
          subtitle: Text('$cid • $method'),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              widget.bridge.favoritesRemove(canisterId: cid, method: method);
              _reload();
            },
          ),
          onTap: () => widget.onTapEntry(cid, method),
        );
      },
    );
  }
}

class _DialogSection extends StatelessWidget {
  const _DialogSection({required this.label, required this.value, this.onCopy});

  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              if (onCopy != null)
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy',
                  onPressed: onCopy,
                ),
            ],
          ),
          SelectableText(value),
        ],
      ),
    );
  }
}

enum _IdentityAction { showDetails, rename, delete }
