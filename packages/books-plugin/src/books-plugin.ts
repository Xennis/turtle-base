import type { TurtlePlugin } from '@turtle-base/plugin-api';

import { isbnVariant } from './isbn.ts';
import { readingList } from './reading-list.ts';

export const booksPlugin: TurtlePlugin = {
  id: 'books',
  name: 'Books',
  description: 'Track the books you want to read, are reading and have read.',
  icon: '📚',
  variants: [isbnVariant],
  collections: [readingList],
};
