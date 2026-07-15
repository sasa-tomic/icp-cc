import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Leading icon for a script row or panel.
///
/// Renders the [iconUrl] artwork when present, falling back to [emoji]
/// (or 📦 for marketplace scripts / 📜 otherwise) while the image loads and
/// if it fails to load. Single source of truth shared by the scripts list
/// tile and the run panel so both surfaces stay consistent (W7-19: the run
/// panel previously hard-coded 📦 even for scripts with valid artwork).
class ScriptLeadingIcon extends StatelessWidget {
  const ScriptLeadingIcon({
    super.key,
    this.iconUrl,
    this.emoji,
    this.isMarketplace = false,
    this.radius = 24,
  });

  final String? iconUrl;
  final String? emoji;
  final bool isMarketplace;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = _fallbackEmoji();
    if (iconUrl == null || iconUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        child: Text(fallback, style: _emojiStyle()),
      );
    }
    return CircleAvatar(
      radius: radius,
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: CachedNetworkImage(
          imageUrl: iconUrl!,
          fit: BoxFit.cover,
          placeholder: (context, url) => _centered(fallback),
          errorWidget: (context, url, error) => _centered(fallback),
        ),
      ),
    );
  }

  Widget _centered(String emoji) =>
      Center(child: Text(emoji, style: _emojiStyle()));

  /// Resolved single-grapheme emoji shown when there is no image, while it
  /// loads, or on load failure.
  String _fallbackEmoji() {
    const box = '📦';
    const scroll = '📜';
    final raw = emoji ?? (isMarketplace ? box : scroll);
    return raw.isEmpty ? scroll : raw.characters.first;
  }

  TextStyle _emojiStyle() => TextStyle(fontSize: radius * 0.8);
}
