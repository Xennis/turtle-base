import { textVariant, type TurtlePlugin } from '@turtle-base/plugin-api';

export const demoCodeVariant = textVariant({ id: 'demo.code', label: 'Code', normalize: (v) => v.toUpperCase() });

/** A plugin with one field of each template kind, shared by the plugin tests. */
export const demoPlugin: TurtlePlugin = {
  id: 'demo',
  name: 'Demo',
  description: '',
  icon: '🧪',
  variants: [demoCodeVariant],
  collections: [
    {
      key: 'items',
      name: 'Items',
      icon: '📦',
      titleLabel: 'Item',
      fields: [
        {
          kind: 'select',
          key: 'status',
          name: 'Status',
          options: [
            { key: 'open', name: 'Open', color: 'gray' },
            { key: 'done', name: 'Done', color: 'green' },
          ],
        },
        { kind: 'text', key: 'code', name: 'Code', variant: demoCodeVariant },
        { kind: 'number', key: 'rating', name: 'Rating', min: 1, max: 5 },
        { kind: 'date', key: 'due', name: 'Due' },
        { kind: 'files', key: 'cover', name: 'Cover', accept: ['image/*'], maxFiles: 1 },
      ],
    },
  ],
};
