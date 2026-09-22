import 'package:flutter/material.dart';

import '../../../core/services/build_x_secure_store.dart';
import '../../../icons/lucide_adapter.dart';

/// Connection settings page for Build X (NVIDIA NIM & OpenHands).
class CerebrasConnectionPage extends StatefulWidget {
  const CerebrasConnectionPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<CerebrasConnectionPage> createState() => _CerebrasConnectionPageState();
}

class _CerebrasConnectionPageState extends State<CerebrasConnectionPage> {
  final _keyController = TextEditingController();
  final _urlController = TextEditingController();
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
      final key = await BuildXSecureStore.readNvidiaKey();
      final url = await BuildXSecureStore.readWorkBackendUrl();
      if (mounted) {
        _keyController.text = key;
        _urlController.text = url;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await BuildXSecureStore.saveNvidiaKey(_keyController.text);
      await BuildXSecureStore.saveWorkBackendUrl(_urlController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Build X connection settings saved.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save settings.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final form = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'Build X Connection (NVIDIA NIM)',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            Text(
              'Configure your NVIDIA API key (nvapi-...) to power autonomous Work mode and Chat mode with nvidia/nemotron-3-ultra-550b-a55b.',
              style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurfaceVariant),
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
                hintText: 'nvapi-...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  tooltip: _showKey ? 'Hide key' : 'Show key',
                  onPressed: () => setState(() => _showKey = !_showKey),
                  icon: Icon(
                    _showKey ? Lucide.EyeOff : Lucide.Eye,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _urlController,
              enabled: !_loading && !_saving,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'OpenHands Backend URL (Optional)',
                hintText: 'http://localhost:8000 or remote VM URL',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _loading || _saving ? null : _save,
                child: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) return form;
    return Scaffold(
      appBar: AppBar(title: const Text('Build X Connection (NVIDIA NIM)')),
      body: form,
    );
  }
}
