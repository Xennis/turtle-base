import type { KeyValueStore } from '@turtle-base/platform';

import { Notifier } from '../../../core/notifier.ts';
import { aiModels, type AiModel } from './ai-model.ts';

const modelKey = 'ai_default_model';

/** The default AI model, per device in the prefs - like the theme, a choice for this device, not synced content. */
export class AiSettingsController extends Notifier {
  readonly #prefs: KeyValueStore;
  #model: AiModel;

  constructor(prefs: KeyValueStore) {
    super();
    this.#prefs = prefs;
    const stored = prefs.get(modelKey);
    this.#model = aiModels.find((model) => model.key === stored) ?? aiModels[0];
  }

  get model(): AiModel {
    return this.#model;
  }

  async setModel(model: AiModel): Promise<void> {
    if (model.key === this.#model.key) return;
    this.#model = model;
    this.notify();
    await this.#prefs.set(modelKey, model.key);
  }
}
