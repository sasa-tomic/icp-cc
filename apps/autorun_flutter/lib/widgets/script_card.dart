import 'package:flutter/material.dart';
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
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                          Theme.of(context).colorScheme.primaryContainer,
                          Theme.of(context).colorScheme.secondaryContainer,
                        ],
                      ),
                    ),
                    child: script.iconUrl != null
                        ? CachedNetworkImage(
                            imageUrl: script.iconUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Center(
                              child: Icon(
                                Icons.code,
                                size: 48,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            errorWidget: (context, url, error) => Center(
                              child: Icon(
                                Icons.code_off,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.code,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                  ),
                  
                  // Quick action overlay
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Quick preview button
                        if (onQuickPreview != null)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.visibility, size: 16, color: Colors.white),
                              onPressed: onQuickPreview,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              tooltip: 'Quick Preview',
                            ),
                          ),
                        
                        // Share button
                        if (onShare != null)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.share, size: 16, color: Colors.white),
                              onPressed: onShare,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      script.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Category
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        script.category,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Author and price row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Author
                        Expanded(
                          child: Text(
                            script.authorName,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // Price or Free indicator
                        if (script.price > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '\$${script.price.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.green[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'FREE',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Colors.blue[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Rating and downloads
                    Row(
                      children: [
                        // Rating
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              size: 14,
                              color: script.rating > 0 ? Colors.amber : Colors.grey[400],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              script.rating > 0
                                  ? script.rating.toStringAsFixed(1)
                                  : 'No rating',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),

                        const SizedBox(width: 12),

                        // Downloads
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.download,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _formatDownloads(script.downloads),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Action buttons
                    const SizedBox(height: 8),
                    
                    // Prominent download button for free scripts
                    if (onDownload != null && script.price == 0)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isDownloading ? null : onDownload,
                          icon: isDownloading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                  ),
                                )
                              : Icon(
                                  isDownloaded ? Icons.check_circle : Icons.download,
                                  size: 18,
                                ),
                          label: Text(
                            isDownloading 
                                ? 'Downloading...' 
                                : isDownloaded 
                                    ? 'Downloaded ✓' 
                                    : 'Download FREE',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: isDownloaded 
                                ? Colors.green 
                                : Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      )
                    else if (onDownload != null && script.price > 0)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: isDownloading ? null : onDownload,
                          icon: isDownloading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                )
                              : Icon(
                                  isDownloaded ? Icons.check_circle : Icons.shopping_cart,
                                  size: 18,
                                ),
                          label: Text(
                            isDownloading 
                                ? 'Processing...' 
                                : isDownloaded 
                                    ? 'Purchased ✓' 
                                    : '\$${script.price.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
                            IconButton(
                              icon: Icon(
                                isFavorite ? Icons.favorite : Icons.favorite_border,
                                color: isFavorite ? Colors.red : Colors.grey[600],
                                size: 20,
                              ),
                              onPressed: onFavorite,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
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