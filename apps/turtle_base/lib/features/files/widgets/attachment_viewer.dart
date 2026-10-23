import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/core/sync/sync_scope.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/files/widgets/stored_file_builder.dart';
import 'package:turtle_base/packages/file_store/file_store.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows an image full-size, opens any other file with the system's app
/// for its type.
Future<void> openAttachment(BuildContext context, Attachment attachment) async {
  if (attachment.isImage) {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _ImageViewer(attachment: attachment),
    );
    return;
  }
  await openExternally(context, attachment);
}

/// Opens the file with the system's app for its type. The store names
/// files by hash, without an extension the system could tell the type
/// from - so it opens a copy under the attachment's own name.
Future<void> openExternally(BuildContext context, Attachment attachment) async {
  final scope = AppScope.of(context);
  final sync = SyncScope.maybeOf(context);
  final toaster = ShadToaster.of(context);
  var original = scope.files.originalIfPresent(attachment.fileHash);
  if (original == null && sync != null && sync.isConnected) {
    toaster.show(ShadToast(title: Text('Downloading ${attachment.name}…')));
    if (await sync.fetchFile(attachment.fileHash)) original = scope.files.originalIfPresent(attachment.fileHash);
  }
  if (original == null) {
    toaster.show(ShadToast.destructive(title: Text('${attachment.name} is not available offline')));
    return;
  }
  final copy = await _namedCopy(original, attachment);
  final opened = defaultTargetPlatform == TargetPlatform.android
      ? (await OpenFilex.open(copy.path, type: attachment.mimeType)).type == ResultType.done
      : await launchUrl(Uri.file(copy.path));
  if (!opened) toaster.show(ShadToast.destructive(title: Text('No app found to open ${attachment.name}')));
}

Future<File> _namedCopy(File original, Attachment attachment) async {
  final dir = Directory(p.join((await getTemporaryDirectory()).path, 'open', attachment.id));
  await dir.create(recursive: true);
  // basename - the name came in from another device via sync.
  final copy = File(p.join(dir.path, p.basename(attachment.name)));
  if (!await copy.exists() || await copy.length() != await original.length()) {
    await original.copy(copy.path);
  }
  return copy;
}

/// Starts downloading the original if it's missing - the thumbnail
/// shows meanwhile.
class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.attachment});

  final Attachment attachment;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  bool _fetching = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sync = SyncScope.maybeOf(context);
    final files = AppScope.of(context).files;
    if (_fetching || sync == null || !sync.isConnected) return;
    if (files.originalIfPresent(widget.attachment.fileHash) != null) return;
    _fetching = true;
    sync.fetchFile(widget.attachment.fileHash).whenComplete(() {
      if (mounted) setState(() => _fetching = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final files = AppScope.of(context).files;
    final hash = attachment.fileHash;
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: StoredFileBuilder(
              names: [hash, FileStore.thumbnailNameOf(hash)],
              builder: (context) {
                final original = files.originalIfPresent(hash);
                final file = original ?? files.thumbnailIfPresent(hash);
                if (file == null) {
                  return Center(
                    child: _fetching
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Not available offline', style: TextStyle(color: Colors.white)),
                  );
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        maxScale: 8,
                        // Keyed by file, so the original replaces the
                        // thumbnail once it's downloaded.
                        child: Center(
                          child: Image.file(file, key: ValueKey(file.path), fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    if (original == null && _fetching)
                      const Positioned(
                        right: 16,
                        bottom: 16,
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Tooltip(
                    message: 'Open with…',
                    child: IconButton(
                      icon: const Icon(Icons.open_in_new, color: Colors.white),
                      onPressed: () => openExternally(context, attachment),
                    ),
                  ),
                  Tooltip(
                    message: 'Close',
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
