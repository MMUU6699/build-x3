import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/build_x_secure_store.dart';
import '../../../core/services/skills/skills_service.dart';
import '../../../l10n/app_localizations.dart';

/// Stores a skill and browser account for future use without browser control.
class SearchFutureToolsSection extends StatefulWidget {
  const SearchFutureToolsSection({super.key});

  @override
  State<SearchFutureToolsSection> createState() =>
      _SearchFutureToolsSectionState();
}

class _SearchFutureToolsSectionState extends State<SearchFutureToolsSection> {
  final _skillName = TextEditingController();
  final _skillDescription = TextEditingController();
  final _skillInstructions = TextEditingController();
  final _site = TextEditingController();
  final _username = TextEditingController();
  final _secret = TextEditingController();
  bool _busySkill = false;
  bool _busyAccount = false;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    try {
      final raw = await BuildXSecureStore.readBrowserAccount();
      if (raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map || !mounted) return;
      _site.text = data['site']?.toString() ?? '';
      _username.text = data['username']?.toString() ?? '';
      _secret.text = data['secret']?.toString() ?? '';
    } catch (_) {
      // A malformed or unavailable secure entry leaves the form empty.
    }
  }

  @override
  void dispose() {
    _skillName.dispose();
    _skillDescription.dispose();
    _skillInstructions.dispose();
    _site.dispose();
    _username.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveSkill() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _skillName.text.trim();
    final description = _skillDescription.text.trim();
    final instructions = _skillInstructions.text.trim();
    if (name.isEmpty || description.isEmpty || instructions.isEmpty) {
      _notice(l10n.buildXSkillError);
      return;
    }
    setState(() => _busySkill = true);
    try {
      final markdown =
          '---\n'
          'name: ${jsonEncode(name)}\n'
          'description: ${jsonEncode(description)}\n'
          '---\n\n$instructions\n';
      await context.read<SkillsService>().importFromText(markdown);
      if (!mounted) return;
      _skillName.clear();
      _skillDescription.clear();
      _skillInstructions.clear();
      _notice(l10n.buildXSkillSaved);
    } catch (_) {
      if (mounted) _notice(l10n.buildXSkillError);
    } finally {
      if (mounted) setState(() => _busySkill = false);
    }
  }

  Future<void> _saveAccount() async {
    final l10n = AppLocalizations.of(context)!;
    final site = _site.text.trim();
    final uri = Uri.tryParse(site);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        _secret.text.trim().isEmpty) {
      _notice(l10n.buildXBrowserError);
      return;
    }
    setState(() => _busyAccount = true);
    try {
      await BuildXSecureStore.saveBrowserAccount(
        jsonEncode({
          'site': site,
          'username': _username.text.trim(),
          'secret': _secret.text,
        }),
      );
      if (mounted) _notice(l10n.buildXBrowserSaved);
    } catch (_) {
      if (mounted) _notice(l10n.buildXBrowserError);
    } finally {
      if (mounted) setState(() => _busyAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    InputDecoration field(String label) => InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          title: Text(l10n.buildXSkillSection),
          childrenPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          children: [
            TextField(
              controller: _skillName,
              decoration: field(l10n.buildXSkillName),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _skillDescription,
              decoration: field(l10n.buildXSkillDescription),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _skillInstructions,
              minLines: 3,
              maxLines: 8,
              decoration: field(l10n.buildXSkillInstructions),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busySkill ? null : _saveSkill,
                child: Text(l10n.buildXAddSkill),
              ),
            ),
          ],
        ),
        Divider(color: cs.outlineVariant),
        ExpansionTile(
          title: Text(l10n.buildXBrowserSection),
          childrenPadding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          children: [
            Text(l10n.buildXBrowserHelp),
            const SizedBox(height: 12),
            TextField(
              controller: _site,
              keyboardType: TextInputType.url,
              decoration: field(l10n.buildXBrowserSite),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _username,
              autofillHints: const [AutofillHints.username],
              decoration: field(l10n.buildXBrowserUser),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _secret,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: field(l10n.buildXBrowserSecret),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busyAccount ? null : _saveAccount,
                child: Text(l10n.buildXSaveBrowser),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
