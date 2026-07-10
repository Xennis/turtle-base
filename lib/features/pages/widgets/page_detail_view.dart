import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/pages/widgets/block_document.dart';
import 'package:turtle_base/features/pages/widgets/block_sync.dart';

/// Shows a page's title and its blocks, editable. Works for both
/// freestanding pages and collection entries - they're the same
/// underlying thing (see ARCHITECTURE.md).
///
/// The editor state is loaded once and kept alive across rebuilds
/// (rather than reconstructed from the database like CollectionView's
/// grid) - rebuilding it on every change to the underlying data would
/// reset the user's cursor/selection on every keystroke, since editing
/// itself is what causes those changes. There's no external writer to
/// race against yet (sync is a later phase), so "load once, edit live,
/// write out" is enough for now.
class PageDetailView extends StatefulWidget {
  const PageDetailView({super.key, required this.pageId});

  final String pageId;

  @override
  State<PageDetailView> createState() => _PageDetailViewState();
}

class _PageDetailViewState extends State<PageDetailView> {
  EditorState? _editorState;
  TextEditingController? _titleController;
  FocusNode? _titleFocusNode;
  StreamSubscription<EditorTransactionValue>? _transactionSubscription;
  Timer? _debounceTimer;
  bool _initializedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedOnce) {
      _initializedOnce = true;
      _initialize();
    }
  }

  @override
  void didUpdateWidget(covariant PageDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageId != widget.pageId) {
      _disposeEditingState();
      _initialize();
    }
  }

  @override
  void dispose() {
    _disposeEditingState();
    super.dispose();
  }

  void _disposeEditingState() {
    _debounceTimer?.cancel();
    _transactionSubscription?.cancel();
    _editorState?.dispose();
    _titleController?.dispose();
    _titleFocusNode?.dispose();
    _editorState = null;
    _titleController = null;
    _titleFocusNode = null;
  }

  Future<void> _initialize() async {
    final scope = AppScope.of(context);
    final (page, blocks) = await (
      scope.pages.watchById(widget.pageId).first,
      scope.blocks.watchAllInPage(widget.pageId).first,
    ).wait;
    if (!mounted) return;

    final titleController = TextEditingController(text: page.title);
    final titleFocusNode = FocusNode();
    titleFocusNode.addListener(() {
      if (!titleFocusNode.hasFocus) {
        _saveTitle(scope, titleController.text);
      }
    });

    final editorState = EditorState(document: buildDocument(blocks))
      ..editable = true;
    final transactionSubscription = editorState.transactionStream.listen((event) {
      final (time, _, _) = event;
      if (time == TransactionTime.after) {
        _scheduleSync(scope, editorState);
      }
    });

    setState(() {
      _titleController = titleController;
      _titleFocusNode = titleFocusNode;
      _editorState = editorState;
      _transactionSubscription = transactionSubscription;
    });
  }

  void _saveTitle(AppScope scope, String value) {
    scope.pages.rename(widget.pageId, value.trim());
  }

  void _scheduleSync(AppScope scope, EditorState editorState) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      final currentBlocks = await scope.blocks.watchAllInPage(widget.pageId).first;
      await syncBlocksFromDocument(
        blocks: scope.blocks,
        pageId: widget.pageId,
        document: editorState.document,
        currentBlocks: currentBlocks,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final editorState = _editorState;
    if (editorState == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Untitled',
            ),
            onSubmitted: (value) => _saveTitle(AppScope.of(context), value),
          ),
        ),
        Expanded(
          child: AppFlowyEditor(editorState: editorState),
        ),
      ],
    );
  }
}
