import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../core/services/work/work_agent_event.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';

/// Modal dialog for an interactive WebView preview of a backend-produced deliverable.
class WorkDeliverablePreviewModal extends StatefulWidget {
  const WorkDeliverablePreviewModal({super.key, required this.deliverable});

  final WorkDeliverableEvent deliverable;

  static void show(BuildContext context, WorkDeliverableEvent deliverable) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Preview',
      barrierColor: Colors.black87,
      pageBuilder: (context, anim1, anim2) {
        return WorkDeliverablePreviewModal(deliverable: deliverable);
      },
    );
  }

  @override
  State<WorkDeliverablePreviewModal> createState() =>
      _WorkDeliverablePreviewModalState();
}

class _WorkDeliverablePreviewModalState
    extends State<WorkDeliverablePreviewModal> {
  WebViewController? _controller;
  bool _showSource = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      final ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white);
      await ctrl.loadHtmlString(widget.deliverable.previewHtml);
      if (mounted) {
        setState(() {
          _controller = ctrl;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 780),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outline.withAlpha(60)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: cs.surface,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Lucide.X, color: cs.onSurface),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Row(
              children: [
                Icon(Lucide.Sparkles, size: 16, color: cs.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.deliverable.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: AppFontWeights.semiBold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              // Segmented toggle between rendered preview and source.
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withAlpha(100),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showSource = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: !_showSource ? cs.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Lucide.Play, size: 13, color: cs.onSurface),
                            const SizedBox(width: 4),
                            Text(
                              'Preview',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: AppFontWeights.medium,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showSource = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _showSource ? cs.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Lucide.Code, size: 13, color: cs.onSurface),
                            const SizedBox(width: 4),
                            Text(
                              'Source',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: AppFontWeights.medium,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _showSource
              ? _buildSourceView(context)
              : _buildWebView(context),
        ),
      ),
    );
  }

  Widget _buildWebView(BuildContext context) {
    if (_loading || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: _controller!);
  }

  Widget _buildSourceView(BuildContext context) {
    return Container(
      color: const Color(0xFF111113),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: SelectableText(
          widget.deliverable.previewHtml,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5,
            color: Color(0xFFE4E4E7),
          ),
        ),
      ),
    );
  }
}
