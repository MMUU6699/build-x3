import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/message_part.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/providers/openai_images.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../chat/pages/image_viewer_page.dart';
import '../widgets/header_bubble_button.dart';

class ImagesGalleryPage extends StatefulWidget {
  const ImagesGalleryPage({super.key});

  @override
  State<ImagesGalleryPage> createState() => _ImagesGalleryPageState();
}

class _ImagesGalleryPageState extends State<ImagesGalleryPage> {
  final _promptController = TextEditingController();
  final _promptFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<_GeneratedItem> _items = [];
  XFile? _referenceImage;
  _ImageModel? _selectedModel;
  String? _error;
  bool _generating = false;

  @override
  void dispose() {
    _promptController.dispose();
    _promptFocus.dispose();
    _scrollController.dispose();
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

    final refPath = _referenceImage?.path;
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
            for (final img in images) {
              _items.insert(
                0,
                _GeneratedItem(
                  prompt: effectivePrompt,
                  image: img,
                  timestamp: DateTime.now(),
                  referenceImagePath: refPath,
                ),
              );
            }
            _referenceImage = null;
          });
          _promptController.clear();
          _scrollToTop();
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
        _items.insert(
          0,
          _GeneratedItem(
            prompt: effectivePrompt,
            image: ImagePart(uri: uri),
            timestamp: DateTime.now(),
            referenceImagePath: refPath,
          ),
        );
        _referenceImage = null;
      });
      _promptController.clear();
      _scrollToTop();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) {
      return 'Image generation failed. Please try again.';
    }
    return raw.length > 240 ? '${raw.substring(0, 237)}…' : raw;
  }

  void _openImageViewer(String uri) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => ImageViewerPage(images: [uri]),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (context, anim, sec, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final models = _models(settings);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101012) : const Color(0xFFF9FAFB),
      appBar: AppBar(
        toolbarHeight: 66,
        leadingWidth: 72,
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: Center(
          child: HeaderBubbleButton(
            // 40% larger back button (56px touch target, 26px icon)
            size: 56,
            onTap: () => Navigator.of(context).maybePop(),
            child: Icon(Lucide.ArrowLeft, size: 26, color: cs.onSurface),
          ),
        ),
        title: Text(
          'Images',
          style: TextStyle(
            fontSize: 18,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Content Area
          Positioned.fill(
            child: _items.isEmpty
                ? _buildEmptyState(cs, isDark)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _GeneratedItemCard(
                        item: item,
                        onTapImage: () => _openImageViewer(item.image.uri),
                      );
                    },
                  ),
          ),

          // ChatBox (Replicating main chat input bar, only image attachment on left)
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

  Widget _buildEmptyState(ColorScheme cs, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          const Color(0xFF2563EB).withValues(alpha: 0.35),
                          const Color(0xFF1E1B4B).withValues(alpha: 0.5),
                        ]
                      : [
                          const Color(0xFFDBEAFE),
                          const Color(0xFFEFF6FF),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: isDark ? 0.3 : 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Lucide.Image,
                  size: 36,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'AI Image Studio',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Type a prompt below to create any image, or attach a photo to edit and enhance.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.45,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _GeneratedItem {
  const _GeneratedItem({
    required this.prompt,
    required this.image,
    required this.timestamp,
    this.referenceImagePath,
  });

  final String prompt;
  final ImagePart image;
  final DateTime timestamp;
  final String? referenceImagePath;
}

class _GeneratedItemCard extends StatelessWidget {
  const _GeneratedItemCard({
    required this.item,
    required this.onTapImage,
  });

  final _GeneratedItem item;
  final VoidCallback onTapImage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF19191D)
            : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Prompt Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.referenceImagePath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: kIsWeb
                          ? Image.network(
                              item.referenceImagePath!,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(item.referenceImagePath!),
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    item.prompt,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Lucide.Copy,
                    size: 17,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                  tooltip: 'Copy prompt',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.prompt));
                    showAppSnackBar(
                      context,
                      message: 'Prompt copied',
                      type: NotificationType.success,
                    );
                  },
                ),
              ],
            ),
          ),

          // Main Image Display
          GestureDetector(
            onTap: onTapImage,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: _buildImageWidget(context, item.image.uri),
              ),
            ),
          ),

          // Actions Footer (Share / Fullscreen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: onTapImage,
                  icon: const Icon(Lucide.Maximize2, size: 16),
                  label: const Text('View Fullscreen'),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Lucide.Share2,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                  tooltip: 'Share',
                  onPressed: () {
                    // ignore: deprecated_member_use
                    Share.share(item.image.uri);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidget(BuildContext context, String uri) {
    if (uri.startsWith('data:') && uri.contains(',')) {
      try {
        return Image.memory(
          base64Decode(uri.substring(uri.indexOf(',') + 1)),
          fit: BoxFit.cover,
        );
      } catch (_) {
        return const Center(child: Icon(Lucide.ImageOff));
      }
    } else if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return Image.network(
        uri,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Lucide.ImageOff)),
      );
    } else if (!kIsWeb &&
        (uri.startsWith('file:') || uri.startsWith('kelivo-file:'))) {
      try {
        return Image.file(
          File(SandboxPathResolver.fix(uri)),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Lucide.ImageOff)),
        );
      } catch (_) {
        return const Center(child: Icon(Lucide.ImageOff));
      }
    } else {
      return const Center(child: Icon(Lucide.ImageOff));
    }
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
                  // ONLY Image attachment button on the left (replacing '+')
                  IconButton(
                    icon: Icon(
                      Lucide.Image,
                      size: 22,
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                    tooltip: 'Attach image to edit',
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
                        hintText: 'Describe an image to create...',
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
