import 'package:crdt_file_sync_transport/crdt_file_sync_transport.dart';

/// In-memory [FileTransport] for tests - no network, no disk.
class FakeFileTransport implements FileTransport {
  final Map<String, List<int>> files = {};

  /// Names whose upload or download throws, to simulate failures.
  final Set<String> failing = {};

  @override
  Future<void> upload(String name, Stream<List<int>> bytes, int length) async {
    final content = await bytes.expand((chunk) => chunk).toList();
    if (failing.contains(name)) throw StateError('FakeFileTransport: upload of "$name" failed');
    files[name] = content;
  }

  @override
  Future<Set<String>> list() async => files.keys.toSet();

  @override
  Stream<List<int>> download(String name) async* {
    final content = files[name];
    if (content == null || failing.contains(name)) {
      throw StateError('FakeFileTransport: no file named "$name"');
    }
    yield content;
  }
}
