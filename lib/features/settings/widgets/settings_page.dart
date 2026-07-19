import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/sync/app_sync_controller.dart';
import 'package:turtle_base/core/sync/sync_scope.dart';
import 'package:turtle_base/core/theme/theme_preset.dart';
import 'package:turtle_base/core/theme/theme_preset_scope.dart';
import 'package:turtle_base/core/theme/theme_scope.dart';
import 'package:turtle_base/features/ai/widgets/ai_settings_card.dart';
import 'package:turtle_base/features/settings/widgets/settings_row.dart';
import 'package:turtle_base/packages/crdt_file_sync/sync_controller.dart';

/// Shown in the same content area as the rest of the shell (see
/// AppShell/_MainContent) rather than pushed via Navigator, matching
/// CollectionEditPage's pattern. [onDone] returns to whatever was
/// showing before Settings was opened.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final themeController = ThemeScope.of(context);
    final themePresetController = ThemePresetScope.of(context);
    // No Scaffold/AppBar of its own (unlike CollectionEditPage) - the
    // slim header row matches PageDetailView, and the background comes
    // from the wide layout's floating content panel or the narrow
    // layout's wrapper Scaffold (see AppShell).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Row(
            children: [
              Tooltip(
                message: 'Back',
                child: ShadIconButton.ghost(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onDone,
                ),
              ),
              const SizedBox(width: 4),
              Text('Settings', style: ShadTheme.of(context).textTheme.h3),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Centered with a max width so the cards don't stretch
              // across the whole window on desktop.
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ShadCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Appearance',
                              style: ShadTheme.of(context).textTheme.h4,
                            ),
                            const SizedBox(height: 12),
                            SettingsRow(
                              label: 'Theme',
                              // Per-device, not synced - see ThemeController.
                              control: ShadSelect<ThemeMode>(
                                initialValue: themeController.mode,
                                selectedOptionBuilder: (context, value) =>
                                    Text(value.label),
                                options: [
                                  for (final mode in ThemeMode.values)
                                    ShadOption(
                                      value: mode,
                                      child: Text(mode.label),
                                    ),
                                ],
                                onChanged: (mode) {
                                  if (mode != null) {
                                    themeController.setMode(mode);
                                  }
                                },
                              ),
                            ),
                            SettingsRow(
                              label: 'Color',
                              // Per-device, not synced - see
                              // ThemePresetController.
                              control: ShadSelect<ThemePreset>(
                                initialValue: themePresetController.preset,
                                selectedOptionBuilder: (context, value) =>
                                    Text(value.label),
                                options: [
                                  for (final preset in ThemePreset.values)
                                    ShadOption(
                                      value: preset,
                                      child: Text(preset.label),
                                    ),
                                ],
                                onChanged: (preset) {
                                  if (preset != null) {
                                    themePresetController.setPreset(preset);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const AiSettingsCard(),
                      const _SyncSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Wrapped in its own [ListenableBuilder] (rather than the whole page)
/// so a sync status change doesn't rebuild the Appearance card above it.
/// Renders nothing if Drive sync isn't configured for this platform (see
/// [AppSyncController.isAvailable]) - no OAuth client means it could never
/// connect, so showing the controls would just be confusing.
class _SyncSection extends StatelessWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context) {
    final sync = SyncScope.of(context);
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        if (!sync.isAvailable) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ShadCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sync', style: ShadTheme.of(context).textTheme.h4),
                const SizedBox(height: 12),
                SettingsRow(
                  label: 'Google Drive',
                  control: sync.isConnected
                      ? ShadButton.outline(
                          onPressed: () => sync.disconnect(),
                          child: const Text('Disconnect'),
                        )
                      : ShadButton(
                          onPressed: () => sync.connect(),
                          child: const Text('Connect'),
                        ),
                ),
                SettingsRow(label: 'Status', control: Text(_statusLabel(sync))),
                SettingsRow(
                  label: '',
                  control: ShadButton.outline(
                    onPressed:
                        sync.isConnected && sync.status != SyncStatus.syncing
                        ? () => sync.syncNow()
                        : null,
                    child: const Text('Sync now'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusLabel(AppSyncController sync) {
    if (!sync.isConnected) return 'Not connected';
    return switch (sync.status) {
      SyncStatus.syncing => 'Syncing…',
      SyncStatus.error => 'Error: ${sync.lastError}',
      SyncStatus.idle =>
        sync.lastSyncedAt == null
            ? 'Connected'
            : 'Last synced ${sync.lastSyncedAt}',
    };
  }
}

extension on ThemeMode {
  String get label => switch (this) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}
