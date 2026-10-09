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
      final key = await BuildXSecureStore.readCustomUserKey();
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
      await BuildXSecureStore.saveNvidiaKey(_keyController.text);
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
    final pageTitle = l10n.buildXConnectionTitle;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final desc = isAr
        ? 'أدخل مفتاح NVIDIA API الخاص بك (nvapi-...). يعمل هذا المفتاح على تشغيل المحادثة عبر z-ai/glm-5.3، وتحليل ورؤية الصور، والمهام عبر NVIDIA NIM.'
        : 'Enter your NVIDIA API Key (nvapi-...). This powers Chat and Work modes via z-ai/glm-5.3, multimodal vision analysis, and reasoning on NVIDIA NIM.';

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
                  pageTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            Text(
              desc,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _keyController,
              enabled: !_loading && !_saving,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'NVIDIA API Key',
                hintText: isAr
                    ? 'المفتاح المدمج نشط تلقائياً (أو أدخل nvapi-...)'
                    : 'System key is active (or enter nvapi-...)',
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
      appBar: AppBar(title: Text(pageTitle)),
      body: form,
    );
  }
}
