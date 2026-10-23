import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/features/files/data/attachments_repository.dart';
import 'package:turtle_base/features/files/data/file_accept.dart';

/// Lets the user pick files and attaches the ones [accept] takes to the
/// page's field ([fieldId]) or, without one, its rich text - at most
/// [maxCount]. Rejected files are named in a toast. Returns the new
/// attachments' ids, empty when nothing was picked.
Future<List<String>> pickAndAttach(
  BuildContext context, {
  required String pageId,
  String? fieldId,
  FileAccept accept = FileAccept.any,
  int? maxCount,
}) async {
  final scope = AppScope.of(context);
  final toaster = ShadToaster.of(context);
  final extensions = accept.dialogExtensions;
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: maxCount != 1,
    type: accept.isImagesOnly
        ? FileType.image
        : extensions != null
        ? FileType.custom
        : FileType.any,
    allowedExtensions: accept.isImagesOnly ? null : extensions,
  );
  if (result == null) return const [];

  final ids = <String>[];
  final rejected = <String>[];
  for (final picked in result.files) {
    final path = picked.path;
    if (path == null) continue;
    if (maxCount != null && ids.length >= maxCount) {
      rejected.add(picked.name);
      continue;
    }
    final stored = await scope.files.import(File(path));
    // Checked after importing, against the type read from the content
    // - the dialog's filter only goes by extension.
    if (!accept.accepts(mimeType: stored.mimeType, fileName: picked.name)) {
      rejected.add(picked.name);
      continue;
    }
    ids.add(
      await scope.attachments.create(
        pageId: pageId,
        fieldId: fieldId,
        file: AttachmentFile(
          fileHash: stored.hash,
          name: picked.name,
          mimeType: stored.mimeType,
          size: stored.size,
          width: stored.width,
          height: stored.height,
        ),
      ),
    );
  }
  // On mobile the picker hands out copies in the app's cache, the store
  // has its own now.
  if (defaultTargetPlatform == TargetPlatform.android) await FilePicker.platform.clearTemporaryFiles();

  if (rejected.isNotEmpty) {
    toaster.show(ShadToast.destructive(title: Text('Not added: ${rejected.join(', ')}')));
  }
  return ids;
}
