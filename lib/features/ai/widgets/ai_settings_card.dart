import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:turtle_base/features/ai/data/ai_key_storage.dart';
import 'package:turtle_base/features/ai/data/ai_provider.dart';
import 'package:turtle_base/features/ai/data/ai_test_client.dart';
import 'package:turtle_base/features/ai/widgets/ai_settings_scope.dart';
import 'package:turtle_base/features/settings/widgets/settings_row.dart';

/// AI section of the Settings page: per-provider API key management, a
/// default-model picker, and a throwaway test prompt to confirm a key
/// actually works. See AI_INTEGRATION.md / AI_SETTINGS_MVP.md.
class AiSettingsCard extends StatefulWidget {
  const AiSettingsCard({super.key});

  @override
  State<AiSettingsCard> createState() => _AiSettingsCardState();
}

class _AiSettingsCardState extends State<AiSettingsCard> {
  final _keyStorage = AiKeyStorage();

  bool _testing = false;
  String? _testResult;
  String? _testError;

  Future<void> _runTest() async {
    final model = AiSettingsScope.of(context).selectedModel;
    setState(() {
      _testing = true;
      _testResult = null;
      _testError = null;
    });

    final apiKey = await _keyStorage.read(model.provider);
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _testing = false;
        _testError = 'No API key set for ${model.provider.label}.';
      });
      return;
    }

    try {
      final result = await sendTestPrompt(model: model, apiKey: apiKey);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testResult = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiSettings = AiSettingsScope.of(context);
    final theme = ShadTheme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI', style: theme.textTheme.h4),
            const SizedBox(height: 12),
            for (final provider in AiProvider.values) _ApiKeyRow(provider: provider, keyStorage: _keyStorage),
            SettingsRow(
              label: 'Default model',
              control: ShadSelect<AiModel>(
                initialValue: aiSettings.selectedModel,
                selectedOptionBuilder: (context, value) => Text(value.label),
                options: [
                  for (final model in AiModel.values) ShadOption(value: model, child: Text(model.label)),
                ],
                onChanged: (model) {
                  if (model != null) aiSettings.setModel(model);
                },
              ),
            ),
            const SizedBox(height: 12),
            ShadButton(
              onPressed: _testing ? null : _runTest,
              // Kept short - ShadButton doesn't wrap its child text, and
              // the available width here is a lot narrower than the
              // Settings page's own Card padding on narrow screens.
              child: Text(_testing ? 'Sending...' : 'Send test prompt'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(_testResult!),
            ],
            if (_testError != null) ...[
              const SizedBox(height: 8),
              Text(_testError!, style: TextStyle(color: theme.colorScheme.destructive)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ApiKeyRow extends StatefulWidget {
  const _ApiKeyRow({required this.provider, required this.keyStorage});

  final AiProvider provider;
  final AiKeyStorage keyStorage;

  @override
  State<_ApiKeyRow> createState() => _ApiKeyRowState();
}

class _ApiKeyRowState extends State<_ApiKeyRow> {
  final _controller = TextEditingController();

  // null while the initial secure-storage read is still in flight.
  bool? _hasKey;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final key = await widget.keyStorage.read(widget.provider);
    if (!mounted) return;
    setState(() => _hasKey = key != null && key.isNotEmpty);
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    await widget.keyStorage.write(widget.provider, value);
    _controller.clear();
    if (!mounted) return;
    setState(() => _hasKey = true);
  }

  Future<void> _clear() async {
    await widget.keyStorage.delete(widget.provider);
    if (!mounted) return;
    setState(() => _hasKey = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Not a SettingsRow: input + two buttons need more width than a
    // label-left/control-right layout can spare on narrow screens, so
    // this gets its own full-width block instead.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.provider.label),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                // The key is never shown again once saved - only ever
                // entered/replaced, so this stays empty after a save.
                child: ShadInput(
                  controller: _controller,
                  obscureText: true,
                  placeholder: const Text('API key'),
                ),
              ),
              const SizedBox(width: 8),
              ShadButton(onPressed: _save, child: const Text('Save')),
              const SizedBox(width: 4),
              ShadButton.outline(onPressed: _clear, child: const Text('Clear')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _hasKey == null ? '...' : (_hasKey! ? 'Key saved' : 'No key set'),
            style: ShadTheme.of(context).textTheme.small,
          ),
        ],
      ),
    );
  }
}
