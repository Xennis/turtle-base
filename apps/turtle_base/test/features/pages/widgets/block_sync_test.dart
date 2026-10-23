import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/files/widgets/attachment_block.dart';
import 'package:turtle_base/features/pages/data/blocks_repository.dart';
import 'package:turtle_base/features/pages/widgets/block_sync.dart';

Node _paragraph(String id, String text, {Iterable<Node> children = const []}) {
  return Node(id: id, type: 'paragraph', attributes: {'delta': (Delta()..insert(text)).toJson()}, children: children);
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

    final document = Document(
      root: Node(type: 'page', children: [_paragraph('n1', 'hello')]),
    );
    await syncBlocksFromDocument(blocks: blocks, pageId: pageId, document: document, currentBlocks: const []);

    final stored = await database.select(database.blocks).get();
    expect(stored, hasLength(1));
    expect(stored.single.id, 'n1');
    expect(stored.single.type, 'paragraph');
  });

  test('an existing block is updated in place, not recreated', () async {
    blocks = BlocksRepository(database);
    await blocks.create(id: 'n1', pageId: pageId, type: 'paragraph', content: '{"delta":[]}');
    final before = await database.select(database.blocks).get();

    final document = Document(
      root: Node(type: 'page', children: [_paragraph('n1', 'edited')]),
    );
    await syncBlocksFromDocument(blocks: blocks, pageId: pageId, document: document, currentBlocks: before);

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
    await syncBlocksFromDocument(blocks: blocks, pageId: pageId, document: document, currentBlocks: before);

    final stored = await (database.select(database.blocks)..where((b) => b.id.equals('n1'))).getSingle();
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
        children: [
          _paragraph('parent', 'p', children: [_paragraph('child', 'c')]),
        ],
      ),
    );
    await syncBlocksFromDocument(blocks: blocks, pageId: pageId, document: document, currentBlocks: before);

    final child = await (database.select(database.blocks)..where((b) => b.id.equals('child'))).getSingle();
    expect(child.parentBlockId, 'parent');
    expect(child.position, 0);
  });

  group('syncAttachmentsFromDocument', () {
    const file = AttachmentFile(fileHash: 'sha256-a', name: 'a.png', mimeType: 'image/png', size: 1);

    Document documentWith(List<String> attachmentIds) => Document(
      root: Node(type: 'page', children: [for (final id in attachmentIds) attachmentNode(id)]),
    );

    test('soft-deletes an attachment whose block is gone, restores it when it\'s back', () async {
      final attachments = AttachmentsRepository(database);
      final id = await attachments.create(pageId: pageId, file: file);

      await syncAttachmentsFromDocument(attachments: attachments, pageId: pageId, document: documentWith([]));
      expect((await attachments.byId(id))!.deletedAt, isNotNull);

      await syncAttachmentsFromDocument(attachments: attachments, pageId: pageId, document: documentWith([id]));
      expect((await attachments.byId(id))!.deletedAt, isNull);
    });

    test('leaves the page\'s field attachments alone', () async {
      final attachments = AttachmentsRepository(database);
      final id = await attachments.create(pageId: pageId, fieldId: 'field_1', file: file);

      await syncAttachmentsFromDocument(attachments: attachments, pageId: pageId, document: documentWith([]));

      expect((await attachments.byId(id))!.deletedAt, isNull);
    });

    test('copies another page\'s attachment and reports the new id', () async {
      final attachments = AttachmentsRepository(database);
      final foreign = await attachments.create(pageId: 'page_2', file: file);

      final replacements = await syncAttachmentsFromDocument(
        attachments: attachments,
        pageId: pageId,
        document: documentWith([foreign]),
      );

      final copy = await attachments.byId(replacements[foreign]!);
      expect(copy!.pageId, pageId);
      expect(copy.fileHash, 'sha256-a');
      expect((await attachments.byId(foreign))!.pageId, 'page_2');
    });

    test('ignores ids it doesn\'t know yet', () async {
      final attachments = AttachmentsRepository(database);

      final replacements = await syncAttachmentsFromDocument(
        attachments: attachments,
        pageId: pageId,
        document: documentWith(['not-synced-yet']),
      );

      expect(replacements, isEmpty);
    });
  });
}
