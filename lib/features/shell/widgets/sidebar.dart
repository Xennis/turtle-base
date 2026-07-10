// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/widgets/app_navigation_controller.dart';
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
            const Divider(height: 1),
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
                child: DropdownButton<String>(
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  value: selectedSpace?.id,
                  items: [
                    for (final space in spaces)
                      DropdownMenuItem(value: space.id, child: Text(space.name)),
                    const DropdownMenuItem(
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
              if (selectedSpace != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Rename space',
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
        ListTile(
          title: const Text('Collections'),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New collection',
            onPressed: () async {
              final name = await promptForName(context, title: 'New collection');
              if (name == null) return;
              // No starter field: every entry already has a title
              // (see PagesRepository) - that's the grid's first column,
              // not a user-defined field.
              await scope.collections.create(spaceId: spaceId, name: name);
            },
          ),
        ),
        StreamBuilder<List<Collection>>(
          stream: scope.collections.watchAllInSpace(spaceId),
          builder: (context, snapshot) {
            final collections = snapshot.data ?? const <Collection>[];
            return Column(
              children: [
                for (final collection in collections)
                  ListTile(
                    leading: const Icon(Icons.table_chart_outlined),
                    title: Text(collection.name),
                    selected: navigation.selectedCollectionId == collection.id,
                    onTap: () => navigation.selectCollection(collection.id),
                  ),
              ],
            );
          },
        ),
        const Divider(),
        ListTile(
          title: const Text('Pages'),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New page',
            onPressed: () async {
              final id = await scope.pages.create(spaceId: spaceId);
              navigation.selectPage(id);
            },
          ),
        ),
        StreamBuilder<List<Page>>(
          stream: scope.pages.watchTopLevelInSpace(spaceId),
          builder: (context, snapshot) {
            final pages = snapshot.data ?? const <Page>[];
            return Column(
              children: [
                for (final page in pages)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(page.title.isEmpty ? 'Untitled' : page.title),
                    selected: navigation.selectedPageId == page.id,
                    onTap: () => navigation.selectPage(page.id),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
