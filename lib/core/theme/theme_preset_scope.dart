import 'package:flutter/widgets.dart';
import 'package:turtle_base/core/theme/theme_preset_controller.dart';

/// Makes [ThemePresetController] available to the widget tree - kept
/// separate from ThemeScope since it tracks a different preference
/// (color scheme rather than light/dark mode) with its own storage key.
class ThemePresetScope extends InheritedNotifier<ThemePresetController> {
  const ThemePresetScope({super.key, required ThemePresetController controller, required super.child})
    : super(notifier: controller);

  static ThemePresetController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemePresetScope>();
    assert(scope != null, 'No ThemePresetScope found in context');
    return scope!.notifier!;
  }
}
