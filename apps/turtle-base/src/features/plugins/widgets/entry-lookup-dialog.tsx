import { LookupError, type EntryDraft, type EntryLookup } from '@turtle-base/plugin-api';
import { BookOpen, Pencil, Search } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { Button } from '../../../core/ui/button.tsx';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '../../../core/ui/dialog.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { EntryDraftWriter } from '../data/entry-draft-writer.ts';

/** How long typing pauses before a search goes out - the source is a remote service. */
const debounceMs = 400;

type SearchState =
  | { readonly kind: 'idle' }
  | { readonly kind: 'searching' }
  | { readonly kind: 'found'; readonly results: readonly EntryDraft[] }
  | { readonly kind: 'failed'; readonly message: string };

/**
 * Searches a plugin's external source (e.g. Open Library) and adds the picked
 * result as an entry - or opens the entry it's already in. Its files (e.g. a
 * cover) are downloaded in the background, the entry is usable right away.
 */
export function EntryLookupDialog(props: {
  collectionId: string;
  lookup: EntryLookup;
  onOpenChange: (open: boolean) => void;
  onOpenEntry: (pageId: string) => void;
}) {
  const { platform, database, fieldTypes, files } = useAppServices();
  const writer = useMemo(
    () => new EntryDraftWriter(database, { fieldTypes, files, fetch: platform.fetch }),
    [database, fieldTypes, files, platform],
  );
  const [query, setQuery] = useState('');
  const [search, setSearch] = useState<SearchState>({ kind: 'idle' });
  const [adding, setAdding] = useState(false);
  const trimmed = query.trim();
  const { lookup } = props;

  useEffect(() => {
    if (trimmed.length === 0) return;
    let current = true;
    const timer = setTimeout(() => {
      setSearch({ kind: 'searching' });
      lookup.search(trimmed, { fetch: platform.fetch }).then(
        (results) => current && setSearch({ kind: 'found', results }),
        (error: unknown) =>
          current &&
          setSearch({ kind: 'failed', message: error instanceof LookupError ? error.message : String(error) }),
      );
    }, debounceMs);
    return () => {
      // A newer query is typed - this one's answer must not overwrite its results.
      current = false;
      clearTimeout(timer);
    };
  }, [trimmed, lookup, platform]);

  async function add(draft: EntryDraft) {
    setAdding(true);
    try {
      const existing = await writer.findExisting(props.collectionId, draft, lookup.uniqueFieldKey);
      const pageId = existing ?? (await writer.create(props.collectionId, draft));
      if (existing === undefined) void writer.attachFiles(props.collectionId, pageId, draft);
      props.onOpenChange(false);
      props.onOpenEntry(pageId);
    } finally {
      setAdding(false);
    }
  }

  return (
    <Dialog open onOpenChange={props.onOpenChange}>
      <DialogContent fullScreenWhenNarrow className="flex max-h-[85vh] flex-col sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{lookup.actionLabel}</DialogTitle>
        </DialogHeader>
        <div className="relative">
          <Search className="pointer-events-none absolute top-2 left-2.5 size-4 text-muted-foreground" />
          <Input
            autoFocus
            aria-label="Search"
            className="pl-8"
            placeholder={lookup.searchHint}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
          />
        </div>
        <div className="min-h-48 flex-1 overflow-auto">
          {/* At the list's top, not in a footer - that would lie behind the keyboard while typing. */}
          {trimmed.length > 0 && (
            <Button
              variant="ghost"
              className="w-full justify-start"
              disabled={adding}
              onClick={() => void add({ title: trimmed })}
            >
              <Pencil />
              <span className="truncate">Add "{trimmed}" manually</span>
            </Button>
          )}
          <Results
            state={trimmed.length === 0 ? { kind: 'idle' } : search}
            disabled={adding}
            onPick={(draft) => void add(draft)}
          />
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Results(props: { state: SearchState; disabled: boolean; onPick: (draft: EntryDraft) => void }) {
  const { state } = props;
  switch (state.kind) {
    case 'idle':
      return null;
    case 'searching':
      return <p className="py-8 text-center text-sm text-muted-foreground">Searching…</p>;
    case 'failed':
      return <p className="py-8 text-center text-sm text-destructive">{state.message}</p>;
    case 'found':
      if (state.results.length === 0)
        return <p className="py-8 text-center text-sm text-muted-foreground">Nothing found</p>;
      return (
        <ul className="grid gap-0.5">
          {state.results.map((draft, index) => (
            // Results have no id; their order is the source's.
            // oxlint-disable-next-line react/no-array-index-key
            <li key={index}>
              <button
                type="button"
                disabled={props.disabled}
                onClick={() => props.onPick(draft)}
                className="flex w-full items-center gap-3 rounded-md p-1.5 text-left hover:bg-muted disabled:opacity-50"
              >
                <span className="flex h-14 w-10 shrink-0 items-center justify-center overflow-hidden rounded bg-muted">
                  {draft.thumbnail === undefined ? (
                    <BookOpen className="size-4 text-muted-foreground" />
                  ) : (
                    <img alt="" src={draft.thumbnail} className="size-full object-cover" />
                  )}
                </span>
                <span className="min-w-0">
                  <span className="line-clamp-2 text-sm">{draft.title}</span>
                  {draft.subtitle !== undefined && draft.subtitle.length > 0 && (
                    <span className="block truncate text-xs text-muted-foreground">{draft.subtitle}</span>
                  )}
                </span>
              </button>
            </li>
          ))}
        </ul>
      );
  }
}
