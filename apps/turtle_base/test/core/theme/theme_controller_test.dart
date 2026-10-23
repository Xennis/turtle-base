import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:turtle_base/core/theme/theme_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to system when nothing was ever stored', () async {
    final controller = await ThemeController.load();
    expect(controller.mode, ThemeMode.system);
  });

  test('setMode updates the mode and notifies listeners', () async {
    final controller = await ThemeController.load();
    var notified = false;
    controller.addListener(() => notified = true);

    await controller.setMode(ThemeMode.dark);

    expect(controller.mode, ThemeMode.dark);
    expect(notified, isTrue);
  });

  test('setMode with the current mode is a no-op, no notification', () async {
    final controller = await ThemeController.load();
    var notifyCount = 0;
    controller.addListener(() => notifyCount++);

    await controller.setMode(ThemeMode.system);

    expect(notifyCount, 0);
  });

  test('persists across a fresh load, simulating an app restart', () async {
    final first = await ThemeController.load();
    await first.setMode(ThemeMode.dark);

    final second = await ThemeController.load();
    expect(second.mode, ThemeMode.dark);
  });
}
