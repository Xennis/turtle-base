import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/blocks_repository.dart';

/// Reconciles the editor's current Node tree back into our flat Block
/// rows - the reverse of block_document.dart's buildDocument().
///
/// A node's id is preserved from its Block.id when the document was
/// built (see buildDocument), so a node can be told apart as "an
/// existing block, maybe changed", "a block the user removed" (no
/// longer present), or "a brand new block" (an id not in
/// [currentBlocks], e.g. a fresh paragraph from pressing Enter) by id
/// alone, without diffing content structurally.
Future<void> syncBlocksFromDocument({
  required BlocksRepository blocks,
  required String pageId,
  required Document document,
  required List<Block> currentBlocks,
}) async {
  final currentById = {for (final block in currentBlocks) block.id: block};
  final seenIds = <String>{};

  Future<void> walk(Iterable<Node> nodes, String? parentId) async {
    var position = 0;
    for (final node in nodes) {
      seenIds.add(node.id);
      final content = jsonEncode(node.attributes);
      final existing = currentById[node.id];

      if (existing == null) {
        await blocks.create(
          id: node.id,
          pageId: pageId,
          parentBlockId: parentId,
          type: node.type,
          content: content,
        );
        await blocks.move(node.id, parentBlockId: parentId, position: position);
      } else {
        if (existing.type != node.type) {
          await blocks.changeType(node.id, node.type);
        }
        if (existing.content != content) {
          await blocks.updateContent(node.id, content);
        }
        if (existing.parentBlockId != parentId || existing.position != position) {
          await blocks.move(node.id, parentBlockId: parentId, position: position);
        }
      }

      await walk(node.children, node.id);
      position++;
    }
  }

  await walk(document.root.children, null);

  for (final block in currentBlocks) {
    if (!seenIds.contains(block.id)) {
      await blocks.softDelete(block.id);
    }
  }
}
