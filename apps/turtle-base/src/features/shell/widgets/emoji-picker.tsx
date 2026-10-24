import emojiDataUrl from '@emoji-mart/data/sets/15/native.json?url';
import { cn } from 'cn';
import { SmilePlus } from 'lucide-react';
import { Suspense, use, useState } from 'react';
import * as v from 'valibot';

import { Button } from '../../../core/ui/button.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { Popover, PopoverContent, PopoverTrigger } from '../../../core/ui/popover.tsx';

const emojiDataSchema = v.object({
  categories: v.array(v.object({ id: v.string(), emojis: v.array(v.string()) })),
  emojis: v.record(
    v.string(),
    v.object({
      name: v.string(),
      keywords: v.array(v.string()),
      skins: v.array(v.object({ native: v.string() })),
    }),
  ),
});

interface EmojiEntry {
  readonly native: string;
  readonly name: string;
  /** Name and keywords, lowercased, for the search. */
  readonly terms: string;
}

interface EmojiCategory {
  readonly id: string;
  readonly emojis: readonly EmojiEntry[];
}

const categoryLabels: Readonly<Record<string, string>> = {
  people: 'Smileys & people',
  nature: 'Animals & nature',
  foods: 'Food & drink',
  activity: 'Activity',
  places: 'Travel & places',
  objects: 'Objects',
  symbols: 'Symbols',
  flags: 'Flags',
};

let loading: Promise<readonly EmojiCategory[]> | undefined;

/** emoji-mart's data, bundled with the app - loaded on the first open, since it's a few hundred KB. */
function loadEmojis(): Promise<readonly EmojiCategory[]> {
  loading ??= (async () => {
    const data = v.parse(emojiDataSchema, await (await fetch(emojiDataUrl)).json());
    return data.categories.map((category) => ({
      id: category.id,
      emojis: category.emojis.flatMap((id) => {
        const emoji = data.emojis[id];
        const native = emoji?.skins[0]?.native;
        if (emoji === undefined || native === undefined) return [];
        return [{ native, name: emoji.name, terms: [id, emoji.name, ...emoji.keywords].join(' ').toLowerCase() }];
      }),
    }));
  })();
  return loading;
}

/**
 * An icon (an emoji) as a button that opens a picker to change or remove it -
 * for pages and collections. Without an icon it shows a muted symbol, since
 * an emoji placeholder would look like a set icon.
 */
export function EmojiIconButton(props: {
  value: string | null;
  label: string;
  onChange: (value: string | null) => void;
  className?: string;
}) {
  const [open, setOpen] = useState(false);

  function pick(value: string | null) {
    setOpen(false);
    if (value !== props.value) props.onChange(value);
  }

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          aria-label={props.label}
          className={cn('size-12 text-3xl', props.className)}
        >
          {props.value ?? <SmilePlus className="size-5 text-muted-foreground" />}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="start" className="w-80 p-2">
        <Suspense fallback={<p className="p-4 text-center text-muted-foreground">Loading…</p>}>
          <EmojiPicker onPick={pick} canRemove={props.value !== null} />
        </Suspense>
      </PopoverContent>
    </Popover>
  );
}

function EmojiPicker(props: { onPick: (value: string | null) => void; canRemove: boolean }) {
  const categories = use(loadEmojis());
  const [query, setQuery] = useState('');
  const terms = query.trim().toLowerCase();
  const shown =
    terms.length === 0
      ? categories
      : [{ id: 'results', emojis: categories.flatMap((c) => c.emojis).filter((e) => e.terms.includes(terms)) }];

  return (
    <div className="flex flex-col gap-2">
      <div className="flex gap-2">
        <Input
          aria-label="Search emoji"
          placeholder="Search"
          autoFocus
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
        {props.canRemove && (
          <Button variant="outline" onClick={() => props.onPick(null)}>
            Remove
          </Button>
        )}
      </div>
      <div className="h-72 overflow-y-auto">
        {shown.map((category) => (
          // Off-screen categories skip layout and paint - there are close to 2000 emoji.
          <section key={category.id} className="[content-visibility:auto]">
            {terms.length === 0 && (
              <h3 className="px-1 pt-2 pb-1 text-xs font-medium text-muted-foreground">
                {categoryLabels[category.id] ?? category.id}
              </h3>
            )}
            <div className="grid grid-cols-8">
              {category.emojis.map((emoji) => (
                <button
                  key={emoji.native}
                  type="button"
                  title={emoji.name}
                  aria-label={emoji.name}
                  onClick={() => props.onPick(emoji.native)}
                  className="flex aspect-square items-center justify-center rounded text-2xl hover:bg-muted focus-visible:bg-muted focus-visible:outline-none"
                >
                  {emoji.native}
                </button>
              ))}
            </div>
          </section>
        ))}
        {shown.every((category) => category.emojis.length === 0) && (
          <p className="p-4 text-center text-muted-foreground">No emoji found</p>
        )}
      </div>
    </div>
  );
}
