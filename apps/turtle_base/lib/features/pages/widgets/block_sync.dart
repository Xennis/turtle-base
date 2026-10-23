import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/files/widgets/attachment_block.dart';
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
        await blocks.create(id: node.id, pageId: pageId, parentBlockId: parentId, type: node.type, content: content);
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

/// Keeps the page's rich-text attachments (those without a field) in
/// step with the `attachment` nodes in [document]: an attachment is
/// active exactly while a node references it - removing the block
/// soft-deletes it, undoing that restores it.
///
/// A node referencing another page's attachment (pasted from there)
/// gets a copy of its own, so the two pages don't share one row. Returns
/// those replacements, old id to new, for the caller to write into the
/// nodes.
Future<Map<String, String>> syncAttachmentsFromDocument({
  required AttachmentsRepository attachments,
  required String pageId,
  required Document document,
}) async {
  final referenced = <String>{};
  void walk(Iterable<Node> nodes) {
    for (final node in nodes) {
      if (node.type == AttachmentBlockKeys.type) {
        if (node.attributes[AttachmentBlockKeys.attachmentId] case final String id) referenced.add(id);
      }
      walk(node.children);
    }
  }

  walk(document.root.children);

  final own = {for (final attachment in await attachments.allInPageContent(pageId)) attachment.id: attachment};
  final replacements = <String, String>{};
  for (final id in referenced) {
    final attachment = own[id];
    if (attachment != null) {
      if (attachment.deletedAt != null) await attachments.restore(id);
      continue;
    }
    // Unknown here - another page's, or not synced in yet (then it's
    // left alone).
    final foreign = await attachments.byId(id);
    if (foreign != null) replacements[id] = await attachments.copyTo(foreign, pageId: pageId);
  }
  for (final attachment in own.values) {
    if (attachment.deletedAt == null && !referenced.contains(attachment.id)) {
      await attachments.softDelete(attachment.id);
    }
  }
  return replacements;
}
