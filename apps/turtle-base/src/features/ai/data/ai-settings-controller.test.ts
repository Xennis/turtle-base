import { MemoryKeyValueStore, MemorySecretStorage } from '@turtle-base/platform/testing';
import { describe, expect, test } from 'vite-plus/test';

import { AiKeyStorage } from './ai-key-storage.ts';
import { aiModels } from './ai-model.ts';
import { AiSettingsController } from './ai-settings-controller.ts';

describe('AiSettingsController', () => {
  test('defaults to the first model and remembers the one picked', async () => {
    const prefs = new MemoryKeyValueStore();
    const [first, second] = aiModels;
    if (second === undefined) throw new Error('Needs two models');
    const controller = new AiSettingsController(prefs);
    expect(controller.model).toBe(first);

    await controller.setModel(second);

    expect(new AiSettingsController(prefs).model).toBe(second);
  });

  test('falls back to the first model for one that is gone', () => {
    const prefs = new MemoryKeyValueStore();
    void prefs.set('ai_default_model', 'retired');

    expect(new AiSettingsController(prefs).model).toBe(aiModels[0]);
  });
});

describe('AiKeyStorage', () => {
  test('keeps a key per provider', async () => {
    const keys = new AiKeyStorage(new MemorySecretStorage());
    await keys.write('anthropic', 'sk-ant');

    expect(await keys.read('anthropic')).toBe('sk-ant');
    expect(await keys.read('google')).toBeUndefined();
    await keys.remove('anthropic');
    expect(await keys.read('anthropic')).toBeUndefined();
  });
});
