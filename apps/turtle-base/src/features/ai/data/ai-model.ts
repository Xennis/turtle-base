/** A provider the user brings their own API key for - no backend of ours in between. */
export type AiProvider = 'google' | 'anthropic';

export const aiProviders: readonly AiProvider[] = ['google', 'anthropic'];

export const aiProviderLabels: Readonly<Record<AiProvider, string>> = {
  google: 'Google (Gemini)',
  anthropic: 'Anthropic (Claude)',
};

export interface AiModel {
  /** What the prefs store - the same names as the Flutter app's `AiModel` enum. */
  readonly key: string;
  readonly provider: AiProvider;
  /** The provider's model id. */
  readonly id: string;
  readonly label: string;
}

/** For now one model per provider, picked from a single list. */
export const aiModels: readonly [AiModel, ...AiModel[]] = [
  { key: 'geminiFlash', provider: 'google', id: 'gemini-3.5-flash', label: 'Gemini 3.5 Flash' },
  { key: 'claudeSonnet', provider: 'anthropic', id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5' },
];
