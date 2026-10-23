/// An AI provider the user can bring their own API key for (BYOK) - no
/// backend/proxy of ours is involved, see AI_INTEGRATION.md.
enum AiProvider { google, anthropic }

extension AiProviderLabel on AiProvider {
  String get label => switch (this) {
    AiProvider.google => 'Google (Gemini)',
    AiProvider.anthropic => 'Anthropic (Claude)',
  };
}

/// v1: exactly one hardcoded model per provider, picked from a single
/// dropdown that spans both providers (no per-provider model choice yet).
enum AiModel {
  geminiFlash(provider: AiProvider.google, id: 'gemini-3.5-flash', label: 'Gemini 3.5 Flash'),
  claudeSonnet(provider: AiProvider.anthropic, id: 'claude-sonnet-5', label: 'Claude Sonnet 5');

  const AiModel({required this.provider, required this.id, required this.label});

  final AiProvider provider;

  /// The model id passed to dartantic_ai's `Agent.forProvider(chatModelName: ...)`.
  final String id;
  final String label;
}
