import 'package:books/src/isbn.dart';
import 'package:books/src/reading_list.dart';
import 'package:turtle_plugin/turtle_plugin.dart';

final booksPlugin = TurtlePlugin(
  id: 'books',
  name: 'Books',
  description: 'Track the books you want to read, are reading and have read.',
  icon: '📚',
  variants: [isbnVariant],
  collections: [readingList],
);
