import 'package:flutter/widgets.dart';
import 'package:turtle_base/core/theme/theme_controller.dart';

/// Makes [ThemeController] available to the widget tree - kept separate
/// from AppScope since it's not backed by the database at all (see
/// ThemeController for why theme is a per-device setting, not synced
/// domain content).
///
/// InheritedNotifier: descendants that call [of] rebuild automatically
/// whenever the controller's mode changes, without a separate
/// ListenableBuilder wrapper.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({super.key, required ThemeController controller, required super.child})
    : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'No ThemeScope found in context');
    return scope!.notifier!;
  }
}
