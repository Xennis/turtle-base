import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/features/plugins/data/plugin_instances_repository.dart';
import 'package:turtle_base/features/plugins/data/plugin_registry.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

import '../../../support/pump_app.dart';

const _plugin = TurtlePlugin(
  id: 'demo',
  name: 'Demo',
  description: 'A demo plugin',
  collections: [
    CollectionTemplate(key: 'items', name: 'Items', fields: [DateFieldTemplate('due', 'Due')]),
  ],
);

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('adding a plugin creates its space and opens it', (WidgetTester tester) async {
    final database = await pumpApp(tester, plugins: PluginRegistry([_plugin]));

    await tester.tap(find.text('Plugins'));
    await settle(tester);
    expect(find.text('A demo plugin'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await settle(tester);

    final spaces = await tester.runAsync(() => PluginInstancesRepository(database).watchInstances('demo').first);
    expect(spaces, hasLength(1));
    // Back in the shell, with the new space's collection in the sidebar.
    expect(find.text('A demo plugin'), findsNothing);
    expect(find.text('Items'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
