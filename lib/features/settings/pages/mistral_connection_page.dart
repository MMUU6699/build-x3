import 'package:flutter/material.dart';

import '../../../core/services/build_x_secure_store.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';

class MistralConnectionPage extends StatefulWidget {
  const MistralConnectionPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<MistralConnectionPage> createState() => _MistralConnectionPageState();
}

class _MistralConnectionPageState extends State<MistralConnectionPage> {
  final _keyController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _showKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final key = await BuildXSecureStore.readMistralKey();
      if (mounted) _keyController.text = key;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      await BuildXSecureStore.saveMistralKey(_keyController.text);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.buildXSaved)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.buildXSaveFailed)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final form = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  l10n.buildXConnectionTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            Text(l10n.buildXApiKeyHelp),
            const SizedBox(height: 24),
            TextField(
              controller: _keyController,
              enabled: !_loading && !_saving,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.buildXApiKeyLabel,
                hintText: l10n.buildXApiKeyHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  tooltip: _showKey ? l10n.buildXHideKey : l10n.buildXShowKey,
                  onPressed: () => setState(() => _showKey = !_showKey),
                  icon: Icon(
                    _showKey ? Lucide.EyeOff : Lucide.Eye,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _loading || _saving ? null : _save,
                child: Text(l10n.buildXSave),
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) return form;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.buildXConnectionTitle)),
      body: form,
    );
  }
}
