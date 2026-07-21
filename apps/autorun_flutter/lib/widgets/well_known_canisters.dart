import 'dart:async';

import 'package:flutter/material.dart';

import '../config/well_known_canisters.dart';

/// Quick-pick grid of well-known canisters shown on the Canisters tab and in
/// the inline Canister Client sheet's "Quick Start" section.
///
/// The list itself is the canonical [WellKnownCanister.all] — single source
/// of truth (UX-H11). This widget only renders it.
class WellKnownList extends StatelessWidget {
  const WellKnownList({super.key, required this.onSelect, this.onBookmark});
  final void Function(String canisterId, String? method) onSelect;
  final Future<void> Function(WellKnownCanister entry)? onBookmark;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 420 ? 1 : (width > 880 ? 3 : 2);
    final childAspectRatio = width > 880 ? 3.5 : (width < 420 ? 3.0 : 2.6);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: WellKnownCanister.all.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (BuildContext context, int index) {
        final entry = WellKnownCanister.all[index];
        return _WellKnownCard(
          entry: entry,
          onTap: () => onSelect(entry.canisterId, entry.method),
          onBookmark:
              onBookmark == null ? null : () => unawaited(onBookmark!(entry)),
        );
      },
    );
  }
}

class _WellKnownCard extends StatelessWidget {
  const _WellKnownCard(
      {required this.entry, required this.onTap, this.onBookmark});

  final WellKnownCanister entry;
  final VoidCallback onTap;
  final VoidCallback? onBookmark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // W6-10 (a): the card is a tappable `InkWell` that opens the call sheet,
    // but without an explicit `Semantics(button:)` wrapper it appeared in the
    // a11y tree only as a `group` — screen-reader users couldn't tell the
    // card is actionable. `container: true` keeps this a clean button node
    // (label = the canister name) whose tap action flows up from the
    // `InkWell`, while the nested `Bookmark` button (its own container below)
    // stays separately focusable instead of merging into this node.
    return Semantics(
      button: true,
      container: true,
      label: 'Open ${entry.label}',
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            // E2E-D-RESUME-2: was a plain Column with `Spacer()` to push the
            // method badge to the bottom. The Spacer (flex=1) both (a) fails
            // "non-zero flex in unbounded constraints" during transient
            // IndexedStack re-layout and (b) overflows when the GridView's
            // tight cell height (esp. at narrow widths / 2-column layouts) is
            // smaller than the natural Row + Spacer + badge height. Pre-3.44.6
            // these were silent warnings; under the new
            // IntegrationTestWidgetsFlutterBinding they fail the test outright.
            //
            // SingleChildScrollView (with scrolling disabled) gives the inner
            // Column unbounded height so its natural content always lays out,
            // and visually clips anything that doesn't fit the card — no
            // overflow error ever. The method badge now sits directly under
            // the title row instead of pinned to the card bottom (minor
            // visual change; no test asserts position).
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(entry.icon,
                            color: theme.colorScheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // W7-19: the card-level Semantics(label: 'Open …')
                            // already exposes the name; exclude the title Text
                            // so screen readers don't announce it twice.
                            ExcludeSemantics(
                              child: Text(
                                entry.label,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.description,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (onBookmark != null)
                        // W6-10 (a): own container so this stays a SEPARATE
                        // focusable button (labelled for screen readers)
                        // instead of merging into the card's open-action node.
                        Semantics(
                          container: true,
                          button: true,
                          label: 'Bookmark ${entry.label}',
                          child: IconButton(
                            tooltip: 'Bookmark',
                            icon: Icon(Icons.bookmark_add_outlined,
                                color: theme.colorScheme.primary),
                            onPressed: onBookmark,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                  if ((entry.method ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        entry.method!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
