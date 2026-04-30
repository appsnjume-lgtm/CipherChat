import 'package:flutter/material.dart';

class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: buildHighlightedTextSpans(
          text: text,
          query: query,
          style: style,
          highlightStyle:
              highlightStyle ??
              style?.copyWith(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.22),
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

List<InlineSpan> buildHighlightedTextSpans({
  required String text,
  required String query,
  TextStyle? style,
  TextStyle? highlightStyle,
}) {
  if (text.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: style)];
  }

  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: style)];
  }

  final lowerText = text.toLowerCase();
  final lowerQuery = trimmedQuery.toLowerCase();
  final spans = <InlineSpan>[];
  var start = 0;

  while (start < text.length) {
    final matchIndex = lowerText.indexOf(lowerQuery, start);
    if (matchIndex < 0) {
      spans.add(TextSpan(text: text.substring(start), style: style));
      break;
    }

    if (matchIndex > start) {
      spans.add(
        TextSpan(text: text.substring(start, matchIndex), style: style),
      );
    }

    spans.add(
      TextSpan(
        text: text.substring(matchIndex, matchIndex + trimmedQuery.length),
        style: highlightStyle ?? style,
      ),
    );
    start = matchIndex + trimmedQuery.length;
  }

  return spans;
}
