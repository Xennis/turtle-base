import 'package:flutter/material.dart';
import 'package:turtle_base/features/pages/widgets/page_detail_view.dart';
import 'package:turtle_base/features/shell/widgets/app_navigation_controller.dart';
import 'package:turtle_base/features/shell/widgets/sidebar.dart';
import 'package:turtle_base/features/tables/widgets/collection_edit_page.dart';
import 'package:turtle_base/features/tables/widgets/collection_view.dart';

/// Fixed side-by-side layout for now. Switching to a drawer on narrow
/// screens (see UI_UX.md) is a follow-up, not part of this first step.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _navigation = AppNavigationController();

  @override
  void dispose() {
    _navigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 260,
            child: Sidebar(navigation: _navigation),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: _navigation,
              builder: (context, _) => _MainContent(navigation: _navigation),
            ),
          ),
        ],
      ),
    );
  }
}

class _MainContent extends StatelessWidget {
  const _MainContent({required this.navigation});

  final AppNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    if (navigation.selectedCollectionId case final id?) {
      if (navigation.isEditingCollection) {
        return CollectionEditPage(
          collectionId: id,
          onDone: navigation.stopEditingCollection,
        );
      }
      return CollectionView(
        collectionId: id,
        onEdit: navigation.startEditingCollection,
      );
    }
    if (navigation.selectedPageId case final id?) {
      return PageDetailView(pageId: id);
    }
    return const Center(child: Text('Select a collection or page'));
  }
}
