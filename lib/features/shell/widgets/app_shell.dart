// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/widgets/page_detail_view.dart';
import 'package:turtle_base/features/settings/widgets/settings_page.dart';
import 'package:turtle_base/features/shell/widgets/app_navigation_controller.dart';
import 'package:turtle_base/features/shell/widgets/name_prompt_dialog.dart';
import 'package:turtle_base/features/shell/widgets/sidebar.dart';
import 'package:turtle_base/features/tables/widgets/collection_edit_page.dart';
import 'package:turtle_base/features/tables/widgets/collection_view.dart';

/// Desktop (wide screens): sidebar permanently visible, side-by-side with
/// content. Mobile (narrow screens): sidebar becomes a drawer, navigation
/// is list-then-detail with a back button, instead of two columns side
/// by side (see UI_UX.md's Responsive/Adaptive Layout section).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// Below this width, use the narrow (drawer + stack) layout - the
  /// common Material breakpoint between compact (phone) and medium
  /// (tablet/desktop) window sizes. UI_UX.md doesn't pin an exact
  /// number.
  static const wideBreakpoint = 600.0;

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
    final isWide = MediaQuery.sizeOf(context).width >= AppShell.wideBreakpoint;
    return isWide ? _WideShell(navigation: _navigation) : _NarrowShell(navigation: _navigation);
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({required this.navigation});

  final AppNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            // Widened from 260 to fit the space selector's rename +
            // delete icon buttons alongside the dropdown without
            // overflowing.
            width: 300,
            child: Sidebar(navigation: navigation),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: navigation,
              builder: (context, _) => _MainContent(navigation: navigation),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sidebar lives in a drawer instead of being permanently visible; the
/// content area is either the sidebar's "nothing selected" fallback (with
/// the drawer's hamburger reachable) or the selected collection/page,
/// full-screen, with a back button that clears the selection.
///
/// CollectionEditPage already brings its own full Scaffold/AppBar/back
/// button (see AppShell/_MainContent) - shown as-is here rather than
/// nested inside a second AppBar.
class _NarrowShell extends StatefulWidget {
  const _NarrowShell({required this.navigation});

  final AppNavigationController navigation;

  @override
  State<_NarrowShell> createState() => _NarrowShellState();
}

class _NarrowShellState extends State<_NarrowShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    widget.navigation.addListener(_closeDrawerOnSelection);
  }

  @override
  void dispose() {
    widget.navigation.removeListener(_closeDrawerOnSelection);
    super.dispose();
  }

  void _closeDrawerOnSelection() {
    final navigation = widget.navigation;
    if (navigation.selectedCollectionId != null ||
        navigation.selectedPageId != null ||
        navigation.isShowingSettings) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigation = widget.navigation;
    return ListenableBuilder(
      listenable: navigation,
      builder: (context, _) {
        if (navigation.isEditingCollection || navigation.isShowingSettings) {
          return _MainContent(navigation: navigation);
        }
        final hasSelection =
            navigation.selectedCollectionId != null || navigation.selectedPageId != null;
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            leading: hasSelection
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: navigation.clearSelection,
                  )
                // Left null (rather than removed) so Scaffold still
                // auto-shows the drawer's hamburger button here.
                : null,
            title: const Text('Turtle Base'),
          ),
          drawer: Drawer(child: SafeArea(child: Sidebar(navigation: navigation))),
          body: _MainContent(navigation: navigation),
        );
      },
    );
  }
}

class _MainContent extends StatelessWidget {
  const _MainContent({required this.navigation});

  final AppNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    if (navigation.isShowingSettings) {
      return SettingsPage(onDone: navigation.hideSettings);
    }
    if (navigation.selectedCollectionId case final id?) {
      if (navigation.isEditingCollection) {
        return CollectionEditPage(
          collectionId: id,
          onDone: navigation.stopEditingCollection,
          onDeleted: navigation.clearSelection,
        );
      }
      return CollectionView(
        collectionId: id,
        onEdit: navigation.startEditingCollection,
        onOpenEntry: navigation.selectPage,
      );
    }
    if (navigation.selectedPageId case final id?) {
      return PageDetailView(pageId: id, onOpenCollection: navigation.selectCollection);
    }
    return StreamBuilder<List<Space>>(
      stream: AppScope.of(context).spaces.watchAll(),
      builder: (context, snapshot) {
        // No spaces yet on this device isn't necessarily "starting from
        // scratch" - it may be a fresh install about to pull existing
        // spaces from another device via Sync, so offer both.
        if (snapshot.data?.isEmpty ?? false) {
          return _EmptySpacesState(navigation: navigation);
        }
        return const Center(child: Text('Select a collection or page'));
      },
    );
  }
}

/// Shown instead of "Select a collection or page" when this device has
/// no spaces at all yet - offers to either start fresh or, since this
/// may well be a second device, go connect/sync instead of creating a
/// space that's about to be replaced by a synced one anyway.
class _EmptySpacesState extends StatelessWidget {
  const _EmptySpacesState({required this.navigation});

  final AppNavigationController navigation;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No spaces yet'),
          const SizedBox(height: 16),
          ShadButton(
            onPressed: () async {
              final name = await promptForName(context, title: 'New space');
              if (name != null) {
                await scope.spaces.create(name: name);
              }
            },
            child: const Text('Create your first space'),
          ),
          const SizedBox(height: 8),
          // MVP: just navigates to Settings, where the user connects
          // Google Drive and triggers a sync themselves - no dedicated
          // "connect and sync now" one-tap flow yet.
          ShadButton.outline(
            onPressed: navigation.showSettings,
            child: const Text('Go to Settings to sync'),
          ),
        ],
      ),
    );
  }
}
