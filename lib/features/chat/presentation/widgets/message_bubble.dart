import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/date_helper.dart';
import '../../application/models/resolved_chat_message.dart';
import '../../domain/entities/message.dart';
import 'highlighted_text.dart';

// -----------------------------------------------------------------------------
// Public widget â€” auto-selects GX or normal style via GXThemeExtension
// -----------------------------------------------------------------------------

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.attachmentPreview,
    this.onAttachmentTap,
    this.onLongPress,
    this.senderLabel,
    this.replyPreviewText,
    this.replyPreviewAttachment,
    this.replyAuthorLabel,
    this.outgoingBubbleColor,
    this.isSelected = false,
    this.onReplySwipe,
    this.cryptoStatusLabel,
    this.highlightQuery,
    this.isActiveSearchResult = false,
    this.isInactiveGridBreachInvite = false,
  });

  final ResolvedChatMessage message;
  final Widget? attachmentPreview;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onLongPress;
  final String? senderLabel;
  final String? replyPreviewText;
  final Widget? replyPreviewAttachment;
  final String? replyAuthorLabel;
  final Color? outgoingBubbleColor;
  final bool isSelected;
  final VoidCallback? onReplySwipe;
  final String? cryptoStatusLabel;
  final String? highlightQuery;
  final bool isActiveSearchResult;
  final bool isInactiveGridBreachInvite;

  @override
  Widget build(BuildContext context) {
    final gx = GXThemeExtension.of(context);

    if (gx.isGX) {
      return _GXMessageBubble(
        message: message,
        attachmentPreview: attachmentPreview,
        onAttachmentTap: onAttachmentTap,
        onLongPress: onLongPress,
        senderLabel: senderLabel,
        replyPreviewText: replyPreviewText,
        replyPreviewAttachment: replyPreviewAttachment,
        replyAuthorLabel: replyAuthorLabel,
        isSelected: isSelected,
        onReplySwipe: onReplySwipe,
        cryptoStatusLabel: cryptoStatusLabel,
        highlightQuery: highlightQuery,
        isActiveSearchResult: isActiveSearchResult,
        isInactiveGridBreachInvite: isInactiveGridBreachInvite,
        accent: gx.accent,
      );
    }

    return _NormalMessageBubble(
      message: message,
      attachmentPreview: attachmentPreview,
      onAttachmentTap: onAttachmentTap,
      onLongPress: onLongPress,
      senderLabel: senderLabel,
      replyPreviewText: replyPreviewText,
      replyPreviewAttachment: replyPreviewAttachment,
      replyAuthorLabel: replyAuthorLabel,
      outgoingBubbleColor: outgoingBubbleColor,
      isSelected: isSelected,
      onReplySwipe: onReplySwipe,
      cryptoStatusLabel: cryptoStatusLabel,
      highlightQuery: highlightQuery,
      isActiveSearchResult: isActiveSearchResult,
      isInactiveGridBreachInvite: isInactiveGridBreachInvite,
    );
  }
}

// -----------------------------------------------------------------------------
// NORMAL BUBBLE
// -----------------------------------------------------------------------------

class _NormalMessageBubble extends StatelessWidget {
  const _NormalMessageBubble({
    required this.message,
    this.attachmentPreview,
    this.onAttachmentTap,
    this.onLongPress,
    this.senderLabel,
    this.replyPreviewText,
    this.replyPreviewAttachment,
    this.replyAuthorLabel,
    this.outgoingBubbleColor,
    this.isSelected = false,
    this.onReplySwipe,
    this.cryptoStatusLabel,
    this.highlightQuery,
    this.isActiveSearchResult = false,
    this.isInactiveGridBreachInvite = false,
  });

  static const double _kBubbleWidthFactor = 0.75;
  static const double _kStickerBubbleMaxDimension = 200;

  final ResolvedChatMessage message;
  final Widget? attachmentPreview;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onLongPress;
  final String? senderLabel;
  final String? replyPreviewText;
  final Widget? replyPreviewAttachment;
  final String? replyAuthorLabel;
  final Color? outgoingBubbleColor;
  final bool isSelected;
  final VoidCallback? onReplySwipe;
  final String? cryptoStatusLabel;
  final String? highlightQuery;
  final bool isActiveSearchResult;
  final bool isInactiveGridBreachInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMine = message.isMine;
    final maxBubbleWidth =
        MediaQuery.sizeOf(context).width * _kBubbleWidthFactor;

    // Grid Breach handling
    if (message.kind == MessageKind.grid_breach) {
      return _GridBreachInvite(
        message: message,
        isGX: false,
        isInactive: isInactiveGridBreachInvite,
      );
    }

    final defaultOutgoingBubbleColor = Color.lerp(
      theme.colorScheme.primary,
      Colors.black,
      0.12,
    )!;
    final resolvedOutgoingBubbleColor =
        outgoingBubbleColor ?? defaultOutgoingBubbleColor;
    final outgoingBubbleBrightness = ThemeData.estimateBrightnessForColor(
      resolvedOutgoingBubbleColor,
    );
    final outgoingTextColor = outgoingBubbleBrightness == Brightness.dark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF10212B);
    final outgoingLinkColor = outgoingBubbleBrightness == Brightness.dark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF0B3B5C);
    final bubbleColor = isMine
        ? resolvedOutgoingBubbleColor
        : theme.colorScheme.surfaceContainerLow;
    final textColor = isMine ? outgoingTextColor : theme.colorScheme.onSurface;
    final metaColor = isMine
        ? outgoingTextColor.withValues(
            alpha: outgoingBubbleBrightness == Brightness.dark ? 0.76 : 0.68,
          )
        : theme.colorScheme.onSurfaceVariant;
    final previewBackground = isMine
        ? _outgoingPreviewBackground(
            resolvedOutgoingBubbleColor,
            outgoingBubbleBrightness,
          )
        : theme.colorScheme.surfaceContainerHighest;
    final defaultBorderColor = isMine
        ? _outgoingBorderColor(
            resolvedOutgoingBubbleColor,
            outgoingTextColor,
            outgoingBubbleBrightness,
          )
        : theme.colorScheme.outlineVariant;
    final selectedBorderColor = isMine
        ? _outgoingBorderColor(
            resolvedOutgoingBubbleColor,
            outgoingTextColor,
            outgoingBubbleBrightness,
            emphasized: true,
          )
        : theme.colorScheme.primary;
    final activeSearchBorderColor = isMine
        ? _outgoingSearchBorderColor(
            resolvedOutgoingBubbleColor,
            outgoingBubbleBrightness,
          )
        : Colors.amber.shade700;
    final bubbleItemAlignment = isMine
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final bubbleCrossAxisAlignment = isMine
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final bubbleTextAlign = isMine ? TextAlign.right : TextAlign.left;
    final effectiveHighlightQuery = highlightQuery?.trim() ?? '';
    final bodyText = message.previewText.trim();
    final shouldShowBodyText =
        bodyText.isNotEmpty &&
        !((message.kind == MessageKind.audio ||
                message.kind == MessageKind.sticker) &&
            attachmentPreview != null);
    final isSingleEmojiMessage = _isTransparentSingleEmojiMessage(
      bodyText,
      attachmentPreview: attachmentPreview,
      replyPreviewText: replyPreviewText,
      senderLabel: senderLabel,
      hasLinkPreview: message.linkPreview != null,
      isViewOnce: message.isViewOnce,
      highlightQuery: effectiveHighlightQuery,
    );
    final isBubblelessSticker =
        message.kind == MessageKind.sticker &&
        attachmentPreview != null &&
        replyPreviewText == null &&
        senderLabel == null &&
        !message.isViewOnce &&
        message.linkPreview == null &&
        effectiveHighlightQuery.isEmpty;
    final useCompactWidth =
        isBubblelessSticker ||
        _shouldUseCompactBubbleWidth(
          bodyText,
          attachmentPreview: attachmentPreview,
          replyPreviewText: replyPreviewText,
          senderLabel: senderLabel,
          hasLinkPreview: message.linkPreview != null,
          isViewOnce: message.isViewOnce,
          highlightQuery: effectiveHighlightQuery,
          isSingleEmojiMessage: isSingleEmojiMessage,
        );
    final bubblePadding = (isSingleEmojiMessage || isBubblelessSticker)
        ? EdgeInsets.zero
        : useCompactWidth
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.all(14);
    final transparentMetaColor = theme.colorScheme.onSurfaceVariant;
    final replyContentMaxWidth =
        (maxBubbleWidth - (replyPreviewAttachment != null ? 60 : 0))
            .clamp(120.0, maxBubbleWidth)
            .toDouble();

    Widget alignBubbleItem(Widget child) =>
        Align(alignment: bubbleItemAlignment, widthFactor: 1, child: child);

    final bubbleBody = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: bubbleCrossAxisAlignment,
        children: [
          if (senderLabel != null) ...[
            alignBubbleItem(
              Text(
                senderLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: bubbleTextAlign,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (replyPreviewText != null) ...[
            alignBubbleItem(
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: previewBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (replyPreviewAttachment != null) ...[
                      replyPreviewAttachment!,
                      const SizedBox(width: 10),
                    ],
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: replyContentMaxWidth,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: bubbleCrossAxisAlignment,
                        children: [
                          Text(
                            replyAuthorLabel ?? 'Reply',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: bubbleTextAlign,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            replyPreviewText!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: bubbleTextAlign,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: textColor.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (message.isViewOnce)
            alignBubbleItem(
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: textColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  message.isConsumed ? 'View once consumed' : 'View once',
                  textAlign: bubbleTextAlign,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (attachmentPreview != null) ...[
            alignBubbleItem(
              message.kind == MessageKind.sticker
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _kStickerBubbleMaxDimension,
                        maxHeight: _kStickerBubbleMaxDimension,
                      ),
                      child: attachmentPreview!,
                    )
                  : attachmentPreview!,
            ),
            if (!isBubblelessSticker) const SizedBox(height: 10),
          ],
          if (message.linkPreview != null) ...[
            alignBubbleItem(
              _UrlPreviewWidget(
                data: message.linkPreview!,
                backgroundColor: previewBackground,
                textColor: textColor,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (shouldShowBodyText) ...[
            alignBubbleItem(
              isSingleEmojiMessage
                  ? Text(
                      bodyText,
                      textAlign: bubbleTextAlign,
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontSize: 46,
                        height: 1.0,
                      ),
                    )
                  : effectiveHighlightQuery.isNotEmpty
                  ? HighlightedText(
                      text: message.previewText,
                      query: effectiveHighlightQuery,
                      textAlign: bubbleTextAlign,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: textColor,
                      ),
                      highlightStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        backgroundColor:
                            (isActiveSearchResult
                                    ? Colors.amber.shade400
                                    : Colors.amber.shade200)
                                .withValues(alpha: isMine ? 0.48 : 0.72),
                      ),
                    )
                  : Linkify(
                      onOpen: (link) async {
                        final uri = Uri.tryParse(link.url);
                        if (uri != null) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      text: message.previewText,
                      textAlign: bubbleTextAlign,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: textColor,
                      ),
                      linkStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: isMine
                            ? outgoingLinkColor
                            : theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            SizedBox(height: isSingleEmojiMessage ? 4 : 10),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                DateHelper.formatBubbleTime(message.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isSingleEmojiMessage || isBubblelessSticker
                      ? transparentMetaColor
                      : metaColor,
                  fontSize: 11,
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 8),
                _DeliveryIndicator(
                  state: message.deliveryState,
                  color: isSingleEmojiMessage || isBubblelessSticker
                      ? transparentMetaColor
                      : metaColor,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    final bubbleChild = GestureDetector(
      onLongPress: onLongPress,
      onTap: onAttachmentTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: bubblePadding,
        decoration:
            (isSingleEmojiMessage || isBubblelessSticker) &&
                !isSelected &&
                !isActiveSearchResult
            ? null
            : BoxDecoration(
                color: isBubblelessSticker
                    ? theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.34,
                      )
                    : bubbleColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected
                      ? selectedBorderColor
                      : isActiveSearchResult
                      ? activeSearchBorderColor
                      : defaultBorderColor,
                  width: isSelected || isActiveSearchResult ? 1.8 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: selectedBorderColor.withValues(alpha: 0.32),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : isActiveSearchResult
                    ? [
                        BoxShadow(
                          color: activeSearchBorderColor.withValues(
                            alpha: 0.24,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
        child: bubbleBody,
      ),
    );

    final interactiveChild = onReplySwipe == null
        ? bubbleChild
        : _NormalReplySwipeWrapper(
            messageId: message.id,
            onReplySwipe: onReplySwipe!,
            child: bubbleChild,
          );

    final statusChip = cryptoStatusLabel == null
        ? null
        : Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              cryptoStatusLabel!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: isMine
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: bubbleCrossAxisAlignment,
          children: [interactiveChild, if (statusChip != null) statusChip],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// GX BUBBLE
// -----------------------------------------------------------------------------

class _GXMessageBubble extends StatelessWidget {
  const _GXMessageBubble({
    required this.message,
    required this.accent,
    this.attachmentPreview,
    this.onAttachmentTap,
    this.onLongPress,
    this.senderLabel,
    this.replyPreviewText,
    this.replyPreviewAttachment,
    this.replyAuthorLabel,
    this.isSelected = false,
    this.onReplySwipe,
    this.cryptoStatusLabel,
    this.highlightQuery,
    this.isActiveSearchResult = false,
    this.isInactiveGridBreachInvite = false,
  });

  static const double _kBubbleWidthFactor = 0.78;
  static const double _kStickerMaxDim = 200;
  static const double _kChamferCut = 10.0;

  final ResolvedChatMessage message;
  final Color accent;
  final Widget? attachmentPreview;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onLongPress;
  final String? senderLabel;
  final String? replyPreviewText;
  final Widget? replyPreviewAttachment;
  final String? replyAuthorLabel;
  final bool isSelected;
  final VoidCallback? onReplySwipe;
  final String? cryptoStatusLabel;
  final String? highlightQuery;
  final bool isActiveSearchResult;
  final bool isInactiveGridBreachInvite;

  static const Color _textPrimary = Color(0xFFF0F0F8);
  static const Color _textSecondary = Color(0xFF8888AA);
  static const Color _surface = Color(0xFF12121E);
  static const Color _surface2 = Color(0xFF191926);

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final maxBubbleWidth =
        MediaQuery.sizeOf(context).width * _kBubbleWidthFactor;

    // Grid Breach handling
    if (message.kind == MessageKind.grid_breach) {
      return _GridBreachInvite(
        message: message,
        isGX: true,
        accent: accent,
        isInactive: isInactiveGridBreachInvite,
      );
    }

    final bubbleBg = isMine
        ? Color.alphaBlend(accent.withValues(alpha: 0.07), _surface)
        : _surface;
    final textColor = _textPrimary;
    final metaColor = _textSecondary;
    final itemAlignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final crossAxis = isMine
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final textAlign = isMine ? TextAlign.right : TextAlign.left;

    final effectiveHighlightQuery = highlightQuery?.trim() ?? '';
    final bodyText = message.previewText.trim();
    final shouldShowBodyText =
        bodyText.isNotEmpty &&
        !((message.kind == MessageKind.audio ||
                message.kind == MessageKind.sticker) &&
            attachmentPreview != null);

    final isSingleEmoji = _isTransparentSingleEmojiMessage(
      bodyText,
      attachmentPreview: attachmentPreview,
      replyPreviewText: replyPreviewText,
      senderLabel: senderLabel,
      hasLinkPreview: message.linkPreview != null,
      isViewOnce: message.isViewOnce,
      highlightQuery: effectiveHighlightQuery,
    );
    final isBubblelessSticker =
        message.kind == MessageKind.sticker &&
        attachmentPreview != null &&
        replyPreviewText == null &&
        senderLabel == null &&
        !message.isViewOnce &&
        message.linkPreview == null &&
        effectiveHighlightQuery.isEmpty;

    final useCompactWidth =
        isBubblelessSticker ||
        _shouldUseCompactBubbleWidth(
          bodyText,
          attachmentPreview: attachmentPreview,
          replyPreviewText: replyPreviewText,
          senderLabel: senderLabel,
          hasLinkPreview: message.linkPreview != null,
          isViewOnce: message.isViewOnce,
          highlightQuery: effectiveHighlightQuery,
          isSingleEmojiMessage: isSingleEmoji,
        );

    final bubblePadding = (isSingleEmoji || isBubblelessSticker)
        ? EdgeInsets.zero
        : useCompactWidth
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
        : const EdgeInsets.fromLTRB(14, 12, 14, 10);

    Widget alignItem(Widget child) =>
        Align(alignment: itemAlignment, widthFactor: 1, child: child);

    final replyContentMaxWidth =
        (maxBubbleWidth - (replyPreviewAttachment != null ? 60 : 0))
            .clamp(120.0, maxBubbleWidth)
            .toDouble();

    final bubbleBody = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxis,
        children: [
          // Sender label
          if (senderLabel != null) ...[
            alignItem(
              Text(
                senderLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Reply preview
          if (replyPreviewText != null) ...[
            alignItem(
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _surface2,
                  border: Border(left: BorderSide(color: accent, width: 2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (replyPreviewAttachment != null) ...[
                      replyPreviewAttachment!,
                      const SizedBox(width: 10),
                    ],
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: replyContentMaxWidth,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: crossAxis,
                        children: [
                          Text(
                            replyAuthorLabel ?? 'REPLY',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: textAlign,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            replyPreviewText!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: textAlign,
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // View once
          if (message.isViewOnce)
            alignItem(
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  message.isConsumed ? 'VIEW ONCE â€¢ CONSUMED' : 'VIEW ONCE',
                  textAlign: textAlign,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ),

          // Attachment
          if (attachmentPreview != null) ...[
            alignItem(
              message.kind == MessageKind.sticker
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _kStickerMaxDim,
                        maxHeight: _kStickerMaxDim,
                      ),
                      child: attachmentPreview!,
                    )
                  : attachmentPreview!,
            ),
            if (!isBubblelessSticker) const SizedBox(height: 10),
          ],

          // Link preview
          if (message.linkPreview != null) ...[
            alignItem(
              _GXUrlPreviewWidget(data: message.linkPreview!, accent: accent),
            ),
            const SizedBox(height: 10),
          ],

          // Body text
          if (shouldShowBodyText) ...[
            alignItem(
              isSingleEmoji
                  ? Text(
                      bodyText,
                      textAlign: textAlign,
                      style: const TextStyle(fontSize: 46, height: 1.0),
                    )
                  : effectiveHighlightQuery.isNotEmpty
                  ? HighlightedText(
                      text: message.previewText,
                      query: effectiveHighlightQuery,
                      textAlign: textAlign,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: textColor,
                        height: 1.45,
                      ),
                      highlightStyle: TextStyle(
                        fontSize: 14.5,
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        backgroundColor:
                            (isActiveSearchResult
                                    ? Colors.amber.shade400
                                    : Colors.amber.shade200)
                                .withValues(alpha: 0.55),
                      ),
                    )
                  : Linkify(
                      onOpen: (link) async {
                        final uri = Uri.tryParse(link.url);
                        if (uri != null) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      text: message.previewText,
                      textAlign: textAlign,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: textColor,
                        height: 1.45,
                      ),
                      linkStyle: TextStyle(
                        fontSize: 14.5,
                        color: accent,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            SizedBox(height: isSingleEmoji ? 4 : 8),
          ],

          // Meta row
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                DateHelper.formatBubbleTime(message.createdAt),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 0.6,
                  color: isSingleEmoji || isBubblelessSticker
                      ? _textSecondary
                      : metaColor,
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 6),
                _DeliveryIndicator(
                  state: message.deliveryState,
                  color: isSingleEmoji || isBubblelessSticker
                      ? _textSecondary
                      : accent,
                ),
              ],
            ],
          ),
        ],
      ),
    );

    // -- Shell ---------------------------------------------------------------
    final useGXChrome = !(isSingleEmoji || isBubblelessSticker);
    final glowOpacity = isSelected
        ? 0.9
        : isActiveSearchResult
        ? 0.7
        : isMine
        ? 0.45
        : 0.0;
    final borderAccent = isActiveSearchResult ? Colors.amber.shade600 : accent;

    Widget bubbleChild = GestureDetector(
      onLongPress: onLongPress,
      onTap: onAttachmentTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: useGXChrome
            ? CustomPaint(
                foregroundPainter: _ChamferBorderPainter(
                  accent: borderAccent,
                  cut: _kChamferCut,
                  borderWidth: isSelected || isActiveSearchResult ? 1.6 : 1.0,
                  glowOpacity: glowOpacity,
                ),
                child: Stack(
                  children: [
                    ClipPath(
                      clipper: const _ChamferClipper(cut: _kChamferCut),
                      child: Container(
                        color: bubbleBg,
                        padding: bubblePadding,
                        child: bubbleBody,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CircuitPainter(
                            accent: accent,
                            isMine: isMine,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Padding(padding: bubblePadding, child: bubbleBody),
      ),
    );

    final interactiveChild = onReplySwipe == null
        ? bubbleChild
        : _GXReplySwipeWrapper(
            messageId: message.id,
            onReplySwipe: onReplySwipe!,
            accent: accent,
            child: bubbleChild,
          );

    final statusChip = cryptoStatusLabel == null
        ? null
        : Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _surface,
              border: Border.all(
                color: accent.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Text(
              cryptoStatusLabel!.toUpperCase(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: _textSecondary,
              ),
            ),
          );

    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: isMine
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: crossAxis,
          children: [interactiveChild, if (statusChip != null) statusChip],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Grid Breach Invite
// -----------------------------------------------------------------------------

class _GridBreachInvite extends StatelessWidget {
  const _GridBreachInvite({
    required this.message,
    required this.isGX,
    this.accent = Colors.cyan,
    this.isInactive = false,
  });

  final ResolvedChatMessage message;
  final bool isGX;
  final Color accent;
  final bool isInactive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMine = message.isMine;
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final isDisabled = isInactive || message.gameMatchId == null;
    final cardAccent = isDisabled
        ? Colors.grey
        : (isGX ? accent : theme.colorScheme.primary);
    final bodyColor = isDisabled ? Colors.white54 : Colors.white70;

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        width: 220,
        decoration: isGX
            ? BoxDecoration(
                color: isDisabled
                    ? const Color(0xFF111216)
                    : const Color(0xFF0B0B14),
                border: Border.all(color: accent, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: cardAccent.withValues(
                      alpha: isDisabled ? 0.08 : 0.3,
                    ),
                    blurRadius: 12,
                  ),
                ],
              )
            : BoxDecoration(
                color: isDisabled
                    ? theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.72,
                      )
                    : theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Icon(Icons.grid_on_rounded, color: accent, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'GRID BREACH GX',
                    style: isGX
                        ? TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: accent,
                          )
                        : theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDisabled
                        ? 'Challenge expired'
                        : isMine
                        ? 'Waiting for breach...'
                        : 'Incoming breach attempt!',
                    style: isGX
                        ? TextStyle(fontSize: 10, color: bodyColor)
                        : theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isGX ? cardAccent.withValues(alpha: 0.5) : null,
            ),
            InkWell(
              onTap: isDisabled
                  ? null
                  : () {
                      final matchId = message.gameMatchId;
                      if (matchId != null) {
                        context.push('/chat/game/$matchId');
                      }
                    },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Text(
                  isDisabled
                      ? 'EXPIRED'
                      : isMine
                      ? 'RESUME'
                      : 'ACCEPT BREACH',
                  style: isGX
                      ? TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: accent,
                        )
                      : TextStyle(fontWeight: FontWeight.bold, color: accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared delivery indicator
// -----------------------------------------------------------------------------

class _DeliveryIndicator extends StatelessWidget {
  const _DeliveryIndicator({required this.state, required this.color});

  final MessageDeliveryState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case MessageDeliveryState.sending:
        return SizedBox(
          width: 14,
          height: 14,
          child: _PendingClockIcon(color: color),
        );
      case MessageDeliveryState.sent:
        return Icon(Icons.check_rounded, size: 15, color: color);
      case MessageDeliveryState.delivered:
      case MessageDeliveryState.read:
        return Icon(Icons.done_all_rounded, size: 15, color: color);
      case MessageDeliveryState.consumed:
        return Icon(Icons.visibility_off_rounded, size: 15, color: color);
      case MessageDeliveryState.failed:
        return Icon(Icons.error_outline_rounded, size: 15, color: color);
    }
  }
}

class _PendingClockIcon extends StatefulWidget {
  const _PendingClockIcon({required this.color});
  final Color color;

  @override
  State<_PendingClockIcon> createState() => _PendingClockIconState();
}

class _PendingClockIconState extends State<_PendingClockIcon>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => setState(() => _elapsed = e))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ClockPainter(color: widget.color, elapsed: _elapsed),
  );
}

class _ClockPainter extends CustomPainter {
  const _ClockPainter({required this.color, required this.elapsed});
  final Color color;
  final Duration elapsed;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;
    canvas.drawCircle(center, radius, stroke);
    final t = elapsed.inMicroseconds / 1000000.0;
    final minA = (t * 0.65 % 1.0) * 2 * math.pi;
    final hrA = (t * 0.65 / 2.5 % 1.0) * 2 * math.pi;
    _hand(canvas, center, radius * 0.45, hrA, stroke);
    _hand(canvas, center, radius * 0.65, minA, stroke);
    canvas.drawCircle(center, 1.2, fill);
  }

  void _hand(Canvas canvas, Offset c, double len, double angle, Paint p) =>
      canvas.drawLine(
        c,
        Offset(c.dx + len * math.sin(angle), c.dy - len * math.cos(angle)),
        p,
      );

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.elapsed != elapsed || old.color != color;
}

// -----------------------------------------------------------------------------
// GX URL preview
// -----------------------------------------------------------------------------

class _GXUrlPreviewWidget extends StatelessWidget {
  const _GXUrlPreviewWidget({required this.data, required this.accent});

  final LinkPreviewData data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(data.url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: CustomPaint(
        foregroundPainter: _ChamferBorderPainter(
          accent: accent,
          cut: 8,
          borderWidth: 0.8,
          glowOpacity: 0.3,
        ),
        child: ClipPath(
          clipper: const _ChamferClipper(cut: 8),
          child: Container(
            color: const Color(0xFF191926),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data.imageUrl != null)
                  LayoutBuilder(
                    builder: (ctx, c) => Image.network(
                      data.imageUrl!,
                      height: 150,
                      width: c.maxWidth.isFinite ? c.maxWidth : 260,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: accent, width: 2)),
                  ),
                  padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (data.title != null)
                        Text(
                          data.title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF0F0F8),
                          ),
                        ),
                      if (data.description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          data.description!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFAAAAAA),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        Uri.parse(data.url).host.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          letterSpacing: 1.1,
                          color: accent.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
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

// -----------------------------------------------------------------------------
// Normal URL preview (original)
// -----------------------------------------------------------------------------

class _UrlPreviewWidget extends StatelessWidget {
  const _UrlPreviewWidget({
    required this.data,
    required this.backgroundColor,
    required this.textColor,
  });

  final LinkPreviewData data;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        final uri = Uri.tryParse(data.url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data.imageUrl != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final imageWidth = constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : 260.0;
                  return Image.network(
                    data.imageUrl!,
                    height: 160,
                    width: imageWidth,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  );
                },
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (data.title != null)
                    Text(
                      data.title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (data.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      data.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    Uri.parse(data.url).host,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: textColor.withValues(alpha: 0.5),
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
}

// -----------------------------------------------------------------------------
// Reply swipe wrappers
// -----------------------------------------------------------------------------

class _NormalReplySwipeWrapper extends StatefulWidget {
  const _NormalReplySwipeWrapper({
    required this.messageId,
    required this.onReplySwipe,
    required this.child,
  });

  final String messageId;
  final VoidCallback onReplySwipe;
  final Widget child;

  @override
  State<_NormalReplySwipeWrapper> createState() =>
      _NormalReplySwipeWrapperState();
}

class _NormalReplySwipeWrapperState extends State<_NormalReplySwipeWrapper> {
  static const double _maxOffset = 72;
  static const double _triggerOffset = 46;
  static const double _iconRevealOffset = 24;
  double _dragOffset = 0;

  void _onUpdate(DragUpdateDetails d) {
    final next = (_dragOffset + d.delta.dx).clamp(0.0, _maxOffset);
    if (next != _dragOffset) setState(() => _dragOffset = next);
  }

  void _onEnd(DragEndDetails _) {
    final should = _dragOffset >= _triggerOffset;
    setState(() => _dragOffset = 0);
    if (should) widget.onReplySwipe();
  }

  void _onCancel() {
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_dragOffset / _iconRevealOffset).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onCancel,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 14,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: progress,
                child: Transform.scale(
                  scale: 0.88 + 0.12 * progress,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.reply_rounded,
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _GXReplySwipeWrapper extends StatefulWidget {
  const _GXReplySwipeWrapper({
    required this.messageId,
    required this.onReplySwipe,
    required this.child,
    required this.accent,
  });

  final String messageId;
  final VoidCallback onReplySwipe;
  final Widget child;
  final Color accent;

  @override
  State<_GXReplySwipeWrapper> createState() => _GXReplySwipeWrapperState();
}

class _GXReplySwipeWrapperState extends State<_GXReplySwipeWrapper> {
  static const double _maxOffset = 72;
  static const double _triggerOffset = 46;
  static const double _iconRevealOffset = 24;
  double _dragOffset = 0;

  void _onUpdate(DragUpdateDetails d) {
    final next = (_dragOffset + d.delta.dx).clamp(0.0, _maxOffset);
    if (next != _dragOffset) setState(() => _dragOffset = next);
  }

  void _onEnd(DragEndDetails _) {
    final should = _dragOffset >= _triggerOffset;
    setState(() => _dragOffset = 0);
    if (should) widget.onReplySwipe();
  }

  void _onCancel() {
    if (_dragOffset != 0) setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragOffset / _iconRevealOffset).clamp(0.0, 1.0);
    final accent = widget.accent;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onCancel,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 14,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: progress,
                child: Transform.scale(
                  scale: 0.88 + 0.12 * progress,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.5),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(Icons.reply_rounded, color: accent, size: 16),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// GX painters
// -----------------------------------------------------------------------------

class _ChamferClipper extends CustomClipper<Path> {
  const _ChamferClipper({this.cut = 10});
  final double cut;

  @override
  Path getClip(Size size) {
    final c = cut;
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width - c, 0)
      ..lineTo(size.width, c)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(c, size.height)
      ..lineTo(0, size.height - c)
      ..lineTo(0, c)
      ..close();
  }

  @override
  bool shouldReclip(_ChamferClipper old) => old.cut != cut;
}

class _ChamferBorderPainter extends CustomPainter {
  const _ChamferBorderPainter({
    required this.accent,
    required this.cut,
    this.borderWidth = 1.2,
    this.glowOpacity = 0.0,
  });

  final Color accent;
  final double cut;
  final double borderWidth;
  final double glowOpacity;

  Path _path(Size size) {
    final c = cut;
    return Path()
      ..moveTo(c, 0)
      ..lineTo(size.width - c, 0)
      ..lineTo(size.width, c)
      ..lineTo(size.width, size.height - c)
      ..lineTo(size.width - c, size.height)
      ..lineTo(c, size.height)
      ..lineTo(0, size.height - c)
      ..lineTo(0, c)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    if (glowOpacity > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: glowOpacity * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth + 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(_ChamferBorderPainter old) =>
      old.accent != accent ||
      old.cut != cut ||
      old.glowOpacity != glowOpacity ||
      old.borderWidth != borderWidth;
}

class _CircuitPainter extends CustomPainter {
  const _CircuitPainter({required this.accent, required this.isMine});

  final Color accent;
  final bool isMine;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final dot = Paint()
      ..color = accent.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    if (isMine) {
      final x = size.width - 2;
      final y = size.height - 2;
      canvas.drawLine(Offset(x - 16, y), Offset(x - 4, y), paint);
      canvas.drawLine(Offset(x - 4, y), Offset(x - 4, y - 8), paint);
      canvas.drawCircle(Offset(x - 4, y - 8), 1.5, dot);
      canvas.drawLine(Offset(x - 16, y), Offset(x - 16, y - 4), paint);
      canvas.drawCircle(Offset(x - 16, y - 4), 1.5, dot);
    } else {
      const x = 2.0;
      final y = size.height - 2;
      canvas.drawLine(Offset(x + 16, y), Offset(x + 4, y), paint);
      canvas.drawLine(Offset(x + 4, y), Offset(x + 4, y - 8), paint);
      canvas.drawCircle(Offset(x + 4, y - 8), 1.5, dot);
      canvas.drawLine(Offset(x + 16, y), Offset(x + 16, y - 4), paint);
      canvas.drawCircle(Offset(x + 16, y - 4), 1.5, dot);
    }
  }

  @override
  bool shouldRepaint(_CircuitPainter old) =>
      old.accent != accent || old.isMine != isMine;
}

// -----------------------------------------------------------------------------
// Shared helper functions
// -----------------------------------------------------------------------------

Color _outgoingPreviewBackground(Color bubbleColor, Brightness brightness) {
  final overlay = (brightness == Brightness.dark ? Colors.white : Colors.black)
      .withValues(alpha: brightness == Brightness.dark ? 0.12 : 0.06);
  return Color.alphaBlend(overlay, bubbleColor);
}

Color _outgoingBorderColor(
  Color bubbleColor,
  Color textColor,
  Brightness brightness, {
  bool emphasized = false,
}) {
  final overlay = textColor.withValues(
    alpha: emphasized
        ? (brightness == Brightness.dark ? 0.28 : 0.18)
        : (brightness == Brightness.dark ? 0.16 : 0.10),
  );
  return Color.alphaBlend(overlay, bubbleColor);
}

Color _outgoingSearchBorderColor(Color bubbleColor, Brightness brightness) {
  final accent =
      (brightness == Brightness.dark
              ? Colors.amber.shade200
              : Colors.amber.shade700)
          .withValues(alpha: 0.34);
  return Color.alphaBlend(accent, bubbleColor);
}

bool _shouldUseCompactBubbleWidth(
  String bodyText, {
  required Widget? attachmentPreview,
  required String? replyPreviewText,
  required String? senderLabel,
  required bool hasLinkPreview,
  required bool isViewOnce,
  required String highlightQuery,
  required bool isSingleEmojiMessage,
}) {
  if (isSingleEmojiMessage) return true;
  if (attachmentPreview != null ||
      replyPreviewText != null ||
      senderLabel != null ||
      hasLinkPreview ||
      isViewOnce ||
      highlightQuery.isNotEmpty) {
    return false;
  }
  final trimmed = bodyText.trim();
  if (trimmed.isEmpty || trimmed.contains('\n')) return false;
  return trimmed.runes.length <= 16;
}

bool _isTransparentSingleEmojiMessage(
  String bodyText, {
  required Widget? attachmentPreview,
  required String? replyPreviewText,
  required String? senderLabel,
  required bool hasLinkPreview,
  required bool isViewOnce,
  required String highlightQuery,
}) {
  if (attachmentPreview != null ||
      replyPreviewText != null ||
      senderLabel != null ||
      hasLinkPreview ||
      isViewOnce ||
      highlightQuery.isNotEmpty) {
    return false;
  }
  return _isSingleEmoji(bodyText);
}

bool _isSingleEmoji(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return false;
  var emojiBaseCount = 0;
  for (final cp in trimmed.runes) {
    if (_isEmojiBaseCodePoint(cp)) {
      emojiBaseCount += 1;
      continue;
    }
    if (_isEmojiModifierCodePoint(cp)) continue;
    return false;
  }
  return emojiBaseCount == 1;
}

bool _isEmojiBaseCodePoint(int cp) =>
    cp == 0x00A9 ||
    cp == 0x00AE ||
    cp == 0x203C ||
    cp == 0x2049 ||
    cp == 0x2122 ||
    cp == 0x2139 ||
    (cp >= 0x2194 && cp <= 0x21AA) ||
    (cp >= 0x231A && cp <= 0x27BF) ||
    (cp >= 0x1F000 && cp <= 0x1FAFF);

bool _isEmojiModifierCodePoint(int cp) =>
    cp == 0x200D ||
    cp == 0xFE0E ||
    cp == 0xFE0F ||
    cp == 0x20E3 ||
    (cp >= 0x1F3FB && cp <= 0x1F3FF) ||
    (cp >= 0xE0020 && cp <= 0xE007F);
