import type { OptionColor } from '@turtle-base/plugin-api';
import { cn } from 'cn';
import { X } from 'lucide-react';

import type { SelectOption } from '../data/select-field.ts';

/** Background and text per option color, light and dark - the Flutter app's palette, muted like Notion's. */
const colorClasses: Readonly<Record<OptionColor, string>> = {
  gray: 'bg-[#e9e8e4] text-[#55534e] dark:bg-[#3f3e3b] dark:text-[#cfccc6]',
  brown: 'bg-[#f0e4dc] text-[#6b4a36] dark:bg-[#4a3a30] dark:text-[#e0c2ae]',
  orange: 'bg-[#fbe6d4] text-[#8a4b14] dark:bg-[#553a22] dark:text-[#f2bf8c]',
  yellow: 'bg-[#f8eecb] text-[#7a5d0c] dark:bg-[#4f4422] dark:text-[#ebd48a]',
  green: 'bg-[#ddefe3] text-[#2b6b43] dark:bg-[#2a4434] dark:text-[#9dd3ae]',
  blue: 'bg-[#dcebf7] text-[#1f5f99] dark:bg-[#22384d] dark:text-[#9cc7ee]',
  purple: 'bg-[#ece3f5] text-[#5e3e8a] dark:bg-[#3d3150] dark:text-[#cdb6ec]',
  pink: 'bg-[#f6e1ec] text-[#8a3463] dark:bg-[#4d2c3e] dark:text-[#edb0cf]',
  red: 'bg-[#fbe0dd] text-[#9a2f25] dark:bg-[#542c28] dark:text-[#f2aaa2]',
};

/** The dot's color is the chip's text color. */
const dotClasses: Readonly<Record<OptionColor, string>> = {
  gray: 'bg-[#55534e] dark:bg-[#cfccc6]',
  brown: 'bg-[#6b4a36] dark:bg-[#e0c2ae]',
  orange: 'bg-[#8a4b14] dark:bg-[#f2bf8c]',
  yellow: 'bg-[#7a5d0c] dark:bg-[#ebd48a]',
  green: 'bg-[#2b6b43] dark:bg-[#9dd3ae]',
  blue: 'bg-[#1f5f99] dark:bg-[#9cc7ee]',
  purple: 'bg-[#5e3e8a] dark:bg-[#cdb6ec]',
  pink: 'bg-[#8a3463] dark:bg-[#edb0cf]',
  red: 'bg-[#9a2f25] dark:bg-[#f2aaa2]',
};

export function optionColorLabel(color: OptionColor): string {
  return color.charAt(0).toUpperCase() + color.slice(1);
}

/** A select option as a pill in its color - with `onRemove`, a small × to take it off. */
export function SelectOptionChip({ option, onRemove }: { option: SelectOption; onRemove?: () => void }) {
  return (
    <span
      className={cn(
        'inline-flex max-w-full items-center gap-0.5 rounded-full px-2 py-0.5 text-xs font-medium',
        colorClasses[option.color],
      )}
    >
      <span className="truncate">{option.name}</span>
      {onRemove !== undefined && (
        <button
          type="button"
          aria-label={`Remove ${option.name}`}
          onClick={onRemove}
          className="-mr-1 rounded-full p-0.5"
        >
          <X className="size-3" />
        </button>
      )}
    </span>
  );
}

export function OptionColorDot({ color, className }: { color: OptionColor; className?: string }) {
  return <span className={cn('inline-block size-3.5 rounded-full', dotClasses[color], className)} />;
}
