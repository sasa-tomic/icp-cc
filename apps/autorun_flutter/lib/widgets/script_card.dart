import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/marketplace_script.dart';

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
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Script icon/image with overlay actions
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                      child: script.iconUrl != null
                          ? CachedNetworkImage(
                              imageUrl: script.iconUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                      Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.code,
                                    size: 48,
                                    color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7),
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
                            )
                          : Center(
                              child: Icon(
                                Icons.code_rounded,
                                size: 48,
                                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.9),
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
                        ),
                      ),
                    ),
                    
                    // Quick action overlay
                    Positioned(
                      top: 12,
                      right: 12,
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
                          
                          const SizedBox(width: 8),
                          
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
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title with better typography
                    Text(
                      script.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 8),

                    // Category with modern pill design
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        script.category,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Author and price row with better spacing
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
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
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
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  script.authorName,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

                        // Price or Free indicator with modern design
                        if (script.price > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.green.shade400,
                                  Colors.green.shade300,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.green.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '\$${script.price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade400,
                                  Colors.blue.shade300,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Text(
                              'FREE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Rating and downloads with better visual design
                    Row(
                      children: [
                        // Rating with stars
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: script.rating > 0 ? Colors.amber.shade600 : Colors.grey.shade400,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                script.rating > 0
                                    ? script.rating.toStringAsFixed(1)
                                    : 'New',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: script.rating > 0 ? Colors.amber.shade700 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Downloads with icon
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.download_rounded,
                                size: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDownloads(script.downloads),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Action buttons with enhanced design
                    const SizedBox(height: 12),
                    
                    // Prominent download button for free scripts
                    if (onDownload != null && script.price == 0)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isDownloading ? null : () {
                            HapticFeedback.mediumImpact();
                            onDownload!();
                          },
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: isDownloading
                                ? SizedBox(
                                    key: const ValueKey('loading'),
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    key: const ValueKey('icon'),
                                    isDownloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                                    size: 18,
                                  ),
                          ),
                          label: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              isDownloading 
                                  ? 'Downloading...' 
                                  : isDownloaded 
                                      ? 'Downloaded ✓' 
                                      : 'Download FREE',
                              key: ValueKey(isDownloading ? 'downloading' : (isDownloaded ? 'downloaded' : 'download')),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: isDownloaded 
                                ? Colors.green.shade500 
                                : Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            elevation: 4,
                            shadowColor: (isDownloaded 
                                ? Colors.green 
                                : Theme.of(context).colorScheme.primary).withValues(alpha: 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      )
                    else if (onDownload != null && script.price > 0)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: isDownloading ? null : () {
                            HapticFeedback.mediumImpact();
                            onDownload!();
                          },
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: isDownloading
                                ? SizedBox(
                                    key: const ValueKey('loading'),
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  )
                                : Icon(
                                    key: const ValueKey('icon'),
                                    isDownloaded ? Icons.check_circle_rounded : Icons.shopping_cart_rounded,
                                    size: 18,
                                  ),
                          ),
                          label: Text(
                            isDownloading 
                                ? 'Processing...' 
                                : isDownloaded 
                                    ? 'Purchased ✓' 
                                    : '\$${script.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      )
                    else
                      // Small action buttons for other cases
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Favorite button (if provided)
                          if (onFavorite != null) ...[
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
                                      : Colors.grey.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isFavorite 
                                        ? Colors.red.withValues(alpha: 0.3) 
                                        : Colors.grey.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  color: isFavorite ? Colors.red.shade500 : Colors.grey.shade600,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
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