import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

/// Lists the plugins the app ships with. Adding one creates a space with
/// its collections - there's nothing to enable or remember, the space
/// is the plugin's whole state. Shown in the shell's content area like
/// SettingsPage.
class PluginsPage extends StatelessWidget {
  const PluginsPage({super.key, required this.onDone, required this.onOpenSpace});

  final VoidCallback onDone;
  final ValueChanged<String> onOpenSpace;

  @override
  Widget build(BuildContext context) {
    final plugins = AppScope.of(context).plugins.addable;
    // SafeArea for the same reason as SettingsPage's.
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                Tooltip(
                  message: 'Back',
                  child: ShadIconButton.ghost(icon: const Icon(Icons.arrow_back), onPressed: onDone),
                ),
                const SizedBox(width: 4),
                Text('Plugins', style: ShadTheme.of(context).textTheme.h3),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (plugins.isEmpty) const Text('No plugins available.'),
                        for (final plugin in plugins) ...[
                          _PluginCard(plugin: plugin, onOpenSpace: onOpenSpace),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginCard extends StatefulWidget {
  const _PluginCard({required this.plugin, required this.onOpenSpace});

  final TurtlePlugin plugin;
  final ValueChanged<String> onOpenSpace;

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      final spaceId = await AppScope.of(context).pluginInstances.add(widget.plugin);
      widget.onOpenSpace(spaceId);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final plugin = widget.plugin;
    final collections = plugin.collections.map((c) => c.name).join(', ');
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (plugin.icon case final icon?) ...[Text(icon, style: theme.textTheme.h4), const SizedBox(width: 8)],
              Expanded(child: Text(plugin.name, style: theme.textTheme.h4)),
              ShadButton(
                leading: const Icon(Icons.add, size: 16),
                onPressed: _adding ? null : _add,
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(plugin.description, style: theme.textTheme.muted),
          const SizedBox(height: 4),
          Text('Creates a space "${plugin.name}" with: $collections', style: theme.textTheme.muted),
          StreamBuilder<List<Space>>(
            stream: AppScope.of(context).pluginInstances.watchInstances(plugin.id),
            builder: (context, snapshot) {
              final spaces = snapshot.data ?? const [];
              if (spaces.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final space in spaces)
                      ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () => widget.onOpenSpace(space.id),
                        child: Text([?space.icon, space.name].join(' ')),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
