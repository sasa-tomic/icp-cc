import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/marketplace_script.dart';
import '../theme/app_design_system.dart';
import '../theme/modern_components.dart';

class ScriptCard extends StatelessWidget {
  final MarketplaceScript script;
  final VoidCallback onTap;
  final VoidCallback? onFavorite;
  final bool isFavorite;
  final VoidCallback? onDownload;
  final bool isDownloading;
  final bool isDownloaded;
  final VoidCallback? onQuickPreview;
  final VoidCallback? onShare;

  const ScriptCard({
    super.key,
    required this.script,
    required this.onTap,
    this.onFavorite,
    this.isFavorite = false,
    this.onDownload,
    this.isDownloading = false,
    this.isDownloaded = false,
    this.onQuickPreview,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'script_${script.id}',
      child: ModernCard(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Script icon/image with overlay actions
            Expanded(
              flex: 2,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          context.colors.primary.withValues(alpha: 0.8),
                          context.colors.secondary.withValues(alpha: 0.6),
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDesignSystem.radius20)),
                    ),
                    child: script.iconUrl != null
                        ? ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDesignSystem.radius20)),
                            child: CachedNetworkImage(
                              imageUrl: script.iconUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      context.colors.primary.withValues(alpha: 0.3),
                                      context.colors.secondary.withValues(alpha: 0.2),
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.code,
                                    size: 48,
                                    color: context.colors.onPrimary.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.grey.withValues(alpha: 0.3),
                                      Colors.grey.withValues(alpha: 0.2),
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.code_off,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.code_rounded,
                              size: 48,
                              color: context.colors.onPrimary.withValues(alpha: 0.9),
                            ),
                          ),
                  ),
                  
                  // Gradient overlay for better text readability
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.3),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppDesignSystem.radius20)),
                      ),
                    ),
                  ),
                  
                  // Quick action overlay
                  Positioned(
                    top: AppDesignSystem.spacing8,
                    right: AppDesignSystem.spacing8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Quick preview button
                        if (onQuickPreview != null)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.visibility, size: 16, color: Colors.white),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                onQuickPreview!();
                              },
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: 'Quick Preview',
                            ),
                          ),

                        const SizedBox(width: AppDesignSystem.spacing4),

                        // Share button
                        if (onShare != null)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.share, size: 16, color: Colors.white),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                onShare!();
                              },
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              tooltip: 'Share',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Script information
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.spacing16, vertical: AppDesignSystem.spacing12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title with better typography
                    Text(
                      script.title,
                      style: context.textStyles.heading5.copyWith(
                        fontSize: 15,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: AppDesignSystem.spacing4),

                    // Category with modern chip
                    ModernChip(
                      label: script.category,
                      selected: true,
                      backgroundColor: context.colors.primaryContainer,
                    ),

                    const Spacer(),

                    // Author and price row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Author with avatar-like design
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: context.colors.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    script.authorName.isNotEmpty 
                                        ? script.authorName[0].toUpperCase()
                                        : 'A',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: context.colors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  script.authorName,
                                  style: context.textStyles.bodySmall.copyWith(
                                    color: context.colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Price or Free indicator
                        if (script.price > 0)
                          ModernChip(
                            label: '\$${script.price.toStringAsFixed(2)}',
                            selected: true,
                            backgroundColor: AppDesignSystem.successLight,
                          )
                        else
                          ModernChip(
                            label: 'FREE',
                            selected: true,
                            backgroundColor: AppDesignSystem.accentLight,
                          ),
                      ],
                    ),

                    const SizedBox(height: AppDesignSystem.spacing8),

                    // Rating and downloads
                    Row(
                      children: [
                        // Rating with stars
                        ModernChip(
                          label: script.rating > 0
                              ? '${script.rating.toStringAsFixed(1)} ⭐'
                              : 'New',
                          icon: script.rating > 0 
                              ? Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade600)
                              : null,
                          selected: script.rating > 0,
                          backgroundColor: script.rating > 0 
                              ? Colors.amber.withValues(alpha: 0.1)
                              : context.colors.surfaceContainerHighest,
                        ),

                        const SizedBox(width: AppDesignSystem.spacing8),

                        // Downloads
                        ModernChip(
                          label: _formatDownloads(script.downloads),
                          icon: Icon(Icons.download_rounded, size: 12, color: context.colors.primary),
                          selected: true,
                          backgroundColor: context.colors.primaryContainer,
                        ),
                      ],
                    ),

                    // Action buttons
                    const SizedBox(height: AppDesignSystem.spacing8),
                    
                    // Prominent download button for free scripts
                    if (onDownload != null && script.price == 0)
                      ModernButton(
                        onPressed: isDownloading ? null : () {
                          HapticFeedback.mediumImpact();
                          onDownload!();
                        },
                        variant: isDownloaded ? ModernButtonVariant.secondary : ModernButtonVariant.primary,
                        size: ModernButtonSize.medium,
                        fullWidth: true,
                        loading: isDownloading,
                        icon: Icon(
                          isDownloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        child: Text(
                          isDownloading 
                              ? 'Downloading...' 
                              : isDownloaded 
                                  ? 'Downloaded ✓' 
                                  : 'Download FREE',
                        ),
                      )
                    else if (onDownload != null && script.price > 0)
                      ModernButton(
                        onPressed: isDownloading ? null : () {
                          HapticFeedback.mediumImpact();
                          onDownload!();
                        },
                        variant: ModernButtonVariant.outline,
                        size: ModernButtonSize.medium,
                        fullWidth: true,
                        loading: isDownloading,
                        icon: Icon(
                          isDownloaded ? Icons.check_circle_rounded : Icons.shopping_cart_rounded,
                          size: 18,
                        ),
                        child: Text(
                          isDownloading 
                              ? 'Processing...' 
                              : isDownloaded 
                                  ? 'Purchased ✓' 
                                  : '\$${script.price.toStringAsFixed(2)}',
                        ),
                      )
                    else
                      // Small action buttons for other cases
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Favorite button (if provided)
                          if (onFavorite != null)
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                onFavorite!();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isFavorite 
                                      ? Colors.red.withValues(alpha: 0.1) 
                                      : context.colors.surfaceContainerHighest,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isFavorite 
                                        ? Colors.red.withValues(alpha: 0.3) 
                                        : context.colors.outline.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  color: isFavorite ? Colors.red.shade500 : context.colors.onSurfaceVariant,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDownloads(int downloads) {
    if (downloads < 1000) {
      return downloads.toString();
    } else if (downloads < 1000000) {
      return '${(downloads / 1000).toStringAsFixed(1)}k';
    } else {
      return '${(downloads / 1000000).toStringAsFixed(1)}M';
    }
  }
}