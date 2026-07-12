import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:turtle_base/packages/crdt_file_sync/google_drive/google_drive_transport.dart';

/// Minimal in-memory stand-in for the Drive REST API, just enough of it to
/// exercise [GoogleDriveTransport]'s folder-lookup/create and
/// upload/list/download logic without a real network call. Understands the
/// same fixed multipart boundary `package:_discoveryapis_commons` always
/// uses for media uploads (see its `MultipartMediaUploader`).
class _FakeDriveFile {
  _FakeDriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.parents,
    this.bytes,
  });

  final String id;
  final String name;
  final String mimeType;
  final List<String> parents;
  Uint8List? bytes;
}

class _FakeDrive {
  final _files = <String, _FakeDriveFile>{};
  var _nextId = 0;

  http.Client get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final uri = request.url;
    final segments = uri.pathSegments;

    if (request.method == 'GET' && segments.join('/') == 'drive/v3/files') {
      return _handleList(uri);
    }
    if (request.method == 'GET' &&
        segments.length == 4 &&
        segments.sublist(0, 3).join('/') == 'drive/v3/files') {
      return _handleDownload(segments[3]);
    }
    if (request.method == 'POST' && segments.join('/') == 'drive/v3/files') {
      return _handleCreate(request, metadataOnly: true);
    }
    if (request.method == 'POST' &&
        segments.join('/') == 'upload/drive/v3/files') {
      return _handleCreate(request, metadataOnly: false);
    }
    return http.Response('unhandled ${request.method} $uri', 404);
  }

  http.Response _handleList(Uri uri) {
    final query = uri.queryParameters['q'] ?? '';
    final matches = _files.values.where((f) => _matchesQuery(f, query)).toList();
    return _json({
      'files': [
        for (final f in matches) {'id': f.id, 'name': f.name},
      ],
    });
  }

  bool _matchesQuery(_FakeDriveFile f, String query) {
    // Query is built by GoogleDriveTransport as a conjunction of clauses -
    // just check each expected fragment is satisfied rather than writing a
    // real query parser.
    if (query.contains("mimeType='application/vnd.google-apps.folder'") &&
        f.mimeType != 'application/vnd.google-apps.folder') {
      return false;
    }
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
    return http.Response.bytes(
      file.bytes ?? Uint8List(0),
      200,
      headers: {'content-type': 'application/octet-stream'},
    );
  }

  http.Response _handleCreate(http.Request request, {required bool metadataOnly}) {
    final id = 'file-${_nextId++}';
    Map<String, dynamic> metadata;
    Uint8List? bytes;

    if (metadataOnly) {
      metadata = jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;
    } else {
      final contentType = request.headers['content-type']!;
      final boundary = RegExp('boundary="([^"]*)"').firstMatch(contentType)!.group(1)!;
      final (parsedMetadata, parsedBytes) = _parseMultipartRelated(
        request.bodyBytes,
        boundary,
      );
      metadata = parsedMetadata;
      bytes = parsedBytes;
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

  http.Response _json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  (Map<String, dynamic>, Uint8List) _parseMultipartRelated(
    Uint8List bodyBytes,
    String boundary,
  ) {
    final body = ascii.decode(bodyBytes);
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

void main() {
  test('upload() creates the app folder and a per-device subfolder lazily', () async {
    final drive = _FakeDrive();
    final transport = GoogleDriveTransport(authClient: drive.client);

    await transport.upload('node-a/1.json', Uint8List.fromList(utf8.encode('hello')));

    final folders = drive._files.values.where((f) => f.mimeType == 'application/vnd.google-apps.folder');
    expect(folders.map((f) => f.name), containsAll(['turtle-base-sync', 'node-a']));
  });

  test('list() returns names for every device folder under the app folder', () async {
    final drive = _FakeDrive();
    final transportA = GoogleDriveTransport(authClient: drive.client);
    final transportB = GoogleDriveTransport(authClient: drive.client);

    await transportA.upload('node-a/1.json', Uint8List.fromList([1]));
    await transportB.upload('node-b/1.json', Uint8List.fromList([2]));

    // A fresh transport instance (no locally cached folder ids) must still
    // discover both devices' folders/files by listing through Drive.
    final freshTransport = GoogleDriveTransport(authClient: drive.client);
    final names = await freshTransport.list();

    expect(names, containsAll(['node-a/1.json', 'node-b/1.json']));
  });

  test('upload() then download() round-trips the bytes', () async {
    final drive = _FakeDrive();
    final transport = GoogleDriveTransport(authClient: drive.client);
    final bytes = Uint8List.fromList(utf8.encode('{"spaces":[]}'));

    await transport.upload('node-a/1.json', bytes);
    await transport.list();
    final downloaded = await transport.download('node-a/1.json');

    expect(downloaded, bytes);
  });

  test('two uploads from the same device reuse the same device folder', () async {
    final drive = _FakeDrive();
    final transport = GoogleDriveTransport(authClient: drive.client);

    await transport.upload('node-a/1.json', Uint8List.fromList([1]));
    await transport.upload('node-a/2.json', Uint8List.fromList([2]));

    final deviceFolders = drive._files.values.where(
      (f) => f.mimeType == 'application/vnd.google-apps.folder' && f.name == 'node-a',
    );
    expect(deviceFolders, hasLength(1));
  });
}
