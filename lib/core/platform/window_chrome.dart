import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Keeps the native window chrome in sync with the app theme.
///
/// On Linux the GTK header bar is drawn by the desktop theme, not by
/// Flutter - without this it stays gray whatever the app looks like.
/// The runner listens on this channel and recolors the header bar via
/// CSS (see linux/runner/my_application.cc). Other platforms have no
/// handler, so calls are skipped there entirely.
class WindowChromeSync extends StatefulWidget {
  const WindowChromeSync({super.key, required this.child});

  final Widget child;

  static const channel = MethodChannel('turtle_base/window');

  @override
  State<WindowChromeSync> createState() => _WindowChromeSyncState();
}

class _WindowChromeSyncState extends State<WindowChromeSync> {
  Color? _lastBackground;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = ShadTheme.of(context).colorScheme;
    if (colors.background == _lastBackground) return;
    _lastBackground = colors.background;
    _apply(colors.background, colors.foreground);
  }

  Future<void> _apply(Color background, Color foreground) async {
    if (kIsWeb || !Platform.isLinux) return;
    try {
      await WindowChromeSync.channel.invokeMethod<void>('setTitleBarColors', {
        'background': _cssHex(background),
        'foreground': _cssHex(foreground),
      });
    } on MissingPluginException {
      // Runner without the channel (e.g. tests) - nothing to sync.
    }
  }

  String _cssHex(Color color) {
    String part(double channel) =>
        (channel * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${part(color.r)}${part(color.g)}${part(color.b)}';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
