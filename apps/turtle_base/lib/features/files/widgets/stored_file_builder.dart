import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:turtle_base/core/app_scope.dart';

/// Rebuilds [builder] whenever one of [names] lands in the FileStore,
/// e.g. once sync has downloaded it - widgets read the files from the
/// store themselves, this only tells them when to look again.
class StoredFileBuilder extends StatefulWidget {
  const StoredFileBuilder({super.key, required this.names, required this.builder});

  final List<String> names;
  final WidgetBuilder builder;

  @override
  State<StoredFileBuilder> createState() => _StoredFileBuilderState();
}

class _StoredFileBuilderState extends State<StoredFileBuilder> {
  StreamSubscription<String>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscription?.cancel();
    _subscription = AppScope.of(context).files.onStored.listen((name) {
      if (mounted && widget.names.contains(name)) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
