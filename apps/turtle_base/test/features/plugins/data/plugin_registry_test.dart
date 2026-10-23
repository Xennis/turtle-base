import 'package:books/books.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/features/plugins/data/plugin_registry.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

const _list = CollectionTemplate(
  key: 'list',
  name: 'List',
  fields: [
    SelectFieldTemplate(
      'status',
      'Status',
      options: [OptionTemplate('open', 'Open', OptionColor.gray), OptionTemplate('done', 'Done', OptionColor.green)],
    ),
  ],
);

void main() {
  test('accepts the plugins the app ships with', () {
    expect(() => PluginRegistry([booksPlugin]), returnsNormally);
  });

  test('collects the variants of all plugins', () {
    final variant = TextVariant(id: 'a.code', label: 'Code');
    final registry = PluginRegistry([
      TurtlePlugin(id: 'a', name: 'A', description: '', variants: [variant]),
      const TurtlePlugin(id: 'b', name: 'B', description: '', collections: [_list]),
    ]);

    expect(registry.variants, [variant]);
    expect(registry.addable.map((p) => p.id), ['b']);
  });

  test('finds the template a collection was created from', () {
    final registry = PluginRegistry([
      const TurtlePlugin(id: 'b', name: 'B', description: '', collections: [_list]),
    ]);
    final spaceId = pluginSpaceId('b', '6f1c-uuid');

    expect(registry.templateOf(pluginCollectionId(spaceId, 'list')), _list);
    expect(registry.templateOf(pluginCollectionId(spaceId, 'other')), isNull);
    expect(registry.templateOf(pluginCollectionId(pluginSpaceId('c', '6f1c-uuid'), 'list')), isNull);
    expect(registry.templateOf('6f1c-uuid'), isNull);
  });

  test('recognizes a plugin space', () {
    expect(isPluginSpaceId(pluginSpaceId('b', '6f1c-uuid'), 'b'), isTrue);
    expect(isPluginSpaceId(pluginSpaceId('b', '6f1c-uuid'), 'c'), isFalse);
    expect(isPluginSpaceId('6f1c-uuid', 'b'), isFalse);
  });

  group('rejects', () {
    test('a plugin id with a dot', () {
      expect(() => PluginRegistry([const TurtlePlugin(id: 'a.b', name: 'A', description: '')]), throwsArgumentError);
    });

    test('a duplicate plugin id', () {
      const plugin = TurtlePlugin(id: 'a', name: 'A', description: '');
      expect(() => PluginRegistry([plugin, plugin]), throwsArgumentError);
    });

    test('a variant without the plugin prefix', () {
      final plugin = TurtlePlugin(
        id: 'a',
        name: 'A',
        description: '',
        variants: [TextVariant(id: 'code', label: 'Code')],
      );
      expect(() => PluginRegistry([plugin]), throwsArgumentError);
    });

    test('duplicate field keys', () {
      const plugin = TurtlePlugin(
        id: 'a',
        name: 'A',
        description: '',
        collections: [
          CollectionTemplate(
            key: 'list',
            name: 'List',
            fields: [DateFieldTemplate('d', 'D'), DateFieldTemplate('d', 'E')],
          ),
        ],
      );
      expect(() => PluginRegistry([plugin]), throwsArgumentError);
    });

    test('an option key with a dot', () {
      const plugin = TurtlePlugin(
        id: 'a',
        name: 'A',
        description: '',
        collections: [
          CollectionTemplate(
            key: 'list',
            name: 'List',
            fields: [
              SelectFieldTemplate('s', 'S', options: [OptionTemplate('o.1', 'O', OptionColor.gray)]),
            ],
          ),
        ],
      );
      expect(() => PluginRegistry([plugin]), throwsArgumentError);
    });
  });
}
