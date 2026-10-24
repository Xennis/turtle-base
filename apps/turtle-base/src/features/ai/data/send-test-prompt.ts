import { createAnthropic } from '@ai-sdk/anthropic';
import { createGoogle } from '@ai-sdk/google';
import { generateText, type LanguageModel } from 'ai';

import type { AiModel } from './ai-model.ts';

interface TestPromptOptions {
  readonly model: AiModel;
  readonly apiKey: string;
  readonly fetch: typeof globalThis.fetch;
}

/**
 * Sends one throwaway prompt, to check that a stored API key works end to
 * end - not how the chat will talk to the model (no history, no tools).
 * `fetch` is the platform's, which isn't bound by the web view's CORS.
 */
export async function sendTestPrompt(options: TestPromptOptions): Promise<string> {
  const { text } = await generateText({ model: languageModelOf(options), prompt: "What's up?" });
  return text;
}

function languageModelOf({ model, apiKey, fetch }: TestPromptOptions): LanguageModel {
  switch (model.provider) {
    case 'anthropic':
      return createAnthropic({ apiKey, fetch })(model.id);
    case 'google':
      return createGoogle({ apiKey, fetch })(model.id);
  }
}
