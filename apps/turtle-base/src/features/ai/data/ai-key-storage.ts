import type { SecretStorage } from '@turtle-base/platform';

import type { AiProvider } from './ai-model.ts';

/**
 * The API key per provider, in the platform's secret storage - never in the
 * database, whose changes are uploaded to Drive by the sync. Keys stay on
 * this device.
 */
export class AiKeyStorage {
  readonly #secrets: SecretStorage;

  constructor(secrets: SecretStorage) {
    this.#secrets = secrets;
  }

  read(provider: AiProvider): Promise<string | undefined> {
    return this.#secrets.get(keyOf(provider));
  }

  write(provider: AiProvider, apiKey: string): Promise<void> {
    return this.#secrets.set(keyOf(provider), apiKey);
  }

  remove(provider: AiProvider): Promise<void> {
    return this.#secrets.remove(keyOf(provider));
  }
}

function keyOf(provider: AiProvider): string {
  return `ai_api_key_${provider}`;
}
