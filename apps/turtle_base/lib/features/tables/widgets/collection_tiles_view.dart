// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/database/app_database.dart';

/// Tile alternative to the collection's grid: one card per entry showing
/// its title and, when there is one, a secondary value (the collection's
/// first field - see CollectionView). The tiles are read-only; tapping
/// one opens the entry.
class CollectionTilesView extends StatelessWidget {
  const CollectionTilesView({super.key, required this.entries, required this.secondaryFor, required this.onOpenEntry});

  final List<Page> entries;

  /// The widget shown below an entry's title, or null for none (no
  /// second field, or the entry has no value for it).
  final Widget? Function(Page entry) secondaryFor;

  final ValueChanged<String> onOpenEntry;

  @override
  Widget build(BuildContext context) {
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
        return _Tile(entry: entry, secondary: secondary, onTap: () => onOpenEntry(entry.id));
      },
    );
  }
}

/// A card that lifts its border on hover, to read as clickable.
class _Tile extends StatefulWidget {
  const _Tile({required this.entry, required this.secondary, required this.onTap});

  final Page entry;
  final Widget? secondary;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final entry = widget.entry;
    final secondary = widget.secondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // GestureDetector rather than InkWell - ShadCard brings its own
      // surface, so there's no Material ancestor to ink on.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ShadCard(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          // The card's own border unless hovered.
          border: _hovered ? ShadBorder.all(color: theme.colorScheme.ring, radius: theme.radius) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  if (entry.icon != null) ...[
                    Text(entry.icon!, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      entry.title.isEmpty ? 'Untitled' : entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.large,
                    ),
                  ),
                ],
              ),
              if (secondary != null) ...[const SizedBox(height: 8), ClipRect(child: secondary)],
            ],
          ),
        ),
      ),
    );
  }
}
