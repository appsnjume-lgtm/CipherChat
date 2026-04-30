import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../application/models/resolved_chat_message.dart';
import '../../domain/entities/chat_background_config.dart';
import '../../domain/entities/message.dart';
import '../providers/chat_background_provider.dart';
import '../widgets/chat_background_layer.dart';
import '../widgets/message_bubble.dart';

class ChatBackgroundEditorScreen extends ConsumerStatefulWidget {
  const ChatBackgroundEditorScreen({super.key, this.chatId});

  final String? chatId;

  bool get isGlobalEditor => chatId == null;

  @override
  ConsumerState<ChatBackgroundEditorScreen> createState() =>
      _ChatBackgroundEditorScreenState();
}

class _ChatBackgroundEditorScreenState
    extends ConsumerState<ChatBackgroundEditorScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  bool _didSeedDraft = false;
  bool _isColorPaletteExpanded = false;
  String? _pendingImageSourcePath;
  late ChatBackgroundConfig _draftConfig;

  ChatBackgroundConfig get _previewConfig => _pendingImageSourcePath == null
      ? _draftConfig
      : _draftConfig.copyWith(imagePath: _pendingImageSourcePath);

  Color? get _selectedBubbleColor => _draftConfig.bubbleColor == null
      ? null
      : Color(_draftConfig.bubbleColor!);

  List<Color?> _visibleBubbleSwatches(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = _selectedBubbleColor;

    return _bubbleSwatches
        .where((color) {
          if (color == null) {
            return true;
          }
          if (selectedColor?.toARGB32() == color.toARGB32()) {
            return true;
          }
          return _isBubbleColorDistinctFromTheme(color, theme);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatBackgroundProvider(widget.chatId));
    final theme = Theme.of(context);

    if (!_didSeedDraft && !state.isLoading) {
      _draftConfig = state.editableConfig;
      _didSeedDraft = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: state.isSaving
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : IconButton.filled(
                    onPressed: _saveChanges,
                    icon: const Icon(Icons.check_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                    ),
                  ),
          ),
        ],
      ),
      body: state.isLoading && !_didSeedDraft
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  _buildPreviewStage(context, state),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        _buildSourceCard(context, state),
                        const SizedBox(height: 16),
                        _buildBubbleColorCard(context),
                        if (state.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            state.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPreviewStage(BuildContext context, ChatBackgroundState state) {
    final previewHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.62,
      520.0,
    );

    return Container(
      color: Colors.black,
      child: SizedBox(
        height: previewHeight,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                ChatBackgroundLayer(config: _previewConfig),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: _previewConfig.hasImage
                        ? (details) => _handlePreviewDrag(details, constraints)
                        : null,
                  ),
                ),
                Container(color: Colors.black.withValues(alpha: 0.10)),
                _buildPreviewConversation(context),
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: _buildPreviewHint(context),
                ),
                Positioned(
                  left: 12,
                  bottom: 18,
                  child: _ColorPaletteDock(
                    selectedColor: _selectedBubbleColor,
                    swatches: _visibleBubbleSwatches(context),
                    isExpanded: _isColorPaletteExpanded,
                    onToggle: () => setState(
                      () => _isColorPaletteExpanded = !_isColorPaletteExpanded,
                    ),
                    onColorSelected: state.isSaving
                        ? null
                        : (color) => setState(() {
                            _draftConfig = color == null
                                ? _draftConfig.copyWith(clearBubbleColor: true)
                                : _draftConfig.copyWith(
                                    bubbleColor: color.toARGB32(),
                                  );
                          }),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 18,
                  child: _BrightnessDock(
                    value: _draftConfig.brightness,
                    onChanged: state.isSaving
                        ? null
                        : (value) => setState(
                            () => _draftConfig = _draftConfig.copyWith(
                              brightness: value,
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPreviewHint(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.44),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          _previewConfig.hasImage
              ? 'Drag to reposition your wallpaper. Bubble color updates live while you edit.'
              : 'Choose an image to preview and customize this background.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewConversation(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 48, 14, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Today',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          MessageBubble(
            message: ResolvedChatMessage(
              id: 'preview-1',
              chatId: 'preview',
              senderId: 'other',
              kind: MessageKind.text,
              createdAt: DateTime(2026, 4, 4, 10, 15),
              isMine: false,
              deliveryState: MessageDeliveryState.read,
              text: 'Pinch to zoom or drag to adjust your wallpaper.',
            ),
          ),
          const SizedBox(height: 8),
          MessageBubble(
            message: ResolvedChatMessage(
              id: 'preview-2',
              chatId: 'preview',
              senderId: 'me',
              kind: MessageKind.text,
              createdAt: DateTime(2026, 4, 4, 10, 16),
              isMine: true,
              deliveryState: MessageDeliveryState.read,
              text:
                  'Only your chat changes. You see updates instantly while editing.',
            ),
            outgoingBubbleColor: _selectedBubbleColor,
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSourceCard(BuildContext context, ChatBackgroundState state) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isGlobalEditor
                  ? 'Default background'
                  : 'This chat background',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.isGlobalEditor
                  ? 'This wallpaper is stored only on this device and will be used when a chat does not have its own override.'
                  : state.hasChatOverride
                  ? 'This chat is using its own local background override.'
                  : 'This chat is currently inheriting the global background until you save an override.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: state.isSaving ? null : _pickBackgroundImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose image'),
                ),
                OutlinedButton.icon(
                  onPressed: state.isSaving || !_previewConfig.hasImage
                      ? null
                      : _removeImage,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove image'),
                ),
                TextButton.icon(
                  onPressed: state.isSaving ? null : _handleResetAction,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(widget.isGlobalEditor ? 'Reset' : 'Use global'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubbleColorCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _selectedBubbleColor ?? theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: _selectedBubbleColor == null
                  ? Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: theme.colorScheme.onPrimary,
                      size: 18,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bubble color',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use the swatch on the preview to set the outgoing message bubble color for this chat background. Colors that blend too closely with the current theme are hidden automatically.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePreviewDrag(
    DragUpdateDetails details,
    BoxConstraints constraints,
  ) {
    final width = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
    final height = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;

    setState(() {
      _draftConfig = _draftConfig.copyWith(
        offsetX: (_draftConfig.offsetX + (details.delta.dx / width) * 2).clamp(
          -1.0,
          1.0,
        ),
        offsetY: (_draftConfig.offsetY + (details.delta.dy / height) * 2).clamp(
          -1.0,
          1.0,
        ),
      );
    });
  }

  Future<void> _pickBackgroundImage() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (image == null || !mounted) {
      return;
    }

    setState(() {
      _pendingImageSourcePath = image.path;
      _draftConfig = _draftConfig.copyWith(imagePath: image.path);
    });
  }

  void _removeImage() {
    setState(() {
      _pendingImageSourcePath = null;
      _draftConfig = _draftConfig.copyWith(clearImage: true);
    });
  }

  Future<void> _saveChanges() async {
    try {
      await ref
          .read(chatBackgroundProvider(widget.chatId).notifier)
          .saveConfig(
            _draftConfig,
            replacementImageSourcePath: _pendingImageSourcePath,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _handleResetAction() async {
    final notifier = ref.read(chatBackgroundProvider(widget.chatId).notifier);
    try {
      if (widget.isGlobalEditor) {
        await notifier.resetGlobal();
      } else {
        await notifier.clearChatOverride();
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }
}

class _ColorPaletteDock extends StatelessWidget {
  const _ColorPaletteDock({
    required this.selectedColor,
    required this.swatches,
    required this.isExpanded,
    required this.onToggle,
    required this.onColorSelected,
  });

  final Color? selectedColor;
  final List<Color?> swatches;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<Color?>? onColorSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onToggle,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selectedColor ?? Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: selectedColor == null
                    ? const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Colors.white,
                      )
                    : null,
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(width: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: swatches
                      .map(
                        (color) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _PaletteSwatch(
                            color: color,
                            isSelected:
                                selectedColor?.toARGB32() == color?.toARGB32(),
                            onTap: onColorSelected == null
                                ? null
                                : () => onColorSelected!(color),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color? color;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: isSelected ? 34 : 30,
        height: isSelected ? 34 : 30,
        decoration: BoxDecoration(
          color: color ?? Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white,
            width: isSelected ? 2.2 : 1.4,
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: color == null
            ? const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Colors.white,
                size: 16,
              )
            : null,
      ),
    );
  }
}

class _BrightnessDock extends StatelessWidget {
  const _BrightnessDock({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 74,
          height: 226,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(36),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 8,
                activeTrackColor: Colors.black87,
                inactiveTrackColor: Colors.black12,
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
              ),
              child: Slider(
                value: value,
                min: 0.5,
                max: 1.5,
                divisions: 10,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.brightness_6_outlined, color: Colors.black87),
        ),
      ],
    );
  }
}

bool _isBubbleColorDistinctFromTheme(Color color, ThemeData theme) {
  final candidates = <Color>{
    theme.colorScheme.surface,
    theme.colorScheme.surfaceContainerLow,
    theme.scaffoldBackgroundColor,
  };

  for (final background in candidates) {
    final distance = _colorDistance(color, background);
    final luminanceGap =
        (color.computeLuminance() - background.computeLuminance()).abs();
    if (distance < 88 || luminanceGap < 0.18) {
      return false;
    }
  }

  return true;
}

double _colorDistance(Color a, Color b) {
  final dr = (a.r - b.r).toDouble();
  final dg = (a.g - b.g).toDouble();
  final db = (a.b - b.b).toDouble();
  return math.sqrt((dr * dr) + (dg * dg) + (db * db));
}

const List<Color?> _bubbleSwatches = <Color?>[
  null,
  Colors.green,
  Colors.teal,
  Colors.blue,
  Colors.indigo,
  Colors.orange,
  Colors.red,
  Colors.pink,
  Colors.brown,
  Colors.black,
];
