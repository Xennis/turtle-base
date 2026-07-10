import 'package:flutter/material.dart';
import 'package:turtle_base/features/shell/app_navigation_controller.dart';
import 'package:turtle_base/features/shell/sidebar.dart';

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
              builder: (context, _) => _ContentPlaceholder(navigation: _navigation),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentPlaceholder extends StatelessWidget {
  const _ContentPlaceholder({required this.navigation});

  final AppNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    final String label;
    if (navigation.selectedCollectionId case final id?) {
      label = 'Collection selected: $id';
    } else if (navigation.selectedPageId case final id?) {
      label = 'Page selected: $id';
    } else {
      label = 'Select a collection or page';
    }
    return Center(child: Text(label));
  }
}
