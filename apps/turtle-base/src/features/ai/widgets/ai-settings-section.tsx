import { Lock } from 'lucide-react';
import { useEffect, useId, useState } from 'react';

import { useAppServices } from '../../../core/app-scope.tsx';
import { Button } from '../../../core/ui/button.tsx';
import { Input } from '../../../core/ui/input.tsx';
import { Label } from '../../../core/ui/label.tsx';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../../../core/ui/select.tsx';
import { useNotifier } from '../../../core/use-notifier.ts';
import { aiModels, aiProviderLabels, aiProviders, type AiProvider } from '../data/ai-model.ts';
import { sendTestPrompt } from '../data/send-test-prompt.ts';

type TestState =
  | { readonly kind: 'idle' }
  | { readonly kind: 'sending' }
  | { readonly kind: 'answered'; readonly text: string }
  | { readonly kind: 'failed'; readonly message: string };

/** The API key per provider, the default model, and a test prompt to check that a key works. */
export function AiSettingsSection() {
  const { aiSettings, aiKeys, platform } = useAppServices();
  const id = useId();
  const model = useNotifier(aiSettings, () => aiSettings.model);
  const [test, setTest] = useState<TestState>({ kind: 'idle' });

  async function runTest() {
    setTest({ kind: 'sending' });
    const apiKey = await aiKeys.read(model.provider);
    if (apiKey === undefined) {
      setTest({ kind: 'failed', message: `No API key set for ${aiProviderLabels[model.provider]}.` });
      return;
    }
    try {
      setTest({ kind: 'answered', text: await sendTestPrompt({ model, apiKey, fetch: platform.fetch }) });
    } catch (error) {
      setTest({ kind: 'failed', message: error instanceof Error ? error.message : String(error) });
    }
  }

  return (
    <section className="grid gap-6">
      <div className="grid gap-1">
        <h2 className="text-sm font-medium text-muted-foreground">AI</h2>
        <p className="flex items-center gap-1.5 text-sm text-muted-foreground">
          <Lock className="size-3.5 shrink-0" />
          API keys stay on this device - never synced, only sent to their provider.
        </p>
      </div>
      {aiProviders.map((provider) => (
        <ApiKeyRow key={provider} provider={provider} />
      ))}
      <div className="grid gap-2">
        <Label htmlFor={`${id}-model`}>Default model</Label>
        <Select
          value={model.key}
          onValueChange={(key) => {
            const picked = aiModels.find((m) => m.key === key);
            if (picked !== undefined) void aiSettings.setModel(picked);
          }}
        >
          <SelectTrigger id={`${id}-model`} className="w-60">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {aiModels.map((m) => (
              <SelectItem key={m.key} value={m.key}>
                {m.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div className="grid justify-items-start gap-2">
        <Button variant="outline" disabled={test.kind === 'sending'} onClick={() => void runTest()}>
          {test.kind === 'sending' ? 'Sending…' : 'Send test prompt'}
        </Button>
        <div aria-live="polite" className="text-sm">
          {test.kind === 'answered' && <p className="whitespace-pre-wrap">{test.text}</p>}
          {test.kind === 'failed' && <p className="text-destructive">{test.message}</p>}
        </div>
      </div>
    </section>
  );
}

/** A key is only ever entered or replaced - once saved, it isn't shown again. */
function ApiKeyRow({ provider }: { provider: AiProvider }) {
  const { aiKeys } = useAppServices();
  const id = useId();
  const [value, setValue] = useState('');
  // Undefined while the secret storage is still being read.
  const [hasKey, setHasKey] = useState<boolean | undefined>();
  const label = aiProviderLabels[provider];

  useEffect(() => {
    let current = true;
    void aiKeys.read(provider).then((key) => current && setHasKey(key !== undefined && key.length > 0));
    return () => {
      current = false;
    };
  }, [aiKeys, provider]);

  async function save() {
    const trimmed = value.trim();
    if (trimmed.length === 0) return;
    await aiKeys.write(provider, trimmed);
    setValue('');
    setHasKey(true);
  }

  async function clear() {
    await aiKeys.remove(provider);
    setHasKey(false);
  }

  return (
    <div className="grid gap-2">
      <Label htmlFor={`${id}-key`}>{label}</Label>
      <form
        className="flex gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          void save();
        }}
      >
        <Input
          id={`${id}-key`}
          type="password"
          autoComplete="off"
          placeholder={hasKey === true ? 'Replace the saved key' : 'API key'}
          value={value}
          onChange={(event) => setValue(event.target.value)}
        />
        <Button type="submit" disabled={value.trim().length === 0}>
          Save
        </Button>
        {hasKey === true && (
          <Button type="button" variant="outline" onClick={() => void clear()}>
            Clear
          </Button>
        )}
      </form>
      <p className="text-sm text-muted-foreground">
        {hasKey === undefined ? '…' : hasKey ? 'Key saved' : 'No key set'}
      </p>
    </div>
  );
}
