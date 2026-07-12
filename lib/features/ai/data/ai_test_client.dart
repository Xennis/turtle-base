import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:turtle_base/features/ai/data/ai_provider.dart';

/// Sends a single, throwaway prompt to the given model - just to smoke-test
/// that a stored API key actually works end to end. Not the shape the real
/// chat feature will use (no history, no tools).
Future<String> sendTestPrompt({required AiModel model, required String apiKey}) async {
  // Built per-branch rather than assigning a shared `provider` variable
  // first - GoogleProvider/AnthropicProvider have different generic
  // ChatModelOptions, which don't unify to a single Provider<...> type.
  final agent = switch (model.provider) {
    AiProvider.google => Agent.forProvider(GoogleProvider(apiKey: apiKey), chatModelName: model.id),
    AiProvider.anthropic => Agent.forProvider(AnthropicProvider(apiKey: apiKey), chatModelName: model.id),
  };
  final result = await agent.send("What's up?");
  return result.output;
}
