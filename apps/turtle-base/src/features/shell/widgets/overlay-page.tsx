import { X } from 'lucide-react';
import type { ReactNode } from 'react';

import { Button } from '../../../core/ui/button.tsx';

/** A page shown on top of the selection (Settings, Plugins), with a way back to it. */
export function OverlayPage(props: { title: string; onDone: () => void; children: ReactNode }) {
  return (
    <div className="mx-auto w-full max-w-2xl px-6 py-8">
      <header className="mb-8 flex items-center justify-between">
        <h1 className="text-2xl font-semibold">{props.title}</h1>
        <Button variant="ghost" size="icon" aria-label="Close" onClick={props.onDone}>
          <X />
        </Button>
      </header>
      {props.children}
    </div>
  );
}
