import {
  AtSign,
  BookOpen,
  Calendar,
  CircleChevronDown,
  CircleHelp,
  Hash,
  Link,
  ListChecks,
  MapPin,
  MoveUpRight,
  Paperclip,
  Phone,
  SquareCheck,
  Text,
} from 'lucide-react';

import type { AnyFieldType } from '../data/base-field-type.ts';

/** The icon of a field type, as in the type picker, the field editor and column headers. */
export function FieldTypeIcon({ base, variantId }: { base: AnyFieldType; variantId?: string | undefined }) {
  switch (variantId) {
    case 'url':
      return <Link />;
    case 'email':
      return <AtSign />;
    case 'phone':
      return <Phone />;
    case 'books.isbn':
      return <BookOpen />;
    default:
      break;
  }
  switch (base.kind) {
    case 'text':
      return <Text />;
    case 'number':
      return <Hash />;
    case 'date':
      return <Calendar />;
    case 'checkbox':
      return <SquareCheck />;
    case 'select':
      return <CircleChevronDown />;
    case 'multiSelect':
      return <ListChecks />;
    case 'relation':
      return <MoveUpRight />;
    case 'location':
      return <MapPin />;
    case 'files':
      return <Paperclip />;
    case 'unsupported':
      return <CircleHelp />;
  }
}
