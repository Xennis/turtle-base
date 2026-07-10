import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:turtle_base/core/database/app_database.dart';

/// Converts our flat, sync-friendly [Block] rows (see ARCHITECTURE.md -
/// one row per block rather than one JSON blob per page) into the
/// single connected Node tree appflowy_editor's Document expects.
///
/// A block's `content` maps to its Node's `attributes` (the `data` in
/// Node JSON) - `type` and `children` come from the block row itself
/// and its children, not from `content`.
///
/// Each Node's id is set to its Block's id (appflowy_editor defaults
/// to a random one otherwise) - block_sync.dart relies on this to tell
/// "still the same block" from "the user created a new one" when
/// syncing edits back to storage.
Document buildDocument(List<Block> blocks) {
  if (blocks.isEmpty) {
    // AppFlowy's document rules require at least one editable node.
    return Document.blank(withInitialText: true);
  }

  final byParent = <String?, List<Block>>{};
  for (final block in blocks) {
    byParent.putIfAbsent(block.parentBlockId, () => []).add(block);
  }
  for (final siblings in byParent.values) {
    siblings.sort((a, b) => a.position.compareTo(b.position));
  }

  Node buildNode(Block block) {
    return Node(
      id: block.id,
      type: block.type,
      attributes: Map<String, dynamic>.from(
        jsonDecode(block.content) as Map,
      ),
      children: [for (final child in byParent[block.id] ?? []) buildNode(child)],
    );
  }

  return Document(
    root: Node(
      type: 'page',
      children: [for (final block in byParent[null] ?? []) buildNode(block)],
    ),
  );
}
