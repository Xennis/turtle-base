import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/plugins/data/entry_draft_writer.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

/// Searches [lookup] and adds the picked result to the collection - or
/// opens the entry it's already in. The same dialog for every plugin;
/// a plugin only provides the search.
Future<void> showEntryLookup(
  BuildContext context, {
  required String collectionId,
  required EntryLookup lookup,
  required ValueChanged<String> onOpenEntry,
  EntryDraftWriter? writer,
}) async {
  final scope = AppScope.of(context);
  final pageId = await showShadDialog<String>(
    context: context,
    builder: (context) => _EntryLookupDialog(
      collectionId: collectionId,
      lookup: lookup,
      writer: writer ?? EntryDraftWriter(scope.database, fieldTypes: scope.fieldTypes, files: scope.files),
    ),
  );
  if (pageId != null) onOpenEntry(pageId);
}

class _EntryLookupDialog extends StatefulWidget {
  const _EntryLookupDialog({required this.collectionId, required this.lookup, required this.writer});

  final String collectionId;
  final EntryLookup lookup;
  final EntryDraftWriter writer;

  @override
  State<_EntryLookupDialog> createState() => _EntryLookupDialogState();
}

class _EntryLookupDialogState extends State<_EntryLookupDialog> {
  static const _debounce = Duration(milliseconds: 400);

  Timer? _timer;
  String _query = '';
  List<EntryDraft> _results = const [];
  bool _searching = false;
  String? _error;
  bool _adding = false;

  /// Bumped per search, so an answer to an older query that arrives
  /// late is dropped.
  int _generation = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _query = value.trim();
    if (_query.isEmpty) {
      _generation++;
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() {});
    _timer = Timer(_debounce, _search);
  }

  Future<void> _search() async {
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.lookup.search(_query);
      if (!mounted || generation != _generation) return;
      setState(() => _results = results);
    } on LookupException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = const [];
        _error = e.message;
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _searching = false);
    }
  }

  Future<void> _add(EntryDraft draft) async {
    setState(() => _adding = true);
    final writer = widget.writer;
    final collectionId = widget.collectionId;
    try {
      final existing = await writer.findExisting(collectionId, draft, uniqueFieldKey: widget.lookup.uniqueFieldKey);
      if (existing != null) {
        if (mounted) Navigator.of(context).pop(existing);
        return;
      }
      final pageId = await writer.create(collectionId, draft);
      // In the background - the entry is there and usable right away,
      // its cover lands when downloaded.
      unawaited(writer.attachFiles(collectionId, pageId, draft));
      if (mounted) Navigator.of(context).pop(pageId);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadDialog(
      title: Text(widget.lookup.actionLabel),
      actions: [ShadButton.outline(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
      child: SizedBox(
        width: 480,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadInput(
              autofocus: true,
              placeholder: Text(widget.lookup.searchHint),
              leading: const Icon(Icons.search, size: 16),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildResults(theme)),
            if (_query.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: ShadButton.ghost(
                  leading: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: _adding ? null : () => _add(EntryDraft(title: _query)),
                  child: Flexible(child: Text('Add "$_query" manually', maxLines: 1, overflow: TextOverflow.ellipsis)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ShadThemeData theme) {
    if (_searching && _results.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error case final error?) {
      return Center(
        child: Text(error, style: theme.textTheme.muted.copyWith(color: theme.colorScheme.destructive)),
      );
    }
    if (_query.isEmpty) return const SizedBox.shrink();
    if (_results.isEmpty && _timer?.isActive != true) {
      return Center(child: Text('Nothing found', style: theme.textTheme.muted));
    }
    // ShadDialog has no Material of its own, which InkWell needs.
    return Material(
      type: MaterialType.transparency,
      child: ListView.builder(
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final draft = _results[index];
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _adding ? null : () => _add(draft),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  _Thumbnail(uri: draft.thumbnail),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(draft.title, style: theme.textTheme.small, maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (draft.subtitle case final subtitle?)
                          Text(subtitle, style: theme.textTheme.muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: ShadTheme.of(context).colorScheme.muted,
      child: const Center(child: Icon(Icons.image_outlined, size: 16)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 40,
        height: 56,
        child: uri == null
            ? placeholder
            : Image.network(uri.toString(), fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
      ),
    );
  }
}
