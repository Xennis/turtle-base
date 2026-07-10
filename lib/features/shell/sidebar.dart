// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/shell/app_navigation_controller.dart';
import 'package:turtle_base/features/shell/name_prompt_dialog.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.navigation});

  final AppNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<Space>>(
      stream: scope.spaces.watchAll(),
      builder: (context, snapshot) {
        final spaces = snapshot.data ?? const <Space>[];
        return ListView(
          children: [
            ListTile(
              title: const Text('Spaces'),
              trailing: IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'New space',
                onPressed: () async {
                  final name = await promptForName(context, title: 'New space');
                  if (name != null) {
                    await scope.spaces.create(name: name);
                  }
                },
              ),
            ),
            for (final space in spaces)
              _SpaceSection(space: space, navigation: navigation),
          ],
        );
      },
    );
  }
}

class _SpaceSection extends StatelessWidget {
  const _SpaceSection({required this.space, required this.navigation});

  final Space space;
  final AppNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(Icons.folder_outlined),
      title: Text(space.name),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Rename',
        onPressed: () async {
          final name = await promptForName(
            context,
            title: 'Rename space',
            initialValue: space.name,
          );
          if (name != null) {
            await scope.spaces.rename(space.id, name);
          }
        },
      ),
      children: [
        StreamBuilder<List<Collection>>(
          stream: scope.collections.watchAllInSpace(space.id),
          builder: (context, snapshot) {
            final collections = snapshot.data ?? const <Collection>[];
            return Column(
              children: [
                for (final collection in collections)
                  ListenableBuilder(
                    listenable: navigation,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.table_chart_outlined),
                      title: Text(collection.name),
                      selected: navigation.selectedCollectionId == collection.id,
                      onTap: () => navigation.selectCollection(collection.id),
                    ),
                  ),
              ],
            );
          },
        ),
        StreamBuilder<List<Page>>(
          stream: scope.pages.watchTopLevelInSpace(space.id),
          builder: (context, snapshot) {
            final pages = snapshot.data ?? const <Page>[];
            return Column(
              children: [
                for (final page in pages)
                  ListenableBuilder(
                    listenable: navigation,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(page.title.isEmpty ? 'Untitled' : page.title),
                      selected: navigation.selectedPageId == page.id,
                      onTap: () => navigation.selectPage(page.id),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
