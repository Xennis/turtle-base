// Flutter's own `Page` (Navigator 2.0) collides with our `Page` data class.
import 'package:flutter/material.dart' hide Page;
import 'package:turtle_base/core/app_scope.dart';
import 'package:turtle_base/core/database/app_database.dart';
import 'package:turtle_base/features/pages/data/pages_repository.dart';

/// The typed-fields area of a collection entry's Page-View, shown above
/// the rich-text body (see UI_UX.md). Not used for freestanding pages.
class PagePropertiesHeader extends StatefulWidget {
  const PagePropertiesHeader({
    super.key,
    required this.pageId,
    required this.collectionId,
  });

  final String pageId;
  final String collectionId;

  @override
  State<PagePropertiesHeader> createState() => _PagePropertiesHeaderState();
}

class _PagePropertiesHeaderState extends State<PagePropertiesHeader> {
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  // Created once per field id, like CollectionEditPage's field-name
  // controllers - pulling the value back down from the stream on every
  // rebuild would reset the cursor mid-edit.
  TextEditingController _controllerFor(Field field, Page page) {
    final existing = _controllers[field.id];
    if (existing != null) return existing;
    final value = decodePageProperties(page.properties)[field.id];
    final controller = TextEditingController(text: value?.toString() ?? '');
    _controllers[field.id] = controller;
    return controller;
  }

  FocusNode _focusNodeFor(Field field, AppScope scope) {
    final existing = _focusNodes[field.id];
    if (existing != null) return existing;
    final focusNode = FocusNode();
    focusNode.addListener(() {
      if (!focusNode.hasFocus) {
        scope.pages.setPropertyValue(
          widget.pageId,
          field.id,
          _controllers[field.id]!.text,
        );
      }
    });
    _focusNodes[field.id] = focusNode;
    return focusNode;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<Page>(
      stream: scope.pages.watchById(widget.pageId),
      builder: (context, pageSnapshot) {
        final page = pageSnapshot.data;
        if (page == null) return const SizedBox.shrink();
        return StreamBuilder<List<Field>>(
          stream: scope.fields.watchAllInCollection(widget.collectionId),
          builder: (context, fieldsSnapshot) {
            final fields = fieldsSnapshot.data ?? const <Field>[];
            _controllers.removeWhere((id, controller) {
              final stillExists = fields.any((f) => f.id == id);
              if (!stillExists) controller.dispose();
              return !stillExists;
            });
            _focusNodes.removeWhere((id, focusNode) {
              final stillExists = fields.any((f) => f.id == id);
              if (!stillExists) focusNode.dispose();
              return !stillExists;
            });
            if (fields.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            field.name,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controllerFor(field, page),
                            focusNode: _focusNodeFor(field, scope),
                            decoration: const InputDecoration(isDense: true),
                            onSubmitted: (value) =>
                                scope.pages.setPropertyValue(widget.pageId, field.id, value),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
