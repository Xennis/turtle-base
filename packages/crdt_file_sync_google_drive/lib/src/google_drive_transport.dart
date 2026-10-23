import 'dart:async';
import 'dart:typed_data';

import 'package:crdt_file_sync_transport/crdt_file_sync_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'drive_folders.dart';

/// [SyncTransport] for changesets: one subfolder per device (named after
/// that device's CRDT node id) below the folder at [path], each holding
/// that device's changeset files - matching the `<nodeId>/<file>` name
/// convention `SyncController` encodes into the flat names.
class GoogleDriveTransport implements SyncTransport {
  GoogleDriveTransport(this._folders, this.path);

  final DriveFolders _folders;
  final List<String> path;

  final _fileIds = <String, String>{};

  drive.DriveApi get _api => _folders.api;

  @override
  Future<void> upload(String name, Uint8List bytes) async {
    final (nodeId, fileName) = _splitName(name);
    final folderId = await _folders.resolve([...path, nodeId]);
    final created = await _api.files.create(
      drive.File(name: fileName, parents: [folderId]),
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
    );
    _fileIds[name] = created.id!;
  }

  @override
  Future<List<String>> list() async {
    final rootId = await _folders.resolve(path);
    final deviceFolders = await _folders.childFolders(rootId);
    debugPrint(
      '[sync] drive: ${path.join('/')} ($rootId) has ${deviceFolders.length} device folder(s): '
      '${deviceFolders.map((f) => '${f.name} (${f.id})').toList()}',
    );

    final names = <String>[];
    for (final folder in deviceFolders) {
      final files = await _folders.childFiles(folder.id!);
      debugPrint('[sync] drive: device folder ${folder.name} has ${files.length} file(s)');
      for (final file in files) {
        final name = '${folder.name}/${file.name}';
        _fileIds[name] = file.id!;
        names.add(name);
      }
    }
    return names;
  }

  @override
  Future<Uint8List> download(String name) async {
    final fileId = _fileIds[name] ?? await _findFileId(name);
    final media = await _api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;

    final bytes = BytesBuilder();
    await for (final chunk in media.stream) {
      bytes.add(chunk);
    }
    return bytes.toBytes();
  }

  Future<String> _findFileId(String name) async {
    final (nodeId, fileName) = _splitName(name);
    final folderId = await _folders.resolve([...path, nodeId]);
    final fileId = (await _folders.childFiles(folderId, name: fileName)).firstOrNull?.id;
    if (fileId == null) {
      throw StateError('GoogleDriveTransport: no file named "$name"');
    }
    _fileIds[name] = fileId;
    return fileId;
  }

  (String, String) _splitName(String name) {
    final slash = name.indexOf('/');
    if (slash == -1) {
      throw ArgumentError.value(name, 'name', 'expected "<nodeId>/<file>"');
    }
    return (name.substring(0, slash), name.substring(slash + 1));
  }
}
