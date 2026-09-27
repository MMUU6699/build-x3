import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/models/message_part.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/providers/openai_images.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../widgets/header_bubble_button.dart';

class ImagesGalleryPage extends StatefulWidget {
  const ImagesGalleryPage({super.key});

  @override
  State<ImagesGalleryPage> createState() => _ImagesGalleryPageState();
}

class _ImagesGalleryPageState extends State<ImagesGalleryPage> {
  static const _examples = <_ImageExample>[
    _ImageExample(
      title: 'Stickers',
      prompt:
          'A cheerful set of six hand drawn stickers: a black cat, a potted plant, a friendly bearded person, tiny stars and flowers. Bold clean outlines, bright warm colors, white background.',
      imageAsset: 'assets/images/examples/stickers.png',
      icon: Lucide.Sparkles,
      colors: [Color(0xFFFFCF45), Color(0xFFFF8A58)],
    ),
    _ImageExample(
      title: 'Photosynthesis as a diagram',
      prompt:
          'A clear, colorful educational infographic diagram explaining photosynthesis in a green plant, labeled sunlight, water, carbon dioxide, glucose, and oxygen. Clean textbook illustration.',
      imageAsset: 'assets/images/examples/photosynthesis.png',
      icon: Lucide.Shapes,
      colors: [Color(0xFF9BD77A), Color(0xFF287B61)],
    ),
    _ImageExample(
      title: 'Map of ancient Rome',
      prompt:
          'An illustrated antique parchment map of ancient Rome, showing the Tiber river, major hills, the Forum, and city walls, with small readable labels and a historical atlas style.',
      imageAsset: 'assets/images/examples/rome_map.png',
      icon: Lucide.Map,
      colors: [Color(0xFFD9B477), Color(0xFF946A45)],
    ),
    _ImageExample(
      title: 'Timeline of the Civil War',
      prompt:
          'A polished classroom infographic timeline of the American Civil War from 1861 to 1865, with major events, dates, simple historical illustrations, and a clear horizontal layout.',
      imageAsset: 'assets/images/examples/civil_war.png',
      icon: Lucide.Timer,
      colors: [Color(0xFF9CB7CE), Color(0xFF455C79)],
    ),
    _ImageExample(
      title: 'Plant cell',
      prompt:
          'A detailed but approachable labeled scientific cross section of a plant cell, showing cell wall, membrane, nucleus, chloroplasts, vacuole, and mitochondria in a clean textbook style.',
      imageAsset: 'assets/images/examples/plant_cell.png',
      icon: Lucide.circleDot,
      colors: [Color(0xFFB6D58C), Color(0xFF60815A)],
    ),
    _ImageExample(
      title: 'Cozy bedroom',
      prompt:
          'A photorealistic cozy bedroom at sunset with a large window, warm string lights, a leafy plant, soft cream bedding, and a calm lived-in atmosphere.',
      imageAsset: 'assets/images/examples/cozy_bedroom.png',
      icon: Lucide.Bed,
      colors: [Color(0xFFE7A36B), Color(0xFF755B76)],
    ),
  ];

  final _promptController = TextEditingController();
  final _promptFocus = FocusNode();
  final List<ImagePart> _generated = [];
  XFile? _referenceImage;
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

  Future<void> _pickReferenceImage() async {
    try {
      Haptics.light();
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 88,
      );
      if (picked != null) {
        setState(() {
          _referenceImage = picked;
        });
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Could not select image: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  void _clearReferenceImage() {
    Haptics.light();
    setState(() {
      _referenceImage = null;
    });
  }

  Future<void> _generate(List<_ImageModel> models) async {
    final prompt = _promptController.text.trim();
    if ((prompt.isEmpty && _referenceImage == null) || _generating) return;

    setState(() {
      _error = null;
      _generating = true;
    });

    final effectivePrompt = prompt.isNotEmpty
        ? prompt
        : 'Generate a variation or detailed enhancement of the reference image';

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
                  'Image generation mode: create or edit an image based on the user prompt. Do not answer with text.',
            },
            {'role': 'user', 'content': effectivePrompt},
          ],
          persistConversation: false,
          allowImagesApiRouting: true,
        );
        final images = result.parts.whereType<ImagePart>().toList();
        if (images.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _generated.insertAll(0, images);
            _referenceImage = null;
          });
          _promptController.clear();
          return;
        }
      } catch (_) {
        // Fall back to direct image pipeline
      }
    }

    try {
      final seed = DateTime.now().millisecondsSinceEpoch % 100000;
      final uri =
          'https://image.pollinations.ai/prompt/${Uri.encodeComponent(effectivePrompt)}?width=1024&height=1024&nologo=true&seed=$seed';
      if (!mounted) return;
      setState(() {
        _generated.insert(0, ImagePart(uri: uri));
        _referenceImage = null;
      });
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
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Image.asset(
                        example.imageAsset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: example.colors),
                          ),
                          child: Icon(example.icon, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          example.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Prompt inspiration',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.55),
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
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
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
                        backgroundColor: const Color(0xFF2563EB),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Center(
          child: HeaderBubbleButton(
            size: 40,
            onTap: () => Navigator.of(context).maybePop(),
            child: Icon(Lucide.ArrowLeft, size: 19, color: cs.onSurface),
          ),
        ),
        title: Text(
          'Images',
          style: TextStyle(
            fontSize: 18,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface,
          ),
        ),
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Text(
                    'Create an image',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              if (_generated.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Generated',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              ],
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
                sliver: SliverGrid.builder(
                  itemCount: _examples.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.82,
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
            child: _ImageChatBox(
              controller: _promptController,
              focusNode: _promptFocus,
              referenceImage: _referenceImage,
              models: models,
              selectedModel: _selectedModel,
              isGenerating: _generating,
              error: _error,
              onPickImage: _pickReferenceImage,
              onClearImage: _clearReferenceImage,
              onModelChanged: (model) => setState(() => _selectedModel = model),
              onSubmit: () => _generate(models),
            ),
          ),
        ],
      ),
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
    required this.imageAsset,
    required this.icon,
    required this.colors,
  });
  final String title;
  final String prompt;
  final String imageAsset;
  final IconData icon;
  final List<Color> colors;
}

class _ExampleTile extends StatelessWidget {
  const _ExampleTile({required this.example, required this.onTap});
  final _ImageExample example;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  example.imageAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: example.colors,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        example.icon,
                        size: 54,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.55, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

class _ImageChatBox extends StatelessWidget {
  const _ImageChatBox({
    required this.controller,
    required this.focusNode,
    required this.referenceImage,
    required this.models,
    required this.selectedModel,
    required this.isGenerating,
    required this.error,
    required this.onPickImage,
    required this.onClearImage,
    required this.onModelChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final XFile? referenceImage;
  final List<_ImageModel> models;
  final _ImageModel? selectedModel;
  final bool isGenerating;
  final String? error;
  final VoidCallback onPickImage;
  final VoidCallback onClearImage;
  final ValueChanged<_ImageModel?> onModelChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final boxBg = isDark
        ? const Color(0xFF1E1E22).withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.98);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Lucide.AlertCircle, size: 16, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        error!,
                        style: TextStyle(color: cs.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (referenceImage != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: boxBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outline.withValues(alpha: 0.15),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb
                            ? Image.network(
                                referenceImage!.path,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(referenceImage!.path),
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                              ),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: GestureDetector(
                          onTap: onClearImage,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(
                              Lucide.X,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: boxBg,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Lucide.Image,
                      size: 22,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                    tooltip: 'Add image to edit',
                    onPressed: onPickImage,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Describe an image',
                        hintStyle: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 4,
                        ),
                      ),
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                      ),
                      onSubmitted: (_) => onSubmit(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Lucide.Mic,
                      size: 20,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                    tooltip: 'Voice input',
                    onPressed: () {
                      Haptics.light();
                    },
                  ),
                  const SizedBox(width: 2),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF1E293B),
                    ),
                    child: Center(
                      child: isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Lucide.ArrowUp,
                                size: 19,
                                color: Colors.white,
                              ),
                              onPressed: onSubmit,
                            ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
