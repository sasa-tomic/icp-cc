import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/account.dart';
import '../models/profile.dart';
import '../models/profile_keypair.dart';
import '../controllers/account_controller.dart';
import '../controllers/profile_controller.dart';
import '../services/connectivity_service.dart';
import '../services/secure_storage_readiness.dart';
import '../theme/app_design_system.dart';

class UnifiedSetupResult {
  const UnifiedSetupResult({
    required this.profile,
    this.account,
  });

  final Profile profile;
  final Account? account;

  bool get hasAccount => account != null;
}

class UnifiedSetupWizard extends StatefulWidget {
  const UnifiedSetupWizard({
    required this.profileController,
    required this.accountController,
    this.initialDisplayName,
    this.secureStorageReadiness,
    this.connectivityProbe,
    super.key,
  });

  final ProfileController profileController;
  final AccountController accountController;
  final String? initialDisplayName;

  /// Optional secure-storage readiness gate. When provided (production wiring
  /// in `main.dart`), the wizard probes whether secrets can be persisted before
  /// letting the user create a profile. On [StorageUnavailable] it renders a
  /// blocking, actionable panel (WU-S2 / NEW-4) instead of letting
  /// `createProfile` throw a raw `PlatformException` (NEW-2). When `null`
  /// (legacy callers / unit tests that inject a fake ProfileController), the
  /// gate is skipped and the form is shown directly.
  final SecureStorageReadiness? secureStorageReadiness;

  /// Optional reachability probe invoked before [ProfileController.createProfile]
  /// when the user has entered a marketplace username (UX-21 / UX-H7). Lets the
  /// wizard fail fast on offline with a friendly inline error, instead of
  /// persisting a profile and rolling it back via UX-CRIT-2's path. When `null`
  /// (production wiring), the default backend health probe is used. When the
  /// username is empty (local-only profile), the probe is skipped entirely —
  /// local profile creation needs no connectivity.
  final ConnectivityProbe? connectivityProbe;

  @override
  State<UnifiedSetupWizard> createState() => _UnifiedSetupWizardState();
}

class _UnifiedSetupWizardState extends State<UnifiedSetupWizard> {
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _usernameFocusNode = FocusNode();

  bool _isValidating = false;
  UsernameValidation? _usernameValidation;
  Timer? _debounceTimer;

  bool _isCreating = false;
  bool _isSuccess = false;
  UnifiedSetupResult? _result;
  String? _errorMessage;

  // WU-S2 secure-storage readiness gate state.
  StorageReadiness? _readiness;
  bool _isCheckingReadiness = false;
  bool _showTechnicalDetails = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDisplayName != null) {
      _displayNameController.text = widget.initialDisplayName!;
    }
    // Probe readiness once on entry so the user learns immediately (WU-S2).
    if (widget.secureStorageReadiness != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runReadinessCheck());
    }
  }

  Future<void> _runReadinessCheck() async {
    final service = widget.secureStorageReadiness;
    if (service == null) return;
    setState(() => _isCheckingReadiness = true);
    final StorageReadiness result = await service.check();
    if (!mounted) return;
    setState(() {
      _readiness = result;
      _isCheckingReadiness = false;
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _usernameFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuccess && _result != null) {
      return _buildSuccessScreen();
    }
    // WU-S2: block on secure-storage readiness before exposing profile
    // creation (which would otherwise throw a raw PlatformException — NEW-2/4).
    if (_isCheckingReadiness) {
      return _buildReadinessChecking();
    }
    final readiness = _readiness;
    if (readiness is StorageUnavailable) {
      return _buildReadinessPanel(readiness);
    }
    return _buildSetupForm();
  }

  Widget _buildReadinessChecking() {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close setup',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Get Started',
          style: AppDesignSystem.heading3.copyWith(color: AppDesignSystem.neutral900),
        ),
        centerTitle: true,
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Checking secure storage…'),
          ],
        ),
      ),
    );
  }

  /// WU-S2 / NEW-4: the actionable blocking panel shown when secrets cannot be
  /// persisted. Replaces the raw `PlatformException(…)` banner with a friendly
  /// title, explanation, a **copyable** install command, and a Retry button.
  Widget _buildReadinessPanel(StorageUnavailable unavailable) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close setup',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Setup needed',
          style: AppDesignSystem.heading3.copyWith(color: AppDesignSystem.neutral900),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          const SizedBox(height: 8),
          Icon(
            Icons.lock_outline,
            size: 48,
            color: AppDesignSystem.errorDark,
          ),
          const SizedBox(height: 16),
          Text(
            unavailable.reason,
            style: AppDesignSystem.heading2.copyWith(
              color: context.colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            unavailable.explanation,
            style: AppDesignSystem.bodyMedium.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (unavailable.fixCommand.isNotEmpty) ...[
            Text(
              'Install command',
              style: AppDesignSystem.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: context.colors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: context.colors.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      unavailable.fixCommand,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    tooltip: 'Copy',
                    onPressed: () => _copyToClipboard(unavailable.fixCommand),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            unavailable.fixHint,
            style: AppDesignSystem.bodySmall.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() =>
                  _showTechnicalDetails = !_showTechnicalDetails),
              icon: Icon(
                _showTechnicalDetails
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 20,
              ),
              label: Text(
                _showTechnicalDetails ? 'Hide details' : 'Show details',
                style: AppDesignSystem.bodySmall,
              ),
            ),
          ),
          // Only build the raw technical detail when the user opts in, so the
          // verbatim 'PlatformException(…)' string is NEVER in the widget tree
          // (and thus never accidentally painted/announced) by default (NEW-4).
          if (_showTechnicalDetails)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText(
                unavailable.technicalDetail,
                style: AppDesignSystem.caption.copyWith(
                  fontFamily: 'monospace',
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _runReadinessCheck,
            icon: const Icon(Icons.refresh),
            label: const Text(
              'Retry',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppDesignSystem.primaryLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied install command'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSetupForm() {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close setup',
          onPressed: _isCreating ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Get Started',
          style: AppDesignSystem.heading3.copyWith(
            color: AppDesignSystem.neutral900,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Create Your Profile',
                style: AppDesignSystem.heading2.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set up your profile to start creating and running scripts.',
                style: AppDesignSystem.bodyMedium.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              _displayNameField(),
              const SizedBox(height: 24),
              _usernameSection(),
              const SizedBox(height: 32),
              if (_errorMessage != null) ...[
                _buildErrorBanner(_errorMessage!),
                const SizedBox(height: 16),
              ],
              _buildCreateButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _displayNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Display Name',
          style: AppDesignSystem.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: context.colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _displayNameController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'How should we call you?',
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => _usernameFocusNode.requestFocus(),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Display name is required';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _usernameSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Marketplace username (optional)',
          style: AppDesignSystem.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: context.colors.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Create a marketplace account to share scripts and interact with the community',
          style: AppDesignSystem.bodySmall.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _usernameController,
          focusNode: _usernameFocusNode,
          decoration: InputDecoration(
            hintText: 'Choose a username',
            prefixIcon: const Icon(Icons.alternate_email),
            suffixIcon: _buildUsernameValidationIcon(),
            errorText: _usernameValidation?.isValid == false
                ? _usernameValidation!.error
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onChanged: _onUsernameChanged,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) {
            if (_canCreate && !_isCreating) _handleCreate();
          },
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_-]')),
          ],
        ),
        const SizedBox(height: 8),
        _buildUsernameRules(),
      ],
    );
  }

  Widget _buildUsernameValidationIcon() {
    if (_isValidating) {
      return const Padding(
        padding: EdgeInsets.all(12.0),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_usernameValidation == null || _usernameController.text.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_usernameValidation!.isValid) {
      return const Icon(
        Icons.check_circle,
        color: AppDesignSystem.successLight,
      );
    }
    return const Icon(
      Icons.cancel,
      color: AppDesignSystem.errorLight,
    );
  }

  Widget _buildUsernameRules() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Username requirements:',
          style: AppDesignSystem.bodySmall.copyWith(
            color: AppDesignSystem.neutral600,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _buildRuleChip('3-32 chars'),
            _buildRuleChip('Lowercase'),
            _buildRuleChip('a-z, 0-9, _, -'),
          ],
        ),
      ],
    );
  }

  Widget _buildRuleChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppDesignSystem.neutral100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppDesignSystem.caption.copyWith(
          color: AppDesignSystem.neutral600,
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppDesignSystem.errorLight.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppDesignSystem.errorLight.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: AppDesignSystem.errorDark,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppDesignSystem.bodySmall.copyWith(
                color: AppDesignSystem.errorDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateButton() {
    final canCreate = _canCreate;

    return FilledButton(
      onPressed: (canCreate && !_isCreating) ? _handleCreate : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: AppDesignSystem.primaryLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isCreating
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : const Text(
              'Get Started',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }

  Widget _buildSuccessScreen() {
    final result = _result!;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: AppDesignSystem.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: AppDesignSystem.shadowColored,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Success!',
                style: AppDesignSystem.heading1.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                result.hasAccount
                    ? 'Your profile and marketplace account are ready.'
                    : 'Your profile is ready to use.',
                style: AppDesignSystem.bodyMedium.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildSuccessDetails(result),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(context, result),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  backgroundColor: AppDesignSystem.primaryLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Start Exploring',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessDetails(UnifiedSetupResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colors.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          _buildDetailRow(
            icon: Icons.person_outline,
            label: 'Profile',
            value: result.profile.name,
          ),
          if (result.hasAccount) ...[
            const SizedBox(height: 12),
            _buildDetailRow(
              icon: Icons.alternate_email,
              label: 'Username',
              value: '@${result.account!.username}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: context.colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppDesignSystem.caption.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: AppDesignSystem.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onUsernameChanged(String value) {
    _debounceTimer?.cancel();

    if (value.isEmpty) {
      setState(() {
        _usernameValidation = null;
        _isValidating = false;
      });
      return;
    }

    setState(() {
      _isValidating = true;
    });

    _debounceTimer = Timer(AppDurations.debounce, () {
      _validateUsername(value);
    });
  }

  Future<void> _validateUsername(String username) async {
    final normalized = username.toLowerCase();

    final formatResult = widget.accountController.validateUsername(normalized);
    if (!formatResult.isValid) {
      setState(() {
        _usernameValidation = formatResult;
        _isValidating = false;
      });
      return;
    }

    try {
      final isAvailable =
          await widget.accountController.isUsernameAvailable(normalized);
      setState(() {
        _usernameValidation = isAvailable
            ? const UsernameValidation(isValid: true)
            : UsernameValidation.invalid('Username already taken');
        _isValidating = false;
      });
    } catch (e) {
      setState(() {
        _usernameValidation =
            UsernameValidation.invalid('Failed to check availability');
        _isValidating = false;
      });
    }
  }

  bool get _canCreate {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) return false;

    final username = _usernameController.text.trim();
    if (username.isEmpty) return true;

    return _usernameValidation?.isValid == true;
  }

  Future<bool> _runConnectivityProbe() async {
    final injected = widget.connectivityProbe;
    if (injected != null) return injected();
    // Production wiring: a one-shot ConnectivityService that runs the
    // platform-default backend health probe (HTTP GET /api/v1/health on
    // native; navigator.onLine on web). Cheap to construct; disposed once.
    final service = ConnectivityService();
    try {
      return await service.checkConnectivity();
    } finally {
      await service.dispose();
    }
  }

  Future<void> _handleCreate() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final username = _usernameController.text.trim();
    if (username.isNotEmpty && _usernameValidation?.isValid != true) {
      setState(() => _isValidating = true);
      await _validateUsername(username);
      setState(() => _isValidating = false);
      if (_usernameValidation?.isValid != true) return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    // UX-21 / UX-H7: if the user intends to register a marketplace account,
    // probe the backend BEFORE createProfile so we fail fast on offline with a
    // friendly inline error (no orphan-profile churn, no waiting for a network
    // timeout). Skipped when the username is empty — a local-only profile
    // needs no backend.
    if (username.isNotEmpty) {
      final reachable = await _runConnectivityProbe();
      if (!mounted) return;
      if (!reachable) {
        setState(() {
          _errorMessage =
              "Can't reach the marketplace backend. Check your connection and try again.";
          _isCreating = false;
        });
        return;
      }
    }

    try {
      final displayName = _displayNameController.text.trim();
      final normalizedUsername =
          username.isNotEmpty ? username.toLowerCase() : null;

      var profile = await widget.profileController.createProfile(
        profileName: displayName,
        algorithm: KeyAlgorithm.ed25519,
        setAsActive: true,
      );

      Account? account;
      if (normalizedUsername != null && normalizedUsername.isNotEmpty) {
        try {
          account = await widget.accountController.registerAccount(
            keypair: profile.primaryKeypair,
            username: normalizedUsername,
            displayName: displayName,
          );
        } catch (e) {
          // UX-CRIT-2: `createProfile` already persisted the profile + keypair
          // to secure storage. If marketplace registration fails, roll the
          // profile back so a retry doesn't fork into a SECOND orphan profile
          // (the original was created, but the user thinks it wasn't).
          await widget.profileController.deleteProfile(profile.id);
          setState(() {
            _errorMessage =
                'Profile created locally, but marketplace registration '
                'failed: $e. Your profile has been removed — please try again.';
            _isCreating = false;
          });
          return;
        }

        await widget.profileController.updateProfileUsername(
          profileId: profile.id,
          username: normalizedUsername,
        );

        profile = profile.copyWith(username: normalizedUsername);
      }

      HapticFeedback.heavyImpact();

      setState(() {
        _result = UnifiedSetupResult(profile: profile, account: account);
        _isSuccess = true;
        _isCreating = false;
      });
    } catch (e) {
      // Profile creation itself failed (e.g. secure storage unavailable). No
      // rollback needed because nothing was persisted.
      setState(() {
        _errorMessage = humanizeSecureStorageError(e);
        _isCreating = false;
      });
    }
  }
}
