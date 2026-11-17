import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'markdown.dart';

const _safeSchemes = {'http', 'https', 'mailto', 'tel'};

/// Opens a link from a document, but only well-known schemes: a document
/// must not be able to launch arbitrary app intents.
Future<bool> openDocumentLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !_safeSchemes.contains(uri.scheme)) {
    return Future.value(false);
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Shows parsed Markdown as formatted, selectable text.
class MarkdownView extends StatefulWidget {
  const MarkdownView(
    this.source, {
    super.key,
    this.padding = const EdgeInsets.all(20),
  });
  final String source;
  final EdgeInsets padding;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TextSpan _spans(String text, TextStyle base, ColorScheme scheme) {
    return TextSpan(
      style: base,
      children: [
        for (final s in parseInline(text))
          TextSpan(
            text: s.text,
            recognizer: s.link == null
                ? null
                : (TapGestureRecognizer()
                    ..onTap = () => openDocumentLink(s.link!)),
            style: TextStyle(
              fontWeight: s.bold ? FontWeight.w700 : null,
              fontStyle: s.italic ? FontStyle.italic : null,
              fontFamily: s.code ? 'monospace' : null,
              backgroundColor: s.code ? scheme.surfaceContainerHighest : null,
              decoration: s.strike
                  ? TextDecoration.lineThrough
                  : s.link != null
                  ? TextDecoration.underline
                  : null,
              color: s.link != null ? scheme.primary : null,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final body = (theme.bodyLarge ?? const TextStyle()).copyWith(height: 1.5);
    final blocks = parseMarkdown(widget.source);

    // Recognisers made while building are tracked so they can be released.
    TextSpan rich(String t, TextStyle style) {
      final span = _spans(t, style, scheme);
      for (final c in span.children!) {
        final r = (c as TextSpan).recognizer;
        if (r is TapGestureRecognizer) _recognizers.add(r);
      }
      return span;
    }

    if (blocks.isEmpty) {
      return Center(
        child: Text(
          'Rien à afficher',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return SelectionArea(
      child: ListView(
        padding: widget.padding,
        children: [
          for (final b in blocks)
            switch (b) {
              Heading() => Padding(
                padding: EdgeInsets.only(top: b.level == 1 ? 8 : 14, bottom: 8),
                child: Text.rich(
                  rich(
                    b.text,
                    switch (b.level) {
                      1 => theme.headlineMedium!,
                      2 => theme.titleLarge!,
                      _ => theme.titleMedium!,
                    }.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                  ),
                ),
              ),
              Paragraph() => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text.rich(rich(b.text, body)),
              ),
              ListItem() => Padding(
                padding: EdgeInsets.only(left: b.indent * 20.0, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: b.checked != null
                          ? Icon(
                              b.checked!
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 20,
                              color: b.checked!
                                  ? scheme.primary
                                  : scheme.outline,
                            )
                          : Text(
                              b.number != null ? '${b.number}.' : '•',
                              style: body.copyWith(fontWeight: FontWeight.w700),
                            ),
                    ),
                    Expanded(
                      child: Text.rich(
                        rich(
                          b.text,
                          b.checked == true
                              ? body.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                  color: scheme.onSurfaceVariant,
                                )
                              : body,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Quote() => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.only(left: 14),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: scheme.primary, width: 3),
                  ),
                ),
                child: Text.rich(
                  rich(
                    b.text,
                    body.copyWith(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              CodeBlock() => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  b.code,
                  style: body.copyWith(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              Rule() => const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(),
              ),
            },
        ],
      ),
    );
  }
}
