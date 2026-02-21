import 'package:flutter/material.dart';
import '../services/marketplace_open_api_service.dart';

/// A compact banner displaying marketplace statistics.
///
/// Shows key metrics like total scripts, authors, and downloads in a thin
/// horizontal bar. Handles loading state with shimmer and gracefully hides
/// on error.
class MarketplaceStatsBanner extends StatelessWidget {
  const MarketplaceStatsBanner({
    super.key,
    this.stats,
    this.isLoading = false,
    this.hasError = false,
  });

  /// The marketplace statistics to display.
  /// If null and not loading/error, banner will be hidden.
  final MarketplaceStats? stats;

  /// Whether the stats are currently loading.
  /// Shows a shimmer placeholder when true.
  final bool isLoading;

  /// Whether an error occurred loading stats.
  /// Banner will be hidden when true.
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    // Hide on error - graceful degradation
    if (hasError) {
      return const SizedBox.shrink();
    }

    // Show shimmer while loading
    if (isLoading) {
      return _buildShimmer(context);
    }

    // Hide if no stats available
    if (stats == null) {
      return const SizedBox.shrink();
    }

    return _buildStatsContent(context);
  }

  Widget _buildShimmer(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildShimmerItem(context),
          _buildSeparator(context),
          _buildShimmerItem(context),
          _buildSeparator(context),
          _buildShimmerItem(context),
        ],
      ),
    );
  }

  Widget _buildShimmerItem(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 80,
      height: 16,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildStatsContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStatItem(
            context,
            value: _formatNumber(stats!.totalScripts),
            label: 'scripts',
          ),
          _buildSeparator(context),
          _buildStatItem(
            context,
            value: _formatNumber(stats!.totalAuthors),
            label: 'authors',
          ),
          _buildSeparator(context),
          _buildStatItem(
            context,
            value: _formatNumber(stats!.totalDownloads),
            label: 'downloads',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String value,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSeparator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        '•',
        style: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  /// Format large numbers for display (e.g., 1.5M, 10K)
  String _formatNumber(int number) {
    if (number >= 1000000) {
      final millions = number / 1000000.0;
      return '${_formatDecimal(millions)}M';
    } else if (number >= 10000) {
      final thousands = number / 1000.0;
      return '${_formatDecimal(thousands)}K';
    } else if (number >= 1000) {
      final thousands = number / 1000.0;
      return '${_formatDecimal(thousands)}K';
    }
    return number.toString();
  }

  /// Format a decimal number, removing trailing zeros
  String _formatDecimal(double value) {
    // Show one decimal place if needed, otherwise show whole number
    if (value == value.roundToDouble()) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }
}
