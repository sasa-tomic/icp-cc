import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/identity_controller.dart';
import '../controllers/account_controller.dart';
import '../models/account.dart';
import '../models/identity_profile.dart';
import '../models/identity_record.dart';
import '../services/secure_identity_repository.dart';
import '../theme/app_design_system.dart';
import '../utils/principal.dart';
import '../widgets/empty_state.dart';
import '../widgets/animated_fab.dart';
import '../widgets/identity_profile_sheet.dart';
import 'account_registration_wizard.dart';
import 'account_profile_screen.dart';

class IdentityHomePage extends StatefulWidget {
  const IdentityHomePage({super.key});

  @override
  State<IdentityHomePage> createState() => _IdentityHomePageState();
}

class _IdentityHomePageState extends State<IdentityHomePage> {
  late final IdentityController _controller;
  late final AccountController _accountController;

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
    // Accounts are populated when user registers or explicitly fetches them
    // We rely on AccountController's cache populated by previous operations
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
    final IdentityRecord? record = await showModalBottomSheet<IdentityRecord>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) => _IdentityCreationSheet(controller: _controller),
    );
    if (!mounted || record == null) {
      return;
    }
    await _controller.setActiveIdentity(record.id);
    if (!mounted) {
      return;
    }
    await _showDetailsDialog(record, title: 'Identity Created');
  }

  Future<void> _showDetailsDialog(IdentityRecord record, {required String title}) async {
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

  Future<void> _editIdentityProfile(IdentityRecord record) async {
    // Show loading indicator while fetching profile from server
    final IdentityProfile? cachedProfile = _controller.profileForRecord(record);

    if (cachedProfile == null && mounted) {
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
    }

    // Ensure profile is loaded before editing
    await _controller.ensureProfileLoaded(record);

    // Close loading dialog if it was shown
    if (cachedProfile == null && mounted) {
      Navigator.of(context).pop();
    }

    final IdentityProfile? existingProfile = _controller.profileForRecord(record);

    if (!mounted) return;
    
    final IdentityProfileDraft? draft = await showIdentityProfileSheet(
      context: context,
      identity: record,
      existingProfile: existingProfile,
    );
    
    if (draft != null && mounted) {
      try {
        await _controller.saveProfile(identity: record, draft: draft);
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully')),
        );
      } catch (error) {
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $error')),
        );
      }
    }
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

    final _IdentityAction? action = await showMenu<_IdentityAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width - 200,
        100,
        20,
        0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: _buildMenuItems(isActive),
    );

    if (action != null) {
      HapticFeedback.selectionClick();
      await _handleAction(action, record);
    }
  }

  List<PopupMenuEntry<_IdentityAction>> _buildMenuItems(bool isActive) {
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
      PopupMenuItem<_IdentityAction>(
        value: _IdentityAction.editProfile,
        child: Row(
          children: [
            const Icon(Icons.person_rounded, size: 20),
            const SizedBox(width: 12),
            const Text('Edit profile'),
          ],
        ),
      ),
      PopupMenuItem<_IdentityAction>(
        value: _IdentityAction.showDetails,
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 20),
            const SizedBox(width: 12),
            const Text('Show details'),
          ],
        ),
      ),
      PopupMenuItem<_IdentityAction>(
        value: _IdentityAction.rename,
        child: Row(
          children: [
            const Icon(Icons.edit_rounded, size: 20),
            const SizedBox(width: 12),
            const Text('Rename'),
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
      case _IdentityAction.showDetails:
        await _showDetailsDialog(record, title: 'Identity details');
        break;
      case _IdentityAction.editProfile:
        await _editIdentityProfile(record);
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
    final TextEditingController controller = TextEditingController(text: record.label);
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
                return null;
              },
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Identity renamed')));
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

  @override
  Widget build(BuildContext context) {
    final List<IdentityRecord> identities = _controller.identities;
    final bool showLoading = _controller.isBusy && identities.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity Manager'),
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
                                         record.label.isNotEmpty 
                                             ? record.label.substring(0, 2).toUpperCase()
                                             : '#',
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
                                       record.label,
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
                                     SizedBox(height: MediaQuery.of(context).size.width < 380 ? 6 : 8),
                                     _buildAccountStatus(record),
                                     SizedBox(height: MediaQuery.of(context).size.width < 380 ? 6 : 8),
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
                                itemBuilder: (BuildContext context) => _buildMenuItems(isActive),
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

  Widget _buildAccountStatus(IdentityRecord record) {
    final Account? account = _accountController.accountForIdentity(record);

    if (account != null) {
      // Show account badge
      return InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          _navigateToAccountProfile(account, record);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                size: 14,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              const SizedBox(width: 6),
              Text(
                '@${account.username}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Show register button
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
        mnemonic: _mnemonicController.text.trim().isEmpty ? null : _mnemonicController.text.trim(),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create identity: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewInsets = MediaQuery.of(context).viewInsets;
     final safeAreaPadding = MediaQuery.of(context).padding;
     
     return Padding(
       padding: EdgeInsets.only(
         bottom: viewInsets.bottom + safeAreaPadding.bottom,
         left: 24,
         right: 24,
         top: 24,
       ),
       child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: <Widget>[
            Text('Create a new identity', style: Theme.of(context).textTheme.titleLarge),
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
                    DropdownMenuItem<KeyAlgorithm>(value: KeyAlgorithm.ed25519, child: Text('Ed25519 (recommended)')),
                    DropdownMenuItem<KeyAlgorithm>(value: KeyAlgorithm.secp256k1, child: Text('secp256k1 (dfx-compatible)')),
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
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bolt),
              label: const Text('Create identity'),
            ),
          ],
        ),
      ),
    );
  }
}

// Empty state moved to shared widget

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

enum _IdentityAction { setActive, editProfile, showDetails, rename, delete }
