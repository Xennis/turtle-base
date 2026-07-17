// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/widgets/app_navigation_controller.dart';
import 'package:turtle_base/features/shell/widgets/confirm_dialog.dart';
import 'package:turtle_base/features/shell/widgets/name_prompt_dialog.dart';

/// A dropdown selects the current space instead of listing every space
/// with its content at once - spaces are meant to be separate areas,
/// only one is shown at a time.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.navigation});

  final AppNavigationController navigation;

  static const newSpaceSentinel = '__new_space__';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<Space>>(
      stream: scope.spaces.watchAll(),
      builder: (context, snapshot) {
        final spaces = snapshot.data ?? const <Space>[];
        // Select the first space once spaces are loaded, if none is
        // selected yet (or the previously selected one is gone).
        if (spaces.isNotEmpty &&
            !spaces.any((s) => s.id == navigation.selectedSpaceId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            navigation.selectSpace(spaces.first.id);
          });
        }

        return Column(
          children: [
            _SpaceSelector(spaces: spaces, navigation: navigation),
            const ShadSeparator.horizontal(),
            Expanded(
              child: ListenableBuilder(
                listenable: navigation,
                builder: (context, _) {
                  final spaceId = navigation.selectedSpaceId;
                  if (spaceId == null) return const SizedBox.shrink();
                  return _SpaceContent(spaceId: spaceId, navigation: navigation);
                },
              ),
            ),
            const ShadSeparator.horizontal(),
            // Fixed entry, not tied to the current space (see UI_UX.md's
            // Sidebar section - Papierkorb follows later as a second one).
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListenableBuilder(
                listenable: navigation,
                builder: (context, _) => _SidebarRow(
                  leading: const Icon(Icons.settings_outlined, size: 18),
                  title: 'Settings',
                  selected: navigation.isShowingSettings,
                  onTap: navigation.showSettings,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpaceSelector extends StatelessWidget {
  const _SpaceSelector({required this.spaces, required this.navigation});

  final List<Space> spaces;
  final AppNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: navigation,
      builder: (context, _) {
        final selectedId = navigation.selectedSpaceId;
        final matches = spaces.where((s) => s.id == selectedId);
        final selectedSpace = matches.isEmpty ? null : matches.first;

        return Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: ShadSelect<String>(
                  initialValue: selectedSpace?.id,
                  placeholder: const Text('Select a space'),
                  selectedOptionBuilder: (context, value) {
                    if (value == Sidebar.newSpaceSentinel) return const Text('New space');
                    // The select's own controller can still hold the
                    // just-deleted space's id for a frame after `spaces`
                    // has already gone empty (e.g. right after deleting
                    // the last one) - fall back to blank rather than
                    // firstWhere() throwing on no match.
                    final matches = spaces.where((s) => s.id == value);
                    return Text(matches.isEmpty ? '' : matches.first.name);
                  },
                  options: [
                    for (final space in spaces)
                      ShadOption(value: space.id, child: Text(space.name)),
                    const ShadOption(
                      value: Sidebar.newSpaceSentinel,
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 18),
                          SizedBox(width: 8),
                          Text('New space'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    if (value == Sidebar.newSpaceSentinel) {
                      final name = await promptForName(context, title: 'New space');
                      if (name != null) {
                        final id = await scope.spaces.create(name: name);
                        navigation.selectSpace(id);
                      }
                      return;
                    }
                    navigation.selectSpace(value);
                  },
                ),
              ),
              if (selectedSpace != null) ...[
                Tooltip(
                  message: 'Rename space',
                  child: ShadIconButton.ghost(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final name = await promptForName(
                        context,
                        title: 'Rename space',
                        initialValue: selectedSpace.name,
                      );
                      if (name != null) {
                        await scope.spaces.rename(selectedSpace.id, name);
                      }
                    },
                  ),
                ),
                Tooltip(
                  // Deleting down to zero spaces is fine - _MainContent
                  // shows a "create a space"/"go to Settings" empty
                  // state instead of assuming one always exists.
                  message: 'Delete space',
                  child: ShadIconButton.ghost(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final confirmed = await confirmDelete(
                        context,
                        title: "Delete space '${selectedSpace.name}'?",
                        message:
                            "Its collections and pages will stop being "
                            "shown until it's restored - there's no "
                            'Trash UI for that yet.',
                      );
                      if (confirmed) {
                        await scope.spaces.softDelete(selectedSpace.id);
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SpaceContent extends StatelessWidget {
  const _SpaceContent({required this.spaceId, required this.navigation});

  final String spaceId;
  final AppNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListView(
      children: [
        _SidebarHeaderRow(
          title: 'Collections',
          tooltip: 'New collection',
          onAdd: () async {
            final name = await promptForName(context, title: 'New collection');
            if (name == null) return;
            // No starter field: every entry already has a title
            // (see PagesRepository) - that's the grid's first column,
            // not a user-defined field.
            await scope.collections.create(spaceId: spaceId, name: name);
          },
        ),
        StreamBuilder<List<Collection>>(
          stream: scope.collections.watchAllInSpace(spaceId),
          builder: (context, snapshot) {
            final collections = snapshot.data ?? const <Collection>[];
            return Column(
              children: [
                for (final collection in collections)
                  _SidebarRow(
                    leading: collection.icon != null
                        ? Text(collection.icon!, style: const TextStyle(fontSize: 20))
                        : const Icon(Icons.table_chart_outlined, size: 18),
                    title: collection.name,
                    selected: navigation.selectedCollectionId == collection.id,
                    onTap: () => navigation.selectCollection(collection.id),
                    trailingTooltip: 'Delete collection',
                    onTrailingTap: () async {
                      final confirmed = await confirmDelete(
                        context,
                        title: "Delete '${collection.name}'?",
                      );
                      if (!confirmed) return;
                      if (navigation.selectedCollectionId == collection.id) {
                        navigation.clearSelection();
                      }
                      await scope.collections.softDelete(collection.id);
                    },
                  ),
              ],
            );
          },
        ),
        const ShadSeparator.horizontal(),
        _SidebarHeaderRow(
          title: 'Pages',
          tooltip: 'New page',
          onAdd: () async {
            final id = await scope.pages.create(spaceId: spaceId);
            navigation.selectPage(id);
          },
        ),
        StreamBuilder<List<Page>>(
          stream: scope.pages.watchTopLevelInSpace(spaceId),
          builder: (context, snapshot) {
            final pages = snapshot.data ?? const <Page>[];
            return Column(
              children: [
                for (final page in pages)
                  _SidebarRow(
                    leading: page.icon != null
                        ? Text(page.icon!, style: const TextStyle(fontSize: 20))
                        : const Icon(Icons.description_outlined, size: 18),
                    title: page.title.isEmpty ? 'Untitled' : page.title,
                    selected: navigation.selectedPageId == page.id,
                    onTap: () => navigation.selectPage(page.id),
                    trailingTooltip: 'Delete page',
                    onTrailingTap: () async {
                      final confirmed = await confirmDelete(
                        context,
                        title:
                            "Delete '${page.title.isEmpty ? 'Untitled' : page.title}'?",
                      );
                      if (!confirmed) return;
                      if (navigation.selectedPageId == page.id) {
                        navigation.clearSelection();
                      }
                      await scope.pages.softDelete(page.id);
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The "Collections"/"Pages" section header, with its "+" action - not
/// a list entry itself, so it's kept separate from [_SidebarRow].
class _SidebarHeaderRow extends StatelessWidget {
  const _SidebarHeaderRow({
    required this.title,
    required this.tooltip,
    required this.onAdd,
  });

  final String title;
  final String tooltip;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: theme.textTheme.small)),
          Tooltip(
            message: tooltip,
            child: ShadIconButton.ghost(
              icon: const Icon(Icons.add, size: 18),
              onPressed: onAdd,
            ),
          ),
        ],
      ),
    );
  }
}

/// A selectable sidebar entry (collection, page, or a fixed entry like
/// Settings) with a leading icon/emoji, a title, and an optional
/// trailing delete action - shadcn_ui has no ListTile equivalent, so
/// this composes one from theme tokens. Fixed entries (no delete
/// action) leave [trailingTooltip]/[onTrailingTap] unset.
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
    this.trailingTooltip,
    this.onTrailingTap,
  }) : assert(
         (trailingTooltip == null) == (onTrailingTap == null),
         'trailingTooltip and onTrailingTap must be set together',
       );

  final Widget leading;
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final String? trailingTooltip;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? theme.colorScheme.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: selected
                        ? theme.textTheme.small.copyWith(
                            color: theme.colorScheme.accentForeground,
                          )
                        : theme.textTheme.small,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailingTooltip != null)
                  Tooltip(
                    message: trailingTooltip!,
                    child: ShadIconButton.ghost(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      onPressed: onTrailingTap,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
