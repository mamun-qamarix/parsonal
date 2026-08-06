import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Matches http(s):// links and bare www.-prefixed ones. Deliberately NOT
/// matching arbitrary bare domains (e.g. "কথা.com") -- too easy to
/// false-positive on ordinary text that just happens to contain a dot.
final RegExp _urlRegex = RegExp(
  r'(https?:\/\/[^\s]+)|(www\.[^\s]+)',
  caseSensitive: false,
);

// Trailing characters that are almost always sentence punctuation rather
// than part of the URL itself (a link at the end of a sentence, in
// parentheses, in quotes, etc.) -- stripped before actually opening it.
const _trailingPunctuation = '.,!?;:)]}”’"\'';

/// Renders [text] with any link inside it picked out in blue and made
/// tappable -- opens in the phone's browser. Used everywhere user-written
/// text shows (chat, vault captions, comments, wishlist, phrases, Reel
/// captions) so a shared link is never just inert text. See DECISIONS.md.
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color? linkColor;
  final int? maxLines;
  final TextOverflow? overflow;
  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.linkColor,
    this.maxLines,
    this.overflow,
  });

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  Future<void> _open(String rawUrl) async {
    var url = rawUrl;
    while (url.isNotEmpty && _trailingPunctuation.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing sensible to show the user for a failed launch (no browser,
      // malformed link, etc.) -- silently ignore rather than crash.
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final matches = _urlRegex.allMatches(widget.text);
    if (matches.isEmpty) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final linkColor = widget.linkColor ?? Colors.lightBlueAccent;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      }
      final linkText = widget.text.substring(m.start, m.end);
      final recognizer = TapGestureRecognizer()..onTap = () => _open(linkText);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: linkText,
          style: TextStyle(color: linkColor, decoration: TextDecoration.underline),
          recognizer: recognizer,
        ),
      );
      last = m.end;
    }
    if (last < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(last)));
    }

    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }
}
