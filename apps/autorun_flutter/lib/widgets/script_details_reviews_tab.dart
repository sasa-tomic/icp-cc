import 'package:flutter/material.dart';

import '../models/marketplace_script.dart';
import '../models/purchase_record.dart';
import '../theme/app_design_system.dart';
import 'script_details_helpers.dart';

/// Reviews tab of [ScriptDetailsDialog].
///
/// Pure display widget: the parent dialog owns the load lifecycle (it fires
/// `_loadReviews()` lazily the first time this tab is selected and streams the
/// result back here via these fields), so this widget holds no state of its
/// own. Extracted verbatim from `script_details_dialog.dart` (TD-11) — the
/// only changes are the leading `_` dropped from the helpers that became this
/// widget's private methods, and `BuildContext` threaded through where the
/// original `State.context` was read implicitly. Behaviour is byte-identical.
class ScriptDetailsReviewsTab extends StatelessWidget {
  const ScriptDetailsReviewsTab({
    super.key,
    required this.script,
    required this.reviews,
    required this.isLoadingReviews,
    this.reviewsError,
  });

  final MarketplaceScript script;
  final List<ScriptReview> reviews;
  final bool isLoadingReviews;
  final String? reviewsError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRatingSummary(context),
          const SizedBox(height: 20),
          Expanded(
            child: _buildReviewsList(context),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSummary(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                script.rating > 0
                    ? script.rating.toStringAsFixed(1)
                    : '-',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return Icon(
                    index < script.rating.round()
                        ? Icons.star
                        : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(
                '${script.reviewCount} reviews',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: _buildRatingDistribution(context),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingDistribution(BuildContext context) {
    final distribution = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final review in reviews) {
      if (review.rating >= 1 && review.rating <= 5) {
        distribution[review.rating] = (distribution[review.rating] ?? 0) + 1;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [5, 4, 3, 2, 1].map((star) {
        final count = distribution[star] ?? 0;
        final percentage = reviews.isEmpty ? 0.0 : count / reviews.length;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Text(
                '$star',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 4),
              Icon(Icons.star, size: 12, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildReviewsList(BuildContext context) {
    if (isLoadingReviews) {
      return const Center(child: CircularProgressIndicator());
    }

    if (reviewsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            reviewsError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (reviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.rate_review_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No reviews yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to review this script!',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: reviews.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final review = reviews[index];
        return _buildReviewItem(context, review);
      },
    );
  }

  Widget _buildReviewItem(BuildContext context, ScriptReview review) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return Icon(
                    index < review.rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Colors.amber,
                  );
                }),
              ),
              const SizedBox(width: 8),
              if (review.isVerifiedPurchase) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppDesignSystem.successColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified,
                        size: 12,
                        color: AppDesignSystem.successDark,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Verified',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppDesignSystem.successDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              Text(
                formatDate(review.createdAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
