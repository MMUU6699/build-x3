import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/providers/openai_images.dart';
import '../../../core/models/message_part.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../utils/sandbox_path_resolver.dart';

class ImagesGalleryPage extends StatefulWidget {
  const ImagesGalleryPage({super.key});

  @override
  State<ImagesGalleryPage> createState() => _ImagesGalleryPageState();
}

class _ImagesGalleryPageState extends State<ImagesGalleryPage> {
  static const _examples = <_ImageExample>[
    _ImageExample(
      title: 'Sticker set',
      prompt:
          'A cheerful set of six hand drawn stickers: a black cat, a potted plant, a friendly bearded person, tiny stars and flowers. Bold clean outlines, bright warm colors, white background.',
      icon: Lucide.Sparkles,
      colors: [Color(0xFFFFCF45), Color(0xFFFF8A58)],
    ),
    _ImageExample(
      title: 'Photosynthesis diagram',
      prompt:
          'A clear, colorful educational infographic diagram explaining photosynthesis in a green plant, labeled sunlight, water, carbon dioxide, glucose, and oxygen. Clean textbook illustration.',
      icon: Lucide.Shapes,
      colors: [Color(0xFF9BD77A), Color(0xFF287B61)],
    ),
    _ImageExample(
      title: 'Map of ancient Rome',
      prompt:
          'An illustrated antique parchment map of ancient Rome, showing the Tiber river, major hills, the Forum, and city walls, with small readable labels and a historical atlas style.',
      icon: Lucide.Map,
      colors: [Color(0xFFD9B477), Color(0xFF946A45)],
    ),
    _ImageExample(
      title: 'Civil War timeline',
      prompt:
          'A polished classroom infographic timeline of the American Civil War from 1861 to 1865, with major events, dates, simple historical illustrations, and a clear horizontal layout.',
      icon: Lucide.Timer,
      colors: [Color(0xFF9CB7CE), Color(0xFF455C79)],
    ),
    _ImageExample(
      title: 'Plant cell diagram',
      prompt:
          'A detailed but approachable labeled scientific cross section of a plant cell, showing cell wall, membrane, nucleus, chloroplasts, vacuole, and mitochondria in a clean textbook style.',
      icon: Lucide.circleDot,
      colors: [Color(0xFFB6D58C), Color(0xFF60815A)],
    ),
    _ImageExample(
      title: 'Cozy bedroom',
      prompt:
          'A photorealistic cozy bedroom at sunset with a large window, warm string lights, a leafy plant, soft cream bedding, and a calm lived-in atmosphere.',
      icon: Lucide.Bed,
      colors: [Color(0xFFE7A36B), Color(0xFF755B76)],
    ),
  ];

  final _promptController = TextEditingController();
  final _promptFocus = FocusNode();
  final List<ImagePart> _generated = [];
  _ImageModel? _selectedModel;
  String? _error;
  bool _generating = false;

  @override
  void dispose() {
    _promptController.dispose();
    _promptFocus.dispose();
    super.dispose();
  }

  List<_ImageModel> _models(SettingsProvider settings) {
    final models = <_ImageModel>[];
    for (final config in settings.providerConfigs.values) {
      if (!config.enabled) continue;
      final ids = <String>{...config.models, ...config.modelOverrides.keys};
      for (final id in ids) {
        if (shouldUseOpenAIImagesApi(config, id)) {
          models.add(_ImageModel(config: config, id: id));
        }
      }
    }
    return models;
  }

  Future<void> _generate(List<_ImageModel> models) async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _generating) return;

    setState(() {
      _error = null;
      _generating = true;
    });

    if (models.isNotEmpty) {
      final model = _selectedModel != null && models.contains(_selectedModel)
          ? _selectedModel!
          : models.first;
      _selectedModel = model;
      try {
        final result = await ChatApiService.generateMessage(
          config: model.config,
          modelId: model.id,
          messages: [
            {
              'role': 'system',
              'content':
                  'Image generation mode: create an image from the user prompt. Do not answer with text.',
            },
            {'role': 'user', 'content': prompt},
          ],
          persistConversation: false,
          allowImagesApiRouting: true,
        );
        final images = result.parts.whereType<ImagePart>().toList();
        if (images.isNotEmpty) {
          if (!mounted) return;
          setState(() => _generated.insertAll(0, images));
          _promptController.clear();
          return;
        }
      } catch (_) {
        // Fall back to direct image generation pipeline
      }
    }

    try {
      final uri =
          'https://image.pollinations.ai/prompt/${Uri.encodeComponent(prompt)}?width=1024&height=1024&nologo=true';
      if (!mounted) return;
      setState(() => _generated.insert(0, ImagePart(uri: uri)));
      _promptController.clear();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showExamplePromptSheet(
    BuildContext context,
    _ImageExample example,
    List<_ImageModel> models,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(colors: example.colors),
                    ),
                    child: Icon(example.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          example.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Example Prompt',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.outline.withValues(alpha: 0.12),
                  ),
                ),
                child: SelectableText(
                  example.prompt,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: example.prompt));
                        Navigator.of(ctx).pop();
                        setState(() {
                          _promptController.text = example.prompt;
                          _error = null;
                        });
                        _promptFocus.requestFocus();
                      },
                      icon: const Icon(Lucide.Copy, size: 18),
                      label: const Text('Use Prompt'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() {
                          _promptController.text = example.prompt;
                          _error = null;
                        });
                        _generate(models);
                      },
                      icon: const Icon(Lucide.Sparkles, size: 18),
                      label: const Text('Generate Now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) {
      return 'Image generation failed. Check the selected model and try again.';
    }
    return raw.length > 240 ? '${raw.substring(0, 237)}…' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final models = _models(settings);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Lucide.ArrowLeft),
        ),
        title: const Text('Images'),
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              if (_generated.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  sliver: SliverGrid.builder(
                    itemCount: _generated.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                    itemBuilder: (context, index) =>
                        _GeneratedImageTile(image: _generated[index]),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 150),
                sliver: SliverGrid.builder(
                  itemCount: _examples.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, index) {
                    final example = _examples[index];
                    return _ExampleTile(
                      example: example,
                      onTap: () => _showExamplePromptSheet(
                        context,
                        example,
                        models,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _Composer(
              controller: _promptController,
              focusNode: _promptFocus,
              models: models,
              selectedModel: _selectedModel,
              isGenerating: _generating,
              error: _error,
              onModelChanged: (model) => setState(() => _selectedModel = model),
              onSubmit: () => _generate(models),
            ),
          ),
        ],
      ),
      backgroundColor: cs.surface,
    );
  }
}

class _ImageModel {
  const _ImageModel({required this.config, required this.id});
  final ProviderConfig config;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is _ImageModel && config.id == other.config.id && id == other.id;

  @override
  int get hashCode => Object.hash(config.id, id);
}

class _ImageExample {
  const _ImageExample({
    required this.title,
    required this.prompt,
    required this.icon,
    required this.colors,
  });
  final String title;
  final String prompt;
  final IconData icon;
  final List<Color> colors;
}

class _ExampleTile extends StatelessWidget {
  const _ExampleTile({required this.example, required this.onTap});
  final _ImageExample example;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: example.colors,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Icon(
                example.icon,
                size: 78,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                example.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GeneratedImageTile extends StatelessWidget {
  const _GeneratedImageTile({required this.image});
  final ImagePart image;

  @override
  Widget build(BuildContext context) {
    final uri = image.uri;
    late final Widget child;
    if (uri.startsWith('data:') && uri.contains(',')) {
      try {
        child = Image.memory(
          base64Decode(uri.substring(uri.indexOf(',') + 1)),
          fit: BoxFit.cover,
        );
      } catch (_) {
        child = const Center(child: Icon(Lucide.ImageOff));
      }
    } else if (uri.startsWith('http://') || uri.startsWith('https://')) {
      child = Image.network(
        uri,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Center(child: Icon(Lucide.ImageOff)),
      );
    } else if (!kIsWeb &&
        (uri.startsWith('file:') || uri.startsWith('kelivo-file:'))) {
      try {
        child = Image.file(
          File(SandboxPathResolver.fix(uri)),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Center(child: Icon(Lucide.ImageOff)),
        );
      } catch (_) {
        child = const Center(child: Icon(Lucide.ImageOff));
      }
    } else {
      child = const Center(child: Icon(Lucide.ImageOff));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: child,
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.models,
    required this.selectedModel,
    required this.isGenerating,
    required this.error,
    required this.onModelChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<_ImageModel> models;
  final _ImageModel? selectedModel;
  final bool isGenerating;
  final String? error;
  final ValueChanged<_ImageModel?> onModelChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.97),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (models.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: DropdownButton<_ImageModel>(
                  value: models.contains(selectedModel)
                      ? selectedModel
                      : models.first,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final model in models)
                      DropdownMenuItem(
                        value: model,
                        child: Text(
                          '${model.config.name} · ${model.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onModelChanged,
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    error!,
                    style: TextStyle(color: cs.error, fontSize: 13),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Describe an image',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => onSubmit(),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: models.isEmpty
                      ? 'Configure an image model'
                      : 'Generate image',
                  onPressed: isGenerating ? null : onSubmit,
                  icon: isGenerating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Lucide.ArrowUp),
                ),
              ],
            ),
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Configure an enabled image-generation model to create images.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
