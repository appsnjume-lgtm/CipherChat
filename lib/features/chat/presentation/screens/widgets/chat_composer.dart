import 'package:flutter/material.dart';
import '../../../../../core/theme/app_theme.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.hasText,
    required this.isRecordingVoiceNote,
    required this.recordingDuration,
    required this.onPrimaryAction,
    required this.onChanged,
    required this.onStickerTap,
    required this.onAttachments,
    this.replyPreviewText,
    this.replyPreviewAttachment,
    this.replyAuthorLabel,
    this.onCancelReply,
    this.onCancelRecording,
    this.onTextFieldTap,
    this.isStickerPanelOpen = false,
    this.enterToSendEnabled = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final bool hasText;
  final bool isRecordingVoiceNote;
  final Duration recordingDuration;
  final Future<void> Function() onPrimaryAction;
  final ValueChanged<String> onChanged;
  final VoidCallback onStickerTap;
  final Future<void> Function({bool imagesOnly}) onAttachments;
  final String? replyPreviewText;
  final Widget? replyPreviewAttachment;
  final String? replyAuthorLabel;
  final VoidCallback? onCancelReply;
  final Future<void> Function()? onCancelRecording;
  final VoidCallback? onTextFieldTap;
  final bool isStickerPanelOpen;
  final bool enterToSendEnabled;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) {
      return;
    }
    oldWidget.focusNode.removeListener(_onFocusChange);
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gx = GXThemeExtension.of(context);
    final isGX = gx.isGX;
    final accent = gx.accent;

    final actionTooltip = widget.isRecordingVoiceNote
        ? 'Stop and send voice note'
        : widget.hasText
        ? 'Send message'
        : 'Record voice note';
    final actionIcon = widget.isRecordingVoiceNote
        ? Icons.stop_rounded
        : widget.hasText
        ? Icons.send_rounded
        : Icons.mic_rounded;

    const surfaceGX = Color(0xFF12121E);
    const surface2GX = Color(0xFF191926);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyPreviewText != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                decoration: BoxDecoration(
                  color: isGX
                      ? surface2GX
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(isGX ? 4 : 18),
                  border: Border.all(
                    color: isGX
                        ? accent.withValues(alpha: 0.3)
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: isGX ? 2 : 4,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isGX ? accent : theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (widget.replyPreviewAttachment != null) ...[
                      widget.replyPreviewAttachment!,
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isGX
                                ? (widget.replyAuthorLabel ?? 'REPLYING')
                                      .toUpperCase()
                                : (widget.replyAuthorLabel ?? 'Replying'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: isGX
                                ? TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    letterSpacing: 1.1,
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  )
                                : theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.replyPreviewText!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: isGX
                                ? const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Color(0xFFF0F0F8),
                                  )
                                : theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel reply',
                      onPressed: widget.isSending ? null : widget.onCancelReply,
                      icon: Icon(
                        Icons.close_rounded,
                        color: isGX ? accent : null,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.isRecordingVoiceNote)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isGX ? surface2GX : theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(isGX ? 4 : 18),
                  border: isGX
                      ? Border.all(
                          color: const Color(0xFFFF5252).withValues(alpha: 0.5),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      color: isGX
                          ? const Color(0xFFFF5252)
                          : theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isGX
                            ? 'RECORDING UPLINK - ${_formatDuration(widget.recordingDuration)}'
                            : 'Recording voice note - ${_formatDuration(widget.recordingDuration)}',
                        style: isGX
                            ? const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFF5252),
                              )
                            : theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w700,
                              ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Discard recording',
                      onPressed: widget.isSending
                          ? null
                          : () => widget.onCancelRecording?.call(),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: isGX
                            ? const Color(0xFFFF5252)
                            : theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isGX
                          ? surfaceGX
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(isGX ? 8 : 28),
                      border: Border.all(
                        color: widget.focusNode.hasFocus
                            ? (isGX ? accent : theme.colorScheme.primary)
                            : (isGX
                                  ? accent.withValues(alpha: 0.2)
                                  : theme.colorScheme.outlineVariant),
                        width: widget.focusNode.hasFocus ? 1.5 : 1.0,
                      ),
                      boxShadow: isGX && widget.focusNode.hasFocus
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: IconButton(
                            tooltip: widget.isStickerPanelOpen
                                ? 'Close stickers'
                                : 'Open stickers',
                            onPressed:
                                widget.isSending || widget.isRecordingVoiceNote
                                ? null
                                : widget.onStickerTap,
                            icon: Icon(
                              Icons.sticky_note_2_outlined,
                              color: widget.isStickerPanelOpen
                                  ? (isGX ? accent : theme.colorScheme.primary)
                                  : (isGX
                                        ? accent.withValues(alpha: 0.7)
                                        : theme.colorScheme.secondary),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            enabled: !widget.isRecordingVoiceNote,
                            minLines: 1,
                            maxLines: widget.enterToSendEnabled ? 1 : 4,
                            textInputAction: widget.enterToSendEnabled
                                ? TextInputAction.send
                                : TextInputAction.newline,
                            onTap: widget.onTextFieldTap,
                            onTapOutside: (_) =>
                                FocusScope.of(context).unfocus(),
                            onChanged: widget.onChanged,
                            onSubmitted: (_) {
                              if (widget.enterToSendEnabled &&
                                  !widget.isRecordingVoiceNote &&
                                  widget.hasText) {
                                widget.onPrimaryAction();
                              }
                            },
                            style: isGX
                                ? const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                    color: Color(0xFFF0F0F8),
                                  )
                                : null,
                            decoration: InputDecoration(
                              hintText: widget.isRecordingVoiceNote
                                  ? (isGX ? 'RECORDING...' : 'Recording...')
                                  : (isGX ? 'ENCRYPT MESSAGE' : 'Message'),
                              hintStyle: isGX
                                  ? const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                      letterSpacing: 0.5,
                                    )
                                  : null,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: IconButton(
                            tooltip: 'Open camera',
                            onPressed:
                                widget.isSending || widget.isRecordingVoiceNote
                                ? null
                                : () => widget.onAttachments(imagesOnly: true),
                            icon: Icon(
                              Icons.camera_alt_outlined,
                              color: isGX
                                  ? accent.withValues(alpha: 0.7)
                                  : theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: IconButton(
                            tooltip: 'Add attachment',
                            onPressed:
                                widget.isSending || widget.isRecordingVoiceNote
                                ? null
                                : () => widget.onAttachments(),
                            icon: Icon(
                              Icons.attach_file_rounded,
                              color: isGX
                                  ? accent.withValues(alpha: 0.7)
                                  : theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                isGX
                    ? GestureDetector(
                        onTap: widget.isSending
                            ? null
                            : () => widget.onPrimaryAction(),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            border: Border.all(color: accent, width: 1.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: widget.isSending
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: accent,
                                    ),
                                  )
                                : Icon(actionIcon, color: accent, size: 22),
                          ),
                        ),
                      )
                    : IconButton.filled(
                        tooltip: actionTooltip,
                        onPressed: widget.isSending
                            ? null
                            : () => widget.onPrimaryAction(),
                        icon: widget.isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(actionIcon),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
