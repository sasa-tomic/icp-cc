import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/settings_service.dart';
import '../services/onboarding_progress_service.dart';
import '../services/spotlight_service.dart';
import '../theme/app_design_system.dart';

/// Settings screen for configuring app preferences.
///
/// Displays:
/// - Theme toggle (Light/Dark/System)
/// - App version and build info (tap 7 times to unlock developer options)
/// - External links (Documentation, Report Issue, Marketplace)
/// - Developer info (hidden by default, requires 7 taps on version to unlock)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.settingsService,
    this.onThemeChanged,
    super.key,
  });

  final SettingsService settingsService;
  final VoidCallback? onThemeChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLoading = true;
  bool _developerOptionsEnabled = false;
  int _versionTapCount = 0;

  // App version info - can be updated via package_info_plus if needed
  static const String _appVersion = '1.0.0';
  static const String _buildNumber = '1';
  static const int _tapsRequiredToUnlock = 7;

  // External links
  static const String _documentationUrl = 'https://github.com/kalaj01/icp-cc';
  static const String _reportIssueUrl =
      'https://github.com/kalaj01/icp-cc/issues';
  static const String _marketplaceWebUrl = 'https://icp-mp.kalaj.org';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final themeMode = await widget.settingsService.getThemeMode();
    final developerOptionsEnabled =
        await widget.settingsService.isDeveloperOptionsEnabled();
    if (mounted) {
      setState(() {
        _themeMode = themeMode;
        _developerOptionsEnabled = developerOptionsEnabled;
        _isLoading = false;
      });
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    await widget.settingsService.setThemeMode(mode);
    if (mounted) {
      setState(() {
        _themeMode = mode;
      });
      widget.onThemeChanged?.call();
    }
  }

  void _handleVersionTap() {
    if (_developerOptionsEnabled) {
      // Already enabled, no need to count
      return;
    }

    setState(() {
      _versionTapCount++;
    });

    final remainingTaps = _tapsRequiredToUnlock - _versionTapCount;

    if (remainingTaps <= 0) {
      // Developer options unlocked!
      _enableDeveloperOptions();
    } else {
      // Show remaining taps hint
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Tap $remainingTaps more times to enable developer options'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _enableDeveloperOptions() async {
    await widget.settingsService.setDeveloperOptionsEnabled(true);
    if (!mounted) return;
    setState(() {
      _developerOptionsEnabled = true;
      _versionTapCount = 0;
    });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Developer options enabled!'),
        backgroundColor: AppDesignSystem.successLight,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _clearDeveloperOptions() async {
    await widget.settingsService.clearDeveloperOptions();
    if (!mounted) return;
    setState(() {
      _developerOptionsEnabled = false;
      _versionTapCount = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Developer options cleared'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $urlString'),
          backgroundColor: AppDesignSystem.errorLight,
        ),
      );
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        backgroundColor: AppDesignSystem.successLight,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'Settings',
          style: AppDesignSystem.heading3.copyWith(
            color: context.colors.onSurface,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildOnboardingSection(),
                  const SizedBox(height: 24),
                  _buildThemeSection(),
                  const SizedBox(height: 24),
                  _buildLinksSection(),
                  if (_developerOptionsEnabled) ...[
                    const SizedBox(height: 24),
                    _buildDeveloperSection(),
                  ],
                  const SizedBox(height: 24),
                  _buildAboutSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildOnboardingSection() {
    return _SettingsCard(
      title: 'HELP',
      icon: Icons.help_outline,
      children: [
        _SettingsListTile(
          icon: Icons.rocket_launch_outlined,
          label: 'Getting Started',
          subtitle: 'Show the onboarding guide',
          onTap: _showGettingStartedGuide,
        ),
        _SettingsListTile(
          icon: Icons.tour_outlined,
          label: 'Restart Tour',
          subtitle: 'Show the guided tour again',
          onTap: _restartTour,
        ),
      ],
    );
  }

  Future<void> _showGettingStartedGuide() async {
    final service = OnboardingProgressService();
    await service.reset();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Getting Started guide will appear on the home screen'),
        ),
      );
    }
  }

  Future<void> _restartTour() async {
    final service = SpotlightService();
    await service.resetAndStart();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tour will start shortly'),
        ),
      );
    }
  }

  Widget _buildThemeSection() {
    return _SettingsCard(
      title: 'APPEARANCE',
      icon: Icons.palette_outlined,
      children: [
        _buildThemeOption(
          mode: ThemeMode.system,
          label: 'System',
          subtitle: 'Follow system settings',
          icon: Icons.brightness_auto,
        ),
        _buildThemeOption(
          mode: ThemeMode.light,
          label: 'Light',
          subtitle: 'Always use light theme',
          icon: Icons.light_mode,
        ),
        _buildThemeOption(
          mode: ThemeMode.dark,
          label: 'Dark',
          subtitle: 'Always use dark theme',
          icon: Icons.dark_mode,
        ),
      ],
    );
  }

  Widget _buildThemeOption({
    required ThemeMode mode,
    required String label,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _themeMode == mode;

    return InkWell(
      onTap: () => _setThemeMode(mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? context.colors.primaryContainer.withValues(alpha: 0.3)
              : null,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: context.colors.primary, width: 2)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? context.colors.primary.withValues(alpha: 0.1)
                    : context.colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppDesignSystem.bodyMedium.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? context.colors.primary
                          : context.colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppDesignSystem.bodySmall.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: context.colors.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinksSection() {
    return _SettingsCard(
      title: 'LINKS',
      icon: Icons.link,
      children: [
        _SettingsListTile(
          icon: Icons.menu_book_outlined,
          label: 'Documentation',
          subtitle: 'View guides and API reference',
          onTap: () => _launchUrl(_documentationUrl),
        ),
        _SettingsListTile(
          icon: Icons.bug_report_outlined,
          label: 'Report Issue',
          subtitle: 'Submit a bug report or feature request',
          onTap: () => _launchUrl(_reportIssueUrl),
        ),
        _SettingsListTile(
          icon: Icons.store_outlined,
          label: 'Marketplace Website',
          subtitle: 'Browse scripts on the web',
          onTap: () => _launchUrl(_marketplaceWebUrl),
        ),
      ],
    );
  }

  Widget _buildDeveloperSection() {
    return _SettingsCard(
      title: 'DEVELOPER INFO',
      icon: Icons.code,
      children: [
        _SettingsInfoTile(
          icon: Icons.api,
          label: 'API Endpoint',
          value: AppConfig.apiEndpoint,
          onCopy: () => _copyToClipboard(AppConfig.apiEndpoint, 'API endpoint'),
        ),
        const SizedBox(height: 8),
        _SettingsInfoTile(
          icon: Icons.settings_ethernet,
          label: 'Environment',
          value: AppConfig.environmentName,
        ),
        const SizedBox(height: 16),
        // Clear Developer Options button
        InkWell(
          onTap: _clearDeveloperOptions,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.delete_outline,
                  color: context.colors.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Clear Developer Options',
                  style: AppDesignSystem.bodyMedium.copyWith(
                    color: context.colors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return _SettingsCard(
      title: 'ABOUT',
      icon: Icons.info_outline,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // App icon/logo
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppDesignSystem.primaryGradient,
                ),
                child: const Icon(
                  Icons.flash_on,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'ICP Autorun',
                style: AppDesignSystem.heading4.copyWith(
                  color: AppDesignSystem.primaryDark,
                ),
              ),
              const SizedBox(height: 8),
              // Make version tappable to unlock developer options
              InkWell(
                onTap: _handleVersionTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Version $_appVersion ($_buildNumber)',
                    style: AppDesignSystem.bodyMedium.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Cross-platform scripting for Internet Computer canisters.',
                style: AppDesignSystem.bodySmall.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A settings card with a title and list of children.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: AppDesignSystem.primaryLight,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppDesignSystem.bodySmall.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A list tile for navigation actions.
class _SettingsListTile extends StatelessWidget {
  const _SettingsListTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: context.colors.onSurfaceVariant,
          size: 20,
        ),
      ),
      title: Text(
        label,
        style: AppDesignSystem.bodyMedium.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppDesignSystem.bodySmall.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.open_in_new,
        color: context.colors.onSurfaceVariant,
        size: 18,
      ),
      onTap: onTap,
    );
  }
}

/// An info tile with icon, label, value, and optional copy button.
class _SettingsInfoTile extends StatelessWidget {
  const _SettingsInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: context.colors.onSurfaceVariant,
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppDesignSystem.bodySmall.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppDesignSystem.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        if (onCopy != null)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: onCopy,
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
