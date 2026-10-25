import type { FlutterAppData } from '@turtle-base/platform';
import { useEffect, useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { Button } from '../../../core/ui/button.tsx';
import { importFlutterData, type ImportSummary } from '../data/flutter-import.ts';

type ImportState =
  | { readonly kind: 'idle' }
  | { readonly kind: 'importing' }
  | { readonly kind: 'done'; readonly summary: ImportSummary }
  | { readonly kind: 'failed'; readonly message: string };

/**
 * Takes over the Flutter app's data, where it was used on this device - only
 * offered then. Running it again only adds what's new there.
 */
export function FlutterImportSection() {
  const { platform, database, files } = useAppServices();
  const [source, setSource] = useState<FlutterAppData | undefined>();
  const [state, setState] = useState<ImportState>({ kind: 'idle' });

  useEffect(() => {
    let current = true;
    void platform.findFlutterAppData().then((found) => current && setSource(found));
    return () => {
      current = false;
    };
  }, [platform]);

  if (source === undefined) return null;

  async function runImport(from: FlutterAppData) {
    setState({ kind: 'importing' });
    try {
      setState({ kind: 'done', summary: await importFlutterData({ source: from, database, files }) });
    } catch (error) {
      setState({ kind: 'failed', message: error instanceof Error ? error.message : String(error) });
    }
  }

  return (
    <section className="grid gap-6">
      <h2 className="text-sm font-medium text-muted-foreground">Flutter app</h2>
      <div className="grid justify-items-start gap-2">
        <p className="text-sm text-muted-foreground">
          The previous app's data was found on this device. Importing copies its spaces, pages and files here and syncs
          them like new ones - the previous app's data stays as it is.
        </p>
        <p className="text-xs break-all text-muted-foreground">{source.location}</p>
        <Button variant="outline" disabled={state.kind === 'importing'} onClick={() => void runImport(source)}>
          {state.kind === 'importing' ? 'Importing…' : 'Import from the Flutter app'}
        </Button>
        <div aria-live="polite" className="text-sm">
          {state.kind === 'done' && <p>{summaryText(state.summary)}</p>}
          {state.kind === 'failed' && <p className="text-destructive">Import failed: {state.message}</p>}
        </div>
      </div>
    </section>
  );
}

function summaryText({ imported, files, failedFiles }: ImportSummary): string {
  const counts = [
    [imported.spaces, 'space', 'spaces'],
    [imported.collections, 'collection', 'collections'],
    [imported.pages, 'page', 'pages'],
    [files, 'file', 'files'],
  ] as const;
  const parts = counts
    .filter(([count]) => count > 0)
    .map(([count, one, many]) => `${count} ${count === 1 ? one : many}`);
  const text = parts.length === 0 ? 'Nothing new to import.' : `Imported ${parts.join(', ')}.`;
  return failedFiles === 0 ? text : `${text} ${failedFiles} file(s) could not be read.`;
}
