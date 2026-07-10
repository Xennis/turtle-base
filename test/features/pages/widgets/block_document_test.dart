import 'package:flutter_test/flutter_test.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/widgets/block_document.dart';

Block _block({
  required String id,
  String? parentBlockId,
  required int position,
  String type = 'paragraph',
  String? text,
}) {
  final now = DateTime.now();
  return Block(
    id: id,
    pageId: 'page_1',
    parentBlockId: parentBlockId,
    type: type,
    position: position,
    content: '{"delta": [{"insert": "${text ?? ''}"}]}',
    createdAt: now,
    updatedAt: now,
    createdBy: 'user_1',
    updatedBy: 'user_1',
  );
}

void main() {
  test('empty blocks produce a blank document with one paragraph', () {
    final document = buildDocument([]);

    expect(document.root.children, hasLength(1));
    expect(document.root.children.single.type, 'paragraph');
  });

  test('top-level blocks become siblings in position order', () {
    final blocks = [
      _block(id: 'b2', position: 1, text: 'second'),
      _block(id: 'b1', position: 0, text: 'first'),
    ];

    final document = buildDocument(blocks);

    expect(document.root.children, hasLength(2));
    expect(document.root.children[0].delta!.toPlainText(), 'first');
    expect(document.root.children[1].delta!.toPlainText(), 'second');
    // block_sync.dart relies on Node.id matching Block.id to tell
    // edited blocks from newly-created ones.
    expect(document.root.children[0].id, 'b1');
    expect(document.root.children[1].id, 'b2');
  });

  test('nested blocks become child nodes, not siblings', () {
    final blocks = [
      _block(id: 'parent', position: 0, text: 'parent'),
      _block(id: 'child', parentBlockId: 'parent', position: 0, text: 'child'),
    ];

    final document = buildDocument(blocks);

    expect(document.root.children, hasLength(1));
    final parentNode = document.root.children.single;
    expect(parentNode.delta!.toPlainText(), 'parent');
    expect(parentNode.children, hasLength(1));
    expect(parentNode.children.single.delta!.toPlainText(), 'child');
  });
}
