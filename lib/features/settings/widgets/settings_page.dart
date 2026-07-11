import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/theme/theme_scope.dart';

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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onDone,
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: ShadTheme.of(context).textTheme.h4),
                  const SizedBox(height: 12),
                  // Per-device, not synced - see ThemeController.
                  ShadRadioGroup<ThemeMode>(
                    initialValue: themeController.mode,
                    onChanged: (mode) {
                      if (mode != null) themeController.setMode(mode);
                    },
                    items: [
                      for (final mode in ThemeMode.values)
                        ShadRadio<ThemeMode>(value: mode, label: Text(mode.label)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on ThemeMode {
  String get label => switch (this) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}
