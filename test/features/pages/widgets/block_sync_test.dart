import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/blocks_repository.dart';
import 'package:turtle_base/features/pages/widgets/block_sync.dart';

Node _paragraph(String id, String text, {Iterable<Node> children = const []}) {
  return Node(
    id: id,
    type: 'paragraph',
    attributes: {'delta': (Delta()..insert(text)).toJson()},
    children: children,
  );
}

void main() {
  late AppDatabase database;
  late BlocksRepository blocks;
  const pageId = 'page_1';

  setUp(() {
    database = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('a node with no matching block id creates a new block', () async {
    blocks = BlocksRepository(database);

    final document = Document(root: Node(type: 'page', children: [_paragraph('n1', 'hello')]));
    await syncBlocksFromDocument(
      blocks: blocks,
      pageId: pageId,
      document: document,
      currentBlocks: const [],
    );

    final stored = await database.select(database.blocks).get();
    expect(stored, hasLength(1));
    expect(stored.single.id, 'n1');
    expect(stored.single.type, 'paragraph');
  });

  test('an existing block is updated in place, not recreated', () async {
    blocks = BlocksRepository(database);
    await blocks.create(id: 'n1', pageId: pageId, type: 'paragraph', content: '{"delta":[]}');
    final before = await database.select(database.blocks).get();

    final document = Document(root: Node(type: 'page', children: [_paragraph('n1', 'edited')]));
    await syncBlocksFromDocument(
      blocks: blocks,
      pageId: pageId,
      document: document,
      currentBlocks: before,
    );

    final stored = await database.select(database.blocks).get();
    expect(stored, hasLength(1));
    expect(stored.single.id, 'n1');
    expect(stored.single.content, contains('edited'));
  });

  test('a block missing from the tree is soft-deleted', () async {
    blocks = BlocksRepository(database);
    await blocks.create(id: 'n1', pageId: pageId, type: 'paragraph');
    final before = await database.select(database.blocks).get();

    final document = Document.blank(withInitialText: false);
    await syncBlocksFromDocument(
      blocks: blocks,
      pageId: pageId,
      document: document,
      currentBlocks: before,
    );

    final stored = await (database.select(
      database.blocks,
    )..where((b) => b.id.equals('n1'))).getSingle();
    expect(stored.deletedAt, isNotNull);
  });

  test('moving a node to a new parent updates parentBlockId and position', () async {
    blocks = BlocksRepository(database);
    await blocks.create(id: 'parent', pageId: pageId, type: 'paragraph');
    await blocks.create(id: 'child', pageId: pageId, type: 'paragraph');
    final before = await database.select(database.blocks).get();

    // "child" is now nested under "parent" instead of being a sibling.
    final document = Document(
      root: Node(
        type: 'page',
        children: [_paragraph('parent', 'p', children: [_paragraph('child', 'c')])],
      ),
    );
    await syncBlocksFromDocument(
      blocks: blocks,
      pageId: pageId,
      document: document,
      currentBlocks: before,
    );

    final child = await (database.select(
      database.blocks,
    )..where((b) => b.id.equals('child'))).getSingle();
    expect(child.parentBlockId, 'parent');
    expect(child.position, 0);
  });
}
