// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/database/app_database.dart';

/// Tile alternative to the collection's grid: one card per entry showing
/// its title and, when there is one, a secondary value (the collection's
/// first field - see CollectionView). The tiles are read-only; tapping
/// one opens the entry.
class CollectionTilesView extends StatelessWidget {
  const CollectionTilesView({
    super.key,
    required this.entries,
    required this.secondaryFor,
    required this.onOpenEntry,
  });

  final List<Page> entries;

  /// The widget shown below an entry's title, or null for none (no
  /// second field, or the entry has no value for it).
  final Widget? Function(Page entry) secondaryFor;

  final ValueChanged<String> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GridView.builder(
      // Fixed-height cards of a max width rather than an aspect ratio, so
      // they fit one column on narrow screens (see UI_UX.md's
      // Responsive/Adaptive Layout) and more per row on wide ones.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisExtent: 128,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final secondary = secondaryFor(entry);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          // GestureDetector rather than InkWell - ShadCard brings its
          // own surface, so there's no Material ancestor to ink on.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpenEntry(entry.id),
            child: ShadCard(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    entry.title.isEmpty ? 'Untitled' : entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.large,
                  ),
                  if (secondary != null) ...[
                    const SizedBox(height: 8),
                    ClipRect(child: secondary),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
