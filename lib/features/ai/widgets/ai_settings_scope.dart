import 'package:flutter/widgets.dart';
import 'package:turtle_base/features/ai/data/ai_settings_controller.dart';

/// Makes [AiSettingsController] available to the widget tree - kept
/// separate from AppScope since it's not backed by the database at all
/// (see AiSettingsController for why the default model is a per-device
/// setting, not synced domain content).
class AiSettingsScope extends InheritedNotifier<AiSettingsController> {
  const AiSettingsScope({super.key, required AiSettingsController controller, required super.child})
    : super(notifier: controller);

  static AiSettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AiSettingsScope>();
    assert(scope != null, 'No AiSettingsScope found in context');
    return scope!.notifier!;
  }
}
