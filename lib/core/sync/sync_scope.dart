import 'package:flutter/widgets.dart';
import 'package:turtle_base/core/sync/app_sync_controller.dart';

/// Makes [AppSyncController] available to the widget tree - same
/// InheritedNotifier pattern as ThemeScope: descendants that call [of]
/// rebuild automatically whenever sync status/connection changes.
class SyncScope extends InheritedNotifier<AppSyncController> {
  const SyncScope({super.key, required AppSyncController controller, required super.child})
    : super(notifier: controller);

  static AppSyncController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SyncScope>();
    assert(scope != null, 'No SyncScope found in context');
    return scope!.notifier!;
  }
}
