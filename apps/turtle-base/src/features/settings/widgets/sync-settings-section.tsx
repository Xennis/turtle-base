import { useId, useState } from 'react';
import { toast } from 'sonner';

import { useAppServices } from '../../../core/app-scope.tsx';
import type { AppSyncController } from '../../../core/sync/app-sync-controller.ts';
import { Button } from '../../../core/ui/button.tsx';
import { Label } from '../../../core/ui/label.tsx';
import { Switch } from '../../../core/ui/switch.tsx';
import { useNotifier } from '../../../core/use-notifier.ts';

/**
 * Google Drive sync: connect, its status, and syncing now. Nothing at all
 * where sign-in isn't configured - it could never connect.
 */
export function SyncSettingsSection() {
  const { sync } = useAppServices();
  const id = useId();
  const isConnected = useNotifier(sync, () => sync.isConnected);
  const status = useNotifier(sync, () => sync.status);
  const keepAllFilesOffline = useNotifier(sync, () => sync.keepAllFilesOffline);
  const label = useNotifier(sync, () => statusLabel(sync));
  const [connecting, setConnecting] = useState(false);

  if (!sync.isAvailable) return null;

  async function connect() {
    setConnecting(true);
    try {
      await sync.connect();
    } catch (error) {
      toast.error(`Couldn't connect to Google Drive: ${messageOf(error)}`);
    } finally {
      setConnecting(false);
    }
  }

  return (
    <section className="grid gap-6">
      <h2 className="text-sm font-medium text-muted-foreground">Sync</h2>
      <div className="flex items-center justify-between gap-4">
        <div className="grid gap-1">
          <Label>Google Drive</Label>
          <p role="status" className="text-sm text-muted-foreground">
            {connecting ? 'Waiting for the sign-in in your browser…' : label}
          </p>
        </div>
        {isConnected ? (
          <Button variant="outline" onClick={() => void sync.disconnect()}>
            Disconnect
          </Button>
        ) : (
          <Button disabled={connecting} onClick={() => void connect()}>
            Connect
          </Button>
        )}
      </div>
      <div className="flex items-center justify-between gap-4">
        <div className="grid gap-1">
          <Label htmlFor={`${id}-offline`}>Keep all files offline</Label>
          <p className="text-sm text-muted-foreground">
            Download every file when syncing, not only when it's opened. Only on this device.
          </p>
        </div>
        <Switch
          id={`${id}-offline`}
          checked={keepAllFilesOffline}
          onCheckedChange={(checked) => void sync.setKeepAllFilesOffline(checked)}
        />
      </div>
      <div>
        <Button variant="outline" disabled={!isConnected || status === 'syncing'} onClick={() => void sync.syncNow()}>
          Sync now
        </Button>
      </div>
    </section>
  );
}

function statusLabel(sync: AppSyncController): string {
  if (!sync.isConnected) return 'Not connected';
  switch (sync.status) {
    case 'syncing':
      return 'Syncing…';
    case 'error':
      return `Error: ${messageOf(sync.lastError)}`;
    case 'idle': {
      const at = sync.lastSyncedAt;
      if (at === undefined) return 'Connected';
      const failed = sync.failedFileCount;
      const synced = `Last synced ${at.toLocaleString()}`;
      if (failed === 0) return synced;
      return `${synced} - ${failed === 1 ? '1 file' : `${failed} files`} failed, retried next time`;
    }
  }
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
