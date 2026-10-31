import { validatePlugin } from '@turtle-base/plugin-catalog';
import { expect, test } from 'vite-plus/test';

import { booksPlugin } from './books-plugin.ts';

test('is a plugin the app accepts', () => {
  expect(validatePlugin(booksPlugin)).toBe(booksPlugin);
});
