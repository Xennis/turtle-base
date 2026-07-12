import 'dart:async';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../sync_transport.dart';

const _folderMimeType = 'application/vnd.google-apps.folder';

/// [SyncTransport] backed by a Google Drive app folder, using only
/// `drive.file`-scoped calls (files the app itself created/opened) - see
/// `.local/GOOGLE_DRIVE_SETUP.md` for why that scope was chosen.
///
/// Layout in Drive: one folder named [appFolderName] at the Drive root,
/// containing one subfolder per device (named after that device's CRDT
/// node id), each holding that device's changeset files - matching the
/// `<nodeId>/<file>` name convention `SyncController` already encodes
/// into the flat [SyncTransport] names.
class GoogleDriveTransport implements SyncTransport {
  GoogleDriveTransport({
    required http.Client authClient,
    this.appFolderName = 'turtle-base-sync',
  }) : _drive = drive.DriveApi(authClient);

  final drive.DriveApi _drive;
  final String appFolderName;

  String? _appFolderId;
  final _deviceFolderIds = <String, String>{};
  final _fileIds = <String, String>{};

  @override
  Future<void> upload(String name, Uint8List bytes) async {
    final (nodeId, fileName) = _splitName(name);
    final folderId = await _deviceFolder(nodeId);
    final created = await _drive.files.create(
      drive.File(name: fileName, parents: [folderId]),
      uploadMedia: drive.Media(Stream.value(bytes), bytes.length),
    );
    _fileIds[name] = created.id!;
  }

  @override
  Future<List<String>> list() async {
    final appFolderId = await _appFolder();
    final deviceFolders = await _drive.files.list(
      q: "'$appFolderId' in parents and mimeType='$_folderMimeType' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );

    final names = <String>[];
    for (final folder in deviceFolders.files ?? const <drive.File>[]) {
      final nodeId = folder.name!;
      _deviceFolderIds[nodeId] = folder.id!;

      final files = await _drive.files.list(
        q: "'${folder.id}' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id,name)',
      );
      for (final file in files.files ?? const <drive.File>[]) {
        final name = '$nodeId/${file.name}';
        _fileIds[name] = file.id!;
        names.add(name);
      }
    }
    return names;
  }

  @override
  Future<Uint8List> download(String name) async {
    final fileId = _fileIds[name] ?? await _findFileId(name);
    final media =
        await _drive.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;

    final bytes = BytesBuilder();
    await for (final chunk in media.stream) {
      bytes.add(chunk);
    }
    return bytes.toBytes();
  }

  Future<String> _findFileId(String name) async {
    final (nodeId, fileName) = _splitName(name);
    final folderId = await _deviceFolder(nodeId);
    final result = await _drive.files.list(
      q: "name='$fileName' and '$folderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    final fileId = result.files?.firstOrNull?.id;
    if (fileId == null) {
      throw StateError('GoogleDriveTransport: no file named "$name"');
    }
    _fileIds[name] = fileId;
    return fileId;
  }

  Future<String> _appFolder() async {
    final cached = _appFolderId;
    if (cached != null) return cached;

    final id = await _findOrCreateFolder(
      name: appFolderName,
      parentId: null,
    );
    _appFolderId = id;
    return id;
  }

  Future<String> _deviceFolder(String nodeId) async {
    final cached = _deviceFolderIds[nodeId];
    if (cached != null) return cached;

    final appFolderId = await _appFolder();
    final id = await _findOrCreateFolder(name: nodeId, parentId: appFolderId);
    _deviceFolderIds[nodeId] = id;
    return id;
  }

  Future<String> _findOrCreateFolder({
    required String name,
    required String? parentId,
  }) async {
    final parentClause = parentId == null ? '' : " and '$parentId' in parents";
    final existing = await _drive.files.list(
      q: "name='$name' and mimeType='$_folderMimeType' and trashed=false$parentClause",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    final existingId = existing.files?.firstOrNull?.id;
    if (existingId != null) return existingId;

    final created = await _drive.files.create(
      drive.File(
        name: name,
        mimeType: _folderMimeType,
        parents: parentId == null ? null : [parentId],
      ),
    );
    return created.id!;
  }

  (String, String) _splitName(String name) {
    final slash = name.indexOf('/');
    if (slash == -1) {
      throw ArgumentError.value(name, 'name', 'expected "<nodeId>/<file>"');
    }
    return (name.substring(0, slash), name.substring(slash + 1));
  }
}
