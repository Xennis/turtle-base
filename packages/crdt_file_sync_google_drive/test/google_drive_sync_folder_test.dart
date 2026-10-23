import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_file_sync_google_drive/crdt_file_sync_google_drive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _folderMimeType = 'application/vnd.google-apps.folder';

/// Minimal in-memory stand-in for the Drive REST API, just enough of it to
/// exercise [GoogleDriveSyncFolder]'s folder-lookup/create, paged listing
/// and upload/list/download logic without a real network call. Understands
/// the same fixed multipart boundary `package:_discoveryapis_commons`
/// always uses for media uploads (see its `MultipartMediaUploader`).
class _FakeDriveFile {
  _FakeDriveFile({required this.id, required this.name, required this.mimeType, required this.parents, this.bytes});

  final String id;
  final String name;
  final String mimeType;
  final List<String> parents;
  Uint8List? bytes;
}

class _FakeDrive {
  _FakeDrive({this.maxPageSize = 1000});

  /// Caps a page below the requested pageSize, to exercise paging
  /// without creating a thousand files.
  final int maxPageSize;

  final _files = <String, _FakeDriveFile>{};
  var _nextId = 0;

  http.Client get client => MockClient(_handle);

  Iterable<_FakeDriveFile> get folders => _files.values.where((f) => f.mimeType == _folderMimeType);

  _FakeDriveFile folderAt(List<String> path) {
    String? parentId;
    late _FakeDriveFile folder;
    for (final name in path) {
      folder = folders.singleWhere((f) => f.name == name && (parentId == null || f.parents.contains(parentId)));
      parentId = folder.id;
    }
    return folder;
  }

  Iterable<_FakeDriveFile> filesIn(_FakeDriveFile folder) => _files.values.where((f) => f.parents.contains(folder.id));

  Future<http.Response> _handle(http.Request request) async {
    final uri = request.url;
    final segments = uri.pathSegments;

    if (request.method == 'GET' && segments.join('/') == 'drive/v3/files') {
      return _handleList(uri);
    }
    if (request.method == 'GET' && segments.length == 4 && segments.sublist(0, 3).join('/') == 'drive/v3/files') {
      return _handleDownload(segments[3]);
    }
    if (request.method == 'POST' && segments.join('/') == 'drive/v3/files') {
      return _handleCreate(request, metadataOnly: true);
    }
    if (request.method == 'POST' && segments.join('/') == 'upload/drive/v3/files') {
      return _handleCreate(request, metadataOnly: false);
    }
    if (request.method == 'PATCH' &&
        segments.length == 5 &&
        segments.sublist(0, 4).join('/') == 'upload/drive/v3/files') {
      return _handleUpdate(request, segments[4]);
    }
    return http.Response('unhandled ${request.method} $uri', 404);
  }

  http.Response _handleList(Uri uri) {
    final query = uri.queryParameters['q'] ?? '';
    final matches = _files.values.where((f) => _matchesQuery(f, query)).toList();
    final pageSize = [int.parse(uri.queryParameters['pageSize'] ?? '100'), maxPageSize].reduce((a, b) => a < b ? a : b);
    final offset = int.parse(uri.queryParameters['pageToken'] ?? '0');
    final page = matches.skip(offset).take(pageSize).toList();
    final nextOffset = offset + page.length;
    return _json({
      'files': [
        for (final f in page) {'id': f.id, 'name': f.name},
      ],
      if (nextOffset < matches.length) 'nextPageToken': '$nextOffset',
    });
  }

  bool _matchesQuery(_FakeDriveFile f, String query) {
    // Queries are built as a conjunction of clauses - just check each
    // expected fragment is satisfied rather than writing a real parser.
    final isFolder = f.mimeType == _folderMimeType;
    if (query.contains("mimeType='$_folderMimeType'") && !isFolder) return false;
    if (query.contains("mimeType!='$_folderMimeType'") && isFolder) return false;

    final nameMatch = RegExp("name='([^']*)'").firstMatch(query);
    if (nameMatch != null && f.name != nameMatch.group(1)) return false;

    final parentMatch = RegExp("'([^']*)' in parents").firstMatch(query);
    if (parentMatch != null && !f.parents.contains(parentMatch.group(1))) {
      return false;
    }
    return true;
  }

  http.Response _handleDownload(String fileId) {
    final file = _files[fileId];
    if (file == null) return http.Response('not found', 404);
    return http.Response.bytes(file.bytes ?? Uint8List(0), 200, headers: {'content-type': 'application/octet-stream'});
  }

  http.Response _handleCreate(http.Request request, {required bool metadataOnly}) {
    final id = 'file-${_nextId++}';
    Map<String, dynamic> metadata;
    Uint8List? bytes;

    if (metadataOnly) {
      metadata = jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;
    } else {
      (metadata, bytes) = _parseMultipartRelated(request);
    }

    final file = _FakeDriveFile(
      id: id,
      name: metadata['name'] as String,
      mimeType: (metadata['mimeType'] as String?) ?? 'application/octet-stream',
      parents: (metadata['parents'] as List?)?.cast<String>() ?? const [],
      bytes: bytes,
    );
    _files[id] = file;
    return _json({'id': id, 'name': file.name});
  }

  http.Response _handleUpdate(http.Request request, String fileId) {
    final file = _files[fileId];
    if (file == null) return http.Response('not found', 404);
    file.bytes = _parseMultipartRelated(request).$2;
    return _json({'id': file.id, 'name': file.name});
  }

  http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  (Map<String, dynamic>, Uint8List) _parseMultipartRelated(http.Request request) {
    final contentType = request.headers['content-type']!;
    final boundary = RegExp('boundary="([^"]*)"').firstMatch(contentType)!.group(1)!;
    final body = ascii.decode(request.bodyBytes);
    final parts = body.split('--$boundary').where((p) => p.trim().isNotEmpty && p.trim() != '--').toList();

    final metadataPart = parts[0];
    final metadataJson = metadataPart.substring(metadataPart.indexOf('\r\n\r\n') + 4).trim();
    final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;

    final mediaPart = parts[1];
    final base64Body = mediaPart.substring(mediaPart.indexOf('\r\n\r\n') + 4).trim();
    final bytes = base64Decode(base64Body);

    return (metadata, bytes);
  }
}

Stream<List<int>> _streamOf(List<int> bytes) => Stream.value(bytes);

void main() {
  group('changesets', () {
    test('upload() creates the folder path and a per-device subfolder lazily', () async {
      final drive = _FakeDrive();
      final folder = GoogleDriveSyncFolder(authClient: drive.client);

      await folder.changesets.upload('node-a/1.json', Uint8List.fromList(utf8.encode('hello')));

      expect(drive.folderAt(['turtle-base-sync', 'changesets', 'node-a']).name, 'node-a');
    });

    test('list() returns names for every device folder', () async {
      final drive = _FakeDrive();
      await GoogleDriveSyncFolder(authClient: drive.client).changesets.upload('node-a/1.json', Uint8List.fromList([1]));
      await GoogleDriveSyncFolder(authClient: drive.client).changesets.upload('node-b/1.json', Uint8List.fromList([2]));

      // A fresh instance (no locally cached folder ids) must still
      // discover both devices' folders/files by listing through Drive.
      final names = await GoogleDriveSyncFolder(authClient: drive.client).changesets.list();

      expect(names, containsAll(['node-a/1.json', 'node-b/1.json']));
    });

    test('list() follows nextPageToken past the first page', () async {
      final drive = _FakeDrive(maxPageSize: 2);
      final folder = GoogleDriveSyncFolder(authClient: drive.client);
      for (var i = 0; i < 5; i++) {
        await folder.changesets.upload('node-a/$i.json', Uint8List.fromList([i]));
      }
      for (final node in ['node-b', 'node-c']) {
        await folder.changesets.upload('$node/0.json', Uint8List.fromList([0]));
      }

      final names = await GoogleDriveSyncFolder(authClient: drive.client).changesets.list();

      expect(names, hasLength(7));
    });

    test('upload() then download() round-trips the bytes', () async {
      final drive = _FakeDrive();
      final folder = GoogleDriveSyncFolder(authClient: drive.client);
      final bytes = Uint8List.fromList(utf8.encode('{"spaces":[]}'));

      await folder.changesets.upload('node-a/1.json', bytes);
      final downloaded = await GoogleDriveSyncFolder(authClient: drive.client).changesets.download('node-a/1.json');

      expect(downloaded, bytes);
    });

    test('two uploads from the same device reuse the same device folder', () async {
      final drive = _FakeDrive();
      final folder = GoogleDriveSyncFolder(authClient: drive.client);

      await folder.changesets.upload('node-a/1.json', Uint8List.fromList([1]));
      await folder.changesets.upload('node-a/2.json', Uint8List.fromList([2]));

      expect(drive.folders.where((f) => f.name == 'node-a'), hasLength(1));
    });

    test('list() ignores the files folder and format file next to it', () async {
      final drive = _FakeDrive();
      final folder = GoogleDriveSyncFolder(authClient: drive.client);
      await folder.changesets.upload('node-a/1.json', Uint8List.fromList([1]));
      await folder.files.upload('sha256-abc', _streamOf([1, 2]), 2);
      await folder.writeFormatVersion(2);

      expect(await folder.changesets.list(), ['node-a/1.json']);
    });
  });

  group('files', () {
    test('upload() stores flat in the files folder', () async {
      final drive = _FakeDrive();
      final folder = GoogleDriveSyncFolder(authClient: drive.client);

      await folder.files.upload('sha256-abc', _streamOf([1, 2, 3]), 3);

      final filesFolder = drive.folderAt(['turtle-base-sync', 'files']);
      expect(drive.filesIn(filesFolder).map((f) => f.name), ['sha256-abc']);
    });

    test('list() returns every name, across pages', () async {
      final drive = _FakeDrive(maxPageSize: 2);
      final folder = GoogleDriveSyncFolder(authClient: drive.client);
      for (var i = 0; i < 5; i++) {
        await folder.files.upload('sha256-$i', _streamOf([i]), 1);
      }

      final names = await GoogleDriveSyncFolder(authClient: drive.client).files.list();

      expect(names, {for (var i = 0; i < 5; i++) 'sha256-$i'});
    });

    test('download() streams the uploaded bytes, also from a fresh instance', () async {
      final drive = _FakeDrive();
      await GoogleDriveSyncFolder(authClient: drive.client).files.upload('sha256-abc', _streamOf([4, 5, 6]), 3);

      final chunks = await GoogleDriveSyncFolder(authClient: drive.client).files.download('sha256-abc').toList();

      expect(chunks.expand((c) => c), [4, 5, 6]);
    });
  });

  group('format', () {
    test('readFormatVersion() is null until written', () async {
      final folder = GoogleDriveSyncFolder(authClient: _FakeDrive().client);

      expect(await folder.readFormatVersion(), isNull);
    });

    test('writeFormatVersion() creates format.json once and updates it after', () async {
      final drive = _FakeDrive();
      final folder = GoogleDriveSyncFolder(authClient: drive.client);

      await folder.writeFormatVersion(2);
      await folder.writeFormatVersion(3);

      final root = drive.folderAt(['turtle-base-sync']);
      expect(drive.filesIn(root).where((f) => f.name == 'format.json'), hasLength(1));
      expect(await GoogleDriveSyncFolder(authClient: drive.client).readFormatVersion(), 3);
    });
  });
}
