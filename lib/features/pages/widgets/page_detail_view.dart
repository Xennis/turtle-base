import 'package:appflowy_editor/appflowy_editor.dart';
// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/widgets/block_document.dart';

/// Shows a page's title and its blocks, read-only for now (editing is
/// a later step). Works for both freestanding pages and collection
/// entries - they're the same underlying thing (see ARCHITECTURE.md).
class PageDetailView extends StatefulWidget {
  const PageDetailView({super.key, required this.pageId});

  final String pageId;

  @override
  State<PageDetailView> createState() => _PageDetailViewState();
}

class _PageDetailViewState extends State<PageDetailView> {
  EditorState? _editorState;
  String? _blocksVersion;

  @override
  void dispose() {
    _editorState?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<Page>(
      stream: scope.pages.watchById(widget.pageId),
      builder: (context, pageSnapshot) {
        final page = pageSnapshot.data;
        return StreamBuilder<List<Block>>(
          stream: scope.blocks.watchAllInPage(widget.pageId),
          builder: (context, blocksSnapshot) {
            final blocks = blocksSnapshot.data ?? const <Block>[];
            final version = _versionOf(blocks);
            // Rebuild the EditorState only when the blocks actually
            // change, not on every incidental rebuild - it owns
            // meaningful internal state (selection, in a later step).
            if (_editorState == null || _blocksVersion != version) {
              _editorState?.dispose();
              _editorState = EditorState(document: buildDocument(blocks))
                ..editable = false;
              _blocksVersion = version;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    (page == null || page.title.isEmpty) ? 'Untitled' : page.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Expanded(
                  child: AppFlowyEditor(
                    key: ValueKey(version),
                    editorState: _editorState!,
                    editable: false,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _versionOf(List<Block> blocks) {
    return blocks
        .map((b) => '${b.id}:${b.updatedAt.millisecondsSinceEpoch}')
        .join(',');
  }
}
