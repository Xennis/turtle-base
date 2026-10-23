import 'package:crdt_file_sync_transport/crdt_file_sync_transport.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'drive_folders.dart';

/// [FileTransport] backed by one flat Drive folder at [path].
class GoogleDriveFileTransport implements FileTransport {
  GoogleDriveFileTransport(this._folders, this.path);

  /// From this size on, uploads use Drive's resumable protocol (chunked,
  /// retried per chunk) instead of a single multipart request.
  static const resumableThreshold = 5 * 1024 * 1024;

  final DriveFolders _folders;
  final List<String> path;

  final _fileIds = <String, String>{};

  drive.DriveApi get _api => _folders.api;

  @override
  Future<void> upload(String name, Stream<List<int>> bytes, int length) async {
    final folderId = await _folders.resolve(path);
    final created = await _api.files.create(
      drive.File(name: name, parents: [folderId]),
      uploadMedia: drive.Media(bytes, length),
      uploadOptions: length >= resumableThreshold ? drive.UploadOptions.resumable : drive.UploadOptions.defaultOptions,
    );
    _fileIds[name] = created.id!;
  }

  @override
  Future<Set<String>> list() async {
    final folderId = await _folders.resolve(path);
    final names = <String>{};
    for (final file in await _folders.childFiles(folderId)) {
      _fileIds[file.name!] = file.id!;
      names.add(file.name!);
    }
    return names;
  }

  @override
  Stream<List<int>> download(String name) async* {
    final fileId = _fileIds[name] ?? await _findFileId(name);
    final media = await _api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    yield* media.stream;
  }

  Future<String> _findFileId(String name) async {
    final folderId = await _folders.resolve(path);
    final fileId = (await _folders.childFiles(folderId, name: name)).firstOrNull?.id;
    if (fileId == null) {
      throw StateError('GoogleDriveFileTransport: no file named "$name"');
    }
    return _fileIds[name] = fileId;
  }
}
