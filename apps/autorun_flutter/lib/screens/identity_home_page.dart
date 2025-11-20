import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/identity_controller.dart';
import '../controllers/account_controller.dart';
import '../models/account.dart';
import '../models/identity_record.dart';
import '../services/secure_identity_repository.dart';
import '../theme/app_design_system.dart';
import '../utils/principal.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_fab.dart';
import '../widgets/key_parameters_dialog.dart';
import 'account_registration_wizard.dart';
import 'account_profile_screen.dart';

/// Account loading state for each identity
enum AccountLoadState {
  /// Account has not been loaded yet
  notLoaded,

  /// Account is currently being loaded
  loading,

  /// Account loaded successfully (or confirmed no account exists)
  loaded,

  /// Failed to load account due to error
  error,
}

class IdentityHomePage extends StatefulWidget {
  const IdentityHomePage({super.key});

  @override
  State<IdentityHomePage> createState() => _IdentityHomePageState();
}

class _IdentityHomePageState extends State<IdentityHomePage> {
  late final IdentityController _controller;
  late final AccountController _accountController;

  /// Track account loading state for each identity
  final Map<String, AccountLoadState> _accountLoadStates = {};

  /// Track error messages for identities that failed to load
  final Map<String, String> _accountLoadErrors = {};

  @override
  void initState() {
    super.initState();
    _controller = IdentityController(
      secureRepository: SecureIdentityRepository(),
    )..addListener(_onControllerChanged);
    _accountController = AccountController()..addListener(_onControllerChanged);
    unawaited(_controller.ensureLoaded());
    unawaited(_loadAccountsForIdentities());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _accountController
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadAccountsForIdentities() async {
    await _controller.ensureLoaded();
    // Fetch accounts for all identities using stored username mappings
    final identities = _controller.identities;

    for (final identity in identities) {
      // Mark as loading
      if (mounted) {
        setState(() {
          _accountLoadStates[identity.id] = AccountLoadState.loading;
          _accountLoadErrors.remove(identity.id);
        });
      }

      try {
        await _accountController.fetchAccountForIdentity(identity);

        // Success - mark as loaded
        if (mounted) {
          setState(() {
            _accountLoadStates[identity.id] = AccountLoadState.loaded;
          });
        }
      } on AccountNetworkException catch (e) {
        // Network error - show error to user
        debugPrint('❌ Network error loading account for ${identity.id}: $e');
        if (mounted) {
          setState(() {
            _accountLoadStates[identity.id] = AccountLoadState.error;
            _accountLoadErrors[identity.id] = e.message;
          });

          // Show snackbar for first network error only
          if (_accountLoadErrors.length == 1) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Network error: ${e.message}'),
                action: SnackBarAction(
                  label: 'Retry',
                  onPressed: () => _retryLoadAccount(identity),
                ),
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      } on TimeoutException {
        // Timeout - show error to user
        debugPrint('⏱️ Timeout loading account for ${identity.id}');
        if (mounted) {
          setState(() {
            _accountLoadStates[identity.id] = AccountLoadState.error;
            _accountLoadErrors[identity.id] = 'Request timed out';
          });

          // Show snackbar for first timeout only
          if (_accountLoadErrors.length == 1) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Request timed out. Check your connection.'),
                action: SnackBarAction(
                  label: 'Retry',
                  onPressed: () => _retryLoadAccount(identity),
                ),
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      } catch (e) {
        // Unexpected error - log and mark as loaded (account may not exist)
        debugPrint('ℹ️ Account fetch completed for ${identity.id}: $e');
        if (mounted) {
          setState(() {
            _accountLoadStates[identity.id] = AccountLoadState.loaded;
          });
        }
      }
    }
  }

  /// Retry loading account for a specific identity
  Future<void> _retryLoadAccount(IdentityRecord identity) async {
    if (mounted) {
      setState(() {
        _accountLoadStates[identity.id] = AccountLoadState.loading;
        _accountLoadErrors.remove(identity.id);
      });
    }

    try {
      await _accountController.fetchAccountForIdentity(identity);

      if (mounted) {
        setState(() {
          _accountLoadStates[identity.id] = AccountLoadState.loaded;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account loaded successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on AccountNetworkException catch (e) {
      debugPrint('❌ Retry failed for ${identity.id}: $e');
      if (mounted) {
        setState(() {
          _accountLoadStates[identity.id] = AccountLoadState.error;
          _accountLoadErrors[identity.id] = e.message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Still failing: ${e.message}'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _retryLoadAccount(identity),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on TimeoutException {
      debugPrint('⏱️ Retry timeout for ${identity.id}');
      if (mounted) {
        setState(() {
          _accountLoadStates[identity.id] = AccountLoadState.error;
          _accountLoadErrors[identity.id] = 'Request timed out';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Still timing out. Check your connection.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _retryLoadAccount(identity),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('ℹ️ Retry completed for ${identity.id}: $e');
      if (mounted) {
        setState(() {
          _accountLoadStates[identity.id] = AccountLoadState.loaded;
        });
      }
    }
  }

  Future<void> _navigateToAccountRegistration(IdentityRecord identity) async {
    final Account? createdAccount = await Navigator.push<Account>(
      context,
      MaterialPageRoute(
        builder: (context) => AccountRegistrationWizard(
          identity: identity,
          accountController: _accountController,
        ),
      ),
    );

    if (createdAccount != null && mounted) {
      // Navigate to account profile after successful registration
      await _navigateToAccountProfile(createdAccount, identity);
    }
  }

  Future<void> _navigateToAccountProfile(Account account, IdentityRecord identity) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => AccountProfileScreen(
          account: account,
          accountController: _accountController,
          currentIdentity: identity,
        ),
      ),
    );
    // Refresh state after returning from profile
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showCreationSheet() async {
    // Show dialog to collect key parameters
    final KeyParameters? params = await showDialog<KeyParameters>(
      context: context,
      builder: (context) => const KeyParametersDialog(
        title: 'Create New Identity',
      ),
    );

    if (params == null || !mounted) {
      return;
    }

    // Determine label (use provided or generate default)
    final label = params.label ?? 'Identity ${_controller.identities.length + 1}';

    // Create identity with provided parameters and set as active
    final IdentityRecord record = await _controller.createIdentity(
      algorithm: params.algorithm,
      label: label,
      mnemonic: params.seed,
      setAsActive: true,
    );

    if (!mounted) {
      return;
    }

    // Navigate directly to account registration wizard
    await _navigateToAccountRegistration(record);
  }

  Future<void> _showKeypairInformationDialog(IdentityRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Keypair Information'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Keypair details for ${_displayNameForIdentity(record)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 16),
                _DialogSection(
                  label: 'Principal',
                  value: PrincipalUtils.textFromRecord(record),
                  onCopy: () => _copyToClipboard('Principal', PrincipalUtils.textFromRecord(record)),
                ),
                _DialogSection(
                  label: 'Algorithm',
                  value: keyAlgorithmToString(record.algorithm),
                ),
                _DialogSection(
                  label: 'Seed phrase',
                  value: record.mnemonic,
                  onCopy: () => _copyToClipboard('Seed phrase', record.mnemonic),
                ),
                _DialogSection(
                  label: 'Public key (base64)',
                  value: record.publicKey,
                  onCopy: () => _copyToClipboard('Public key', record.publicKey),
                ),
                _DialogSection(
                  label: 'Private key (base64)',
                  value: record.privateKey,
                  onCopy: () => _copyToClipboard('Private key', record.privateKey),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ],
        );
      },
    );
  }

  Future<void> _showManageKeypairsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Manage Local Identities'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local cryptographic identities stored on this device',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 16),
                // List of identities
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _controller.identities.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final identity = _controller.identities[index];
                      final isActive = identity.id == _controller.activeIdentityId;
                      final principal = PrincipalUtils.textFromRecord(identity);
                      final principalPrefix = principal.length >= 12 ? principal.substring(0, 12) : principal;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: isActive
                            ? AppDesignSystem.primaryLight
                            : AppDesignSystem.neutral300,
                          child: Text(
                            _avatarInitialsForIdentity(identity),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          _displayNameForIdentity(identity),
                          style: TextStyle(
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          '$principalPrefix...',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppDesignSystem.primaryLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'ACTIVE',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else
                              TextButton(
                                onPressed: () async {
                                  final navigator = Navigator.of(context);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final label = identity.label;
                                  await _controller.setActiveIdentity(identity.id);
                                  if (!mounted) return;
                                  navigator.pop();
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('$label is now active'),
                                      backgroundColor: AppDesignSystem.successLight,
                                    ),
                                  );
                                },
                                child: const Text('Set Active'),
                              ),
                            IconButton(
                              icon: const Icon(Icons.info_outline, size: 20),
                              onPressed: () {
                                Navigator.of(context).pop();
                                _showKeypairInformationDialog(identity);
                              },
                              tooltip: 'Show details',
                            ),
                            if (_controller.identities.length > 1)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: AppDesignSystem.errorLight),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _confirmAndDelete(identity);
                                },
                                tooltip: 'Delete',
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showCreationSheet();
              },
              child: const Text('Create New Identity'),
            ),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied to clipboard')));
  }

  Future<void> _showIdentityMenu(BuildContext context, IdentityRecord record, bool isActive) async {
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final Account? account = _accountController.accountForIdentity(record);

    final _IdentityAction? action = await showMenu<_IdentityAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width - 200,
        100,
        20,
        0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: _buildMenuItems(isActive, account),
    );

    if (action != null) {
      HapticFeedback.selectionClick();
      await _handleAction(action, record);
    }
  }

  List<PopupMenuEntry<_IdentityAction>> _buildMenuItems(bool isActive, Account? account) {
    return <PopupMenuEntry<_IdentityAction>>[
      if (!isActive)
        PopupMenuItem<_IdentityAction>(
          value: _IdentityAction.setActive,
          child: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 20, color: AppDesignSystem.successLight),
              const SizedBox(width: 12),
              const Text('Set as active'),
            ],
          ),
        ),
      if (account != null)
        PopupMenuItem<_IdentityAction>(
          value: _IdentityAction.openAccountProfile,
          child: Row(
            children: [
              const Icon(Icons.account_circle_rounded, size: 20),
              const SizedBox(width: 12),
              const Text('Profile information'),
            ],
          ),
        ),
      if (account != null && !account.isAtMaxKeys)
        PopupMenuItem<_IdentityAction>(
          value: _IdentityAction.addKeyToAccount,
          child: Row(
            children: [
              Icon(Icons.key_rounded, size: 20, color: AppDesignSystem.accentDark),
              const SizedBox(width: 12),
              const Text('Add key to account'),
            ],
          ),
        ),
      PopupMenuItem<_IdentityAction>(
        value: _IdentityAction.showKeypairInfo,
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 12),
            const Text('Show keypair information'),
          ],
        ),
      ),
      PopupMenuItem<_IdentityAction>(
        value: _IdentityAction.manageKeypairs,
        child: Row(
          children: [
            const Icon(Icons.key_rounded, size: 20),
            const SizedBox(width: 12),
            const Text('Manage local identities'),
          ],
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<_IdentityAction>(
        value: _IdentityAction.delete,
        child: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, size: 20, color: AppDesignSystem.errorLight),
            const SizedBox(width: 12),
            const Text('Delete', style: TextStyle(color: AppDesignSystem.errorLight)),
          ],
        ),
      ),
    ];
  }

  Future<void> _handleAction(_IdentityAction action, IdentityRecord record) async {
    switch (action) {
      case _IdentityAction.setActive:
        await _controller.setActiveIdentity(record.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${record.label} is now the active identity'),
            backgroundColor: AppDesignSystem.successLight,
          ),
        );
        break;
      case _IdentityAction.openAccountProfile:
        final Account? account = _accountController.accountForIdentity(record);
        if (account != null) {
          await _navigateToAccountProfile(account, record);
        }
        break;
      case _IdentityAction.addKeyToAccount:
        final Account? account = _accountController.accountForIdentity(record);
        if (account != null) {
          await _navigateToAccountProfile(account, record);
        }
        break;
      case _IdentityAction.showKeypairInfo:
        await _showKeypairInformationDialog(record);
        break;
      case _IdentityAction.manageKeypairs:
        await _showManageKeypairsDialog();
        break;
      case _IdentityAction.delete:
        await _confirmAndDelete(record);
        break;
    }
  }


  Future<void> _confirmAndDelete(IdentityRecord record) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete identity'),
          content: const Text('This action will permanently delete this identity from this device. This cannot be undone.'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton.tonal(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Identity deleted')));
  }

  String _displayNameForIdentity(IdentityRecord record) {
    // Get account (either registered or draft)
    final Account? account = _accountController.accountForIdentity(record);
    if (account != null) {
      return account.displayName;
    }
    // Fall back to identity label if no account exists
    return record.label;
  }

  String _avatarInitialsForIdentity(IdentityRecord record) {
    final String displayName = _displayNameForIdentity(record);
    if (displayName.isEmpty) {
      return '#';
    }
    return displayName.length >= 2
        ? displayName.substring(0, 2).toUpperCase()
        : displayName.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final List<IdentityRecord> identities = _controller.identities;
    final bool showLoading = _controller.isBusy && identities.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Profiles'),
        actions: <Widget>[
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: _controller.isBusy ? null : () {
                HapticFeedback.lightImpact();
                _controller.refresh();
              },
              tooltip: 'Refresh identities',
              icon: Icon(
                Icons.refresh_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false, // AppBar already handles top safe area
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Builder(
            builder: (BuildContext context) {
            if (showLoading) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.verified_user_rounded,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Loading Identities...',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                  ],
                ),
              );
            }
            if (identities.isEmpty) {
              return EmptyState(
                icon: Icons.verified_user_rounded,
                title: 'No Identities Yet',
                subtitle: 'Create your first ICP identity to start interacting with the Internet Computer blockchain',
                action: _showCreationSheet,
                actionLabel: 'Create Identity',
              );
            }
            return RefreshIndicator(
              onRefresh: _controller.refresh,
              child: ListView.separated(
               padding: EdgeInsets.only(
                 left: 16,
                 right: 16,
                 top: 16,
                 bottom: 16 + MediaQuery.of(context).padding.bottom, // Account for bottom safe area
               ),
                itemCount: identities.length + 1, // +1 for incognito mode
                 separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 12),
                itemBuilder: (BuildContext context, int index) {
                  // First item is incognito mode
                  if (index == 0) {
                    final bool isActive = _controller.activeIdentityId == null;
                    return _buildIncognitoModeCard(context, isActive);
                  }

                  // Subsequent items are regular identities (adjust index by -1)
                  final IdentityRecord record = identities[index - 1];
                  final String principalText = PrincipalUtils.textFromRecord(record);
                  final String principalPrefix = principalText.length >= 8 ? principalText.substring(0, 8) : principalText;
                  final bool isActive = record.id == _controller.activeIdentityId;
                  
                  return Hero(
                    tag: 'identity_${record.id}',
                    child: Card(
                      elevation: isActive ? 8 : 4,
                      shadowColor: isActive 
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                          : Colors.black.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: isActive 
                            ? BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 2,
                              )
                            : BorderSide.none,
                      ),
                      child: InkWell(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          if (!isActive) {
                            final messenger = ScaffoldMessenger.of(context);
                            await _controller.setActiveIdentity(record.id);
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('${record.label} is now the active identity'),
                                backgroundColor: AppDesignSystem.successLight,
                              ),
                            );
                          }
                        },
                        onLongPress: () {
                          HapticFeedback.mediumImpact();
                          _showIdentityMenu(context, record, isActive);
                        },
                        borderRadius: BorderRadius.circular(20),
                         child: Padding(
                           padding: EdgeInsets.all(MediaQuery.of(context).size.width < 380 ? 16 : 20),
                           child: Row(
                             children: [
                               // Avatar with gradient
                               Container(
                                 width: MediaQuery.of(context).size.width < 380 ? 50 : 60,
                                 height: MediaQuery.of(context).size.width < 380 ? 50 : 60,
                                 decoration: BoxDecoration(
                                   gradient: LinearGradient(
                                     begin: Alignment.topLeft,
                                     end: Alignment.bottomRight,
                                     colors: isActive
                                         ? [
                                             Theme.of(context).colorScheme.primary,
                                             Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                           ]
                                         : [
                                             Theme.of(context).colorScheme.primary,
                                             Theme.of(context).colorScheme.secondary,
                                           ],
                                   ),
                                   shape: BoxShape.circle,
                                   boxShadow: [
                                     BoxShadow(
                                       color: isActive
                                           ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                                           : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                       blurRadius: isActive ? 12 : 10,
                                       offset: const Offset(0, 4),
                                     ),
                                   ],
                                 ),
                                 child: Stack(
                                   children: [
                                     Center(
                                       child: Text(
                                         _avatarInitialsForIdentity(record),
                                         style: TextStyle(
                                           color: Colors.white,
                                           fontWeight: FontWeight.w700,
                                           fontSize: MediaQuery.of(context).size.width < 380 ? 18 : 20,
                                         ),
                                       ),
                                     ),
                                     if (isActive)
                                       Positioned(
                                         right: 0,
                                         bottom: 0,
                                         child: Container(
                                           width: 18,
                                           height: 18,
                                           decoration: BoxDecoration(
                                             color: Colors.white,
                                             shape: BoxShape.circle,
                                             border: Border.all(
                                               color: Theme.of(context).colorScheme.primary,
                                               width: 2,
                                             ),
                                           ),
                                           child: Icon(
                                             Icons.check_rounded,
                                             size: 12,
                                             color: Theme.of(context).colorScheme.primary,
                                           ),
                                         ),
                                       ),
                                   ],
                                 ),
                               ),
                               
                               SizedBox(width: MediaQuery.of(context).size.width < 380 ? 16 : 20),
                              
                              // Identity info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                     Text(
                                       _displayNameForIdentity(record),
                                       style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                         fontWeight: FontWeight.w700,
                                         fontSize: MediaQuery.of(context).size.width < 380 ? 16 : 18,
                                         letterSpacing: -0.5,
                                       ),
                                       overflow: TextOverflow.ellipsis,
                                       maxLines: 1,
                                     ),
                                     SizedBox(height: MediaQuery.of(context).size.width < 380 ? 6 : 8),
                                     Row(
                                       children: [
                                         Container(
                                           padding: EdgeInsets.symmetric(
                                             horizontal: MediaQuery.of(context).size.width < 380 ? 10 : 12, 
                                             vertical: MediaQuery.of(context).size.width < 380 ? 4 : 6,
                                           ),
                                           decoration: BoxDecoration(
                                             color: isActive
                                                 ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                                                 : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                                             borderRadius: BorderRadius.circular(MediaQuery.of(context).size.width < 380 ? 10 : 12),
                                             border: Border.all(
                                               color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                               width: 1,
                                             ),
                                           ),
                                           child: Text(
                                             '$principalPrefix...',
                                             style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                               color: isActive
                                                   ? Theme.of(context).colorScheme.onPrimary
                                                   : Theme.of(context).colorScheme.onPrimaryContainer,
                                               fontWeight: FontWeight.w600,
                                               fontSize: MediaQuery.of(context).size.width < 380 ? 10 : 11,
                                               letterSpacing: 0.5,
                                             ),
                                           ),
                                         ),
                                         if (isActive) ...[
                                           const SizedBox(width: 6),
                                           Container(
                                             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                             decoration: BoxDecoration(
                                               color: Theme.of(context).colorScheme.primary,
                                               borderRadius: BorderRadius.circular(8),
                                             ),
                                             child: Text(
                                               'ACTIVE',
                                               style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                 color: Theme.of(context).colorScheme.onPrimary,
                                                 fontWeight: FontWeight.w700,
                                                 fontSize: 9,
                                               ),
                                             ),
                                           ),
                                         ],
                                       ],
                                     ),
                                     // Only show account status section if there's something to display
                                     if (_shouldShowAccountStatus(record)) ...[
                                       SizedBox(height: MediaQuery.of(context).size.width < 380 ? 6 : 8),
                                       _buildAccountStatus(record),
                                       SizedBox(height: MediaQuery.of(context).size.width < 380 ? 6 : 8),
                                     ],
                                     Text(
                                       _subtitleFor(record),
                                       style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                         color: Theme.of(context).colorScheme.onSurfaceVariant,
                                         fontSize: MediaQuery.of(context).size.width < 380 ? 11 : 12,
                                       ),
                                       overflow: TextOverflow.ellipsis,
                                       maxLines: 1,
                                     ),
                                  ],
                                ),
                              ),
                              
                              // Action menu
                              PopupMenuButton<_IdentityAction>(
                                onSelected: (_IdentityAction action) {
                                  HapticFeedback.selectionClick();
                                  _handleAction(action, record);
                                },
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                itemBuilder: (BuildContext context) {
                                  final Account? account = _accountController.accountForIdentity(record);
                                  return _buildMenuItems(isActive, account);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        ),
      ),
      floatingActionButton: AnimatedFab(
        heroTag: 'identities_fab',
        onPressed: _controller.isBusy ? null : () {
          HapticFeedback.mediumImpact();
          _showCreationSheet();
        },
        icon: const Icon(Icons.add_rounded),
        label: 'New Identity',
      ),
    );
  }

  String _subtitleFor(IdentityRecord record) {
    final DateTime localTime = record.createdAt.toLocal();
    final String timestamp = '${localTime.year.toString().padLeft(4, '0')}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')} '
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    final String algorithm = keyAlgorithmToString(record.algorithm).toUpperCase();
    return '$algorithm • $timestamp';
  }

  /// Check if we should display the account status section
  bool _shouldShowAccountStatus(IdentityRecord record) {
    final loadState = _accountLoadStates[record.id] ?? AccountLoadState.notLoaded;
    // Show if loading, error, or no account (register button)
    if (loadState == AccountLoadState.loading || loadState == AccountLoadState.error) {
      return true;
    }
    // Show register button if no account exists
    final Account? account = _accountController.accountForIdentity(record);
    return account == null;
  }

  Widget _buildAccountStatus(IdentityRecord record) {
    final loadState = _accountLoadStates[record.id] ?? AccountLoadState.notLoaded;

    // Show loading indicator
    if (loadState == AccountLoadState.loading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Loading...',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    // Show error indicator
    if (loadState == AccountLoadState.error) {
      final errorMessage = _accountLoadErrors[record.id] ?? 'Error loading account';
      return InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _retryLoadAccount(record);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 14,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  errorMessage,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.refresh,
                size: 14,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
          ),
        ),
      );
    }

    // No account exists - show register button
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        _navigateToAccountRegistration(record);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 6),
            Text(
              'Register an Account',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.add_circle_outline,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncognitoModeCard(BuildContext context, bool isActive) {
    return Card(
      elevation: isActive ? 8 : 4,
      shadowColor: isActive
          ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4)
          : Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isActive
            ? BorderSide(
                color: Theme.of(context).colorScheme.secondary,
                width: 2,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () async {
          HapticFeedback.lightImpact();
          if (!isActive) {
            final messenger = ScaffoldMessenger.of(context);
            final secondaryColor = Theme.of(context).colorScheme.secondary;
            await _controller.setActiveIdentity(null);
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: const Text('Incognito mode activated'),
                backgroundColor: secondaryColor,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width < 380 ? 16 : 20),
          child: Row(
            children: [
              // Incognito icon with gradient
              Container(
                width: MediaQuery.of(context).size.width < 380 ? 50 : 60,
                height: MediaQuery.of(context).size.width < 380 ? 50 : 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isActive
                        ? [
                            Theme.of(context).colorScheme.secondary,
                            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.8),
                          ]
                        : [
                            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.7),
                            Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.7),
                          ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: isActive
                          ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5)
                          : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
                      blurRadius: isActive ? 12 : 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        Icons.visibility_off_outlined,
                        color: Colors.white,
                        size: MediaQuery.of(context).size.width < 380 ? 24 : 28,
                      ),
                    ),
                    if (isActive)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.secondary,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              SizedBox(width: MediaQuery.of(context).size.width < 380 ? 16 : 20),

              // Incognito mode info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incognito mode',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: MediaQuery.of(context).size.width < 380 ? 16 : 18,
                        letterSpacing: -0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    SizedBox(height: MediaQuery.of(context).size.width < 380 ? 6 : 8),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: MediaQuery.of(context).size.width < 380 ? 10 : 12,
                            vertical: MediaQuery.of(context).size.width < 380 ? 4 : 6,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.8)
                                : Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(MediaQuery.of(context).size.width < 380 ? 10 : 12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'Read-only',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: isActive
                                  ? Theme.of(context).colorScheme.onSecondary
                                  : Theme.of(context).colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                              fontSize: MediaQuery.of(context).size.width < 380 ? 10 : 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'ACTIVE',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: MediaQuery.of(context).size.width < 380 ? 6 : 8),
                    Text(
                      'Browse without signing or publishing',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: MediaQuery.of(context).size.width < 380 ? 11 : 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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

enum _IdentityAction { setActive, openAccountProfile, addKeyToAccount, showKeypairInfo, manageKeypairs, delete }
