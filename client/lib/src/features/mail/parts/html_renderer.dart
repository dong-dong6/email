part of '../mail_home_screen.dart';

String _sanitizeMailHtml(String html) {
  var value = html.trim();
  if (value.isEmpty) {
    return '';
  }
  value = value.replaceAll(
      RegExp(
          r'<\s*(script|style|iframe|object|embed|form)\b[^>]*>.*?<\s*/\s*\1\s*>',
          caseSensitive: false,
          dotAll: true),
      '');
  value = value.replaceAll(
      RegExp(r'<\s*(script|style|iframe|object|embed|form)\b[^>]*/?\s*>',
          caseSensitive: false),
      '');
  value = value.replaceAll(
      RegExp(r"<img\b[^>]*\bsrc\s*=\s*[" "']https?:[^>]*>",
          caseSensitive: false),
      '');
  value = value.replaceAll(
      RegExp(r"\son[a-z]+\s*=\s*([" "']).*?\1",
          caseSensitive: false, dotAll: true),
      '');
  value = value.replaceAll(
      RegExp(r"\s(href|src)\s*=\s*([" "'])\s*javascript:.*?\2",
          caseSensitive: false, dotAll: true),
      '');
  return value.trim();
}

List<Widget> _htmlNodeToWidgets(
  BuildContext context,
  dom.Node node,
  TextStyle style,
) {
  final scheme = Theme.of(context).colorScheme;
  if (node is dom.Text) {
    final text = _softWrapLongRuns(node.text.replaceAll(RegExp(r'\s+'), ' '));
    if (text.trim().isEmpty) {
      return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SelectableText(text.trim(), style: style),
      ),
    ];
  }
  if (node is! dom.Element) {
    return const [];
  }
  final tag = node.localName?.toLowerCase() ?? '';
  final align = _htmlAlignment(node);
  final children = () => [
        for (final child in node.nodes)
          ..._htmlNodeToWidgets(context, child, style),
      ];
  switch (tag) {
    case 'br':
      return const [SizedBox(height: 8)];
    case 'img':
      return [_HtmlImagePlaceholder(element: node)];
    case 'a':
      final href = node.attributes['href']?.trim() ?? '';
      return [
        Align(
          alignment: align,
          child: _HtmlLinkChip(
            text: _plainText(node).isEmpty ? href : _plainText(node),
            href: href,
          ),
        ),
        const SizedBox(height: 12),
      ];
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
      return [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 10),
          child: Align(
            alignment: align,
            child: SelectableText.rich(
              TextSpan(
                style: style.copyWith(
                  fontSize: switch (tag) {
                    'h1' => 26,
                    'h2' => 22,
                    'h3' => 19,
                    _ => 17,
                  },
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
                children: _htmlInlineSpans(context, node.nodes, style),
              ),
            ),
          ),
        ),
      ];
    case 'p':
    case 'div':
    case 'section':
    case 'article':
    case 'main':
    case 'header':
    case 'footer':
    case 'blockquote':
      if (_hasBlockChildren(node)) {
        return [
          Padding(
            padding: _htmlBlockPadding(tag),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children(),
            ),
          ),
        ];
      }
      final spans = _htmlInlineSpans(context, node.nodes, style);
      if (_isBlankSpans(spans)) {
        return const [SizedBox(height: 10)];
      }
      return [
        Padding(
          padding: _htmlBlockPadding(tag),
          child: Align(
            alignment: align,
            child: SelectableText.rich(
              TextSpan(style: style, children: spans),
              textAlign: _htmlTextAlign(node),
            ),
          ),
        ),
      ];
    case 'ul':
    case 'ol':
      return [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < node.children.length; index++)
                _HtmlListItem(
                  marker: tag == 'ol' ? '${index + 1}.' : '-',
                  element: node.children[index],
                  style: style,
                ),
            ],
          ),
        ),
      ];
    case 'table':
      return [_HtmlTable(element: node, baseStyle: style)];
    case 'tbody':
    case 'thead':
    case 'tfoot':
      return children();
    case 'center':
      return [
        Align(
          alignment: Alignment.center,
          child: Column(children: children()),
        ),
      ];
    default:
      if (_hasBlockChildren(node)) {
        return children();
      }
      final spans = _htmlInlineSpans(context, node.nodes, style);
      if (_isBlankSpans(spans)) {
        return const [];
      }
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SelectableText.rich(TextSpan(style: style, children: spans)),
        ),
      ];
  }
}

List<InlineSpan> _htmlInlineSpans(
  BuildContext context,
  List<dom.Node> nodes,
  TextStyle style,
) {
  final linkColor = Theme.of(context).colorScheme.primary;
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    spans.addAll(_htmlNodeToInlineSpans(node, style, linkColor));
  }
  return _trimTrailingBreaks(spans);
}

List<InlineSpan> _htmlNodeToInlineSpans(
  dom.Node node,
  TextStyle style,
  Color linkColor,
) {
  if (node is dom.Text) {
    final text = _softWrapLongRuns(node.text.replaceAll(RegExp(r'\s+'), ' '));
    if (text.trim().isEmpty) {
      return const [];
    }
    return [TextSpan(text: text, style: style)];
  }
  if (node is! dom.Element) {
    return const [];
  }
  final tag = node.localName?.toLowerCase() ?? '';
  switch (tag) {
    case 'br':
      return const [TextSpan(text: '\n')];
    case 'img':
      final alt = node.attributes['alt']?.trim();
      return [
        TextSpan(
          text: alt == null || alt.isEmpty
              ? '[图片]'
              : '[图片: ${_softWrapLongRuns(alt)}]',
          style: style.copyWith(color: linkColor),
        ),
      ];
    case 'strong':
    case 'b':
      return _htmlChildrenToInlineSpans(
          node, style.copyWith(fontWeight: FontWeight.w700), linkColor);
    case 'em':
    case 'i':
      return _htmlChildrenToInlineSpans(
          node, style.copyWith(fontStyle: FontStyle.italic), linkColor);
    case 'u':
      return _htmlChildrenToInlineSpans(node,
          style.copyWith(decoration: TextDecoration.underline), linkColor);
    case 'code':
      return _htmlChildrenToInlineSpans(
          node,
          style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: const Color(0x14000000),
          ),
          linkColor);
    case 'a':
      final href = node.attributes['href']?.trim() ?? '';
      final label = _plainText(node).trim();
      final text = label.isEmpty ? href : label;
      if (text.isEmpty) {
        return const [];
      }
      return [
        TextSpan(
          text: _softWrapLongRuns(text),
          style: style.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
        ),
      ];
    case 'span':
      return _htmlChildrenToInlineSpans(
          node, _styleFromHtml(node, style), linkColor);
    default:
      return _htmlChildrenToInlineSpans(node, style, linkColor);
  }
}

List<InlineSpan> _htmlChildrenToInlineSpans(
  dom.Element element,
  TextStyle style,
  Color linkColor,
) {
  return [
    for (final child in element.nodes)
      ..._htmlNodeToInlineSpans(child, style, linkColor),
  ];
}

class _HtmlLinkChip extends StatelessWidget {
  const _HtmlLinkChip({required this.text, required this.href});

  final String text;
  final String href;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = text.trim().isEmpty ? href : text.trim();
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_rounded, color: scheme.primary, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: SelectableText(
              _softWrapLongRuns(label),
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HtmlImagePlaceholder extends StatelessWidget {
  const _HtmlImagePlaceholder({required this.element});

  final dom.Element element;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alt = element.attributes['alt']?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.image_not_supported_outlined,
                color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                alt.isEmpty ? '远程图片已阻止' : '远程图片已阻止：$alt',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HtmlListItem extends StatelessWidget {
  const _HtmlListItem({
    required this.marker,
    required this.element,
    required this.style,
  });

  final String marker;
  final dom.Element element;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, child: Text(marker, style: style)),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                style: style,
                children: _htmlInlineSpans(context, element.nodes, style),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HtmlTable extends StatelessWidget {
  const _HtmlTable({required this.element, required this.baseStyle});

  final dom.Element element;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final rows = element.querySelectorAll('tr');
    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in element.nodes)
            ..._htmlNodeToWidgets(context, child, baseStyle),
        ],
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: scheme.outlineVariant),
          children: [
            for (final row in rows)
              TableRow(
                children: [
                  for (final cell in row.children.where((item) =>
                      item.localName == 'td' || item.localName == 'th'))
                    Container(
                      constraints: const BoxConstraints(minWidth: 96),
                      padding: const EdgeInsets.all(10),
                      color: cell.localName == 'th'
                          ? scheme.surfaceContainerHighest
                          : null,
                      child: SelectableText.rich(
                        TextSpan(
                          style: baseStyle.copyWith(
                            fontWeight:
                                cell.localName == 'th' ? FontWeight.w700 : null,
                          ),
                          children:
                              _htmlInlineSpans(context, cell.nodes, baseStyle),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

bool _hasBlockChildren(dom.Element element) {
  const blockTags = {
    'address',
    'article',
    'aside',
    'blockquote',
    'center',
    'div',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'header',
    'li',
    'main',
    'ol',
    'p',
    'section',
    'table',
    'ul',
  };
  return element.children.any((child) => blockTags.contains(child.localName));
}

bool _isBlankSpans(List<InlineSpan> spans) {
  return spans
      .every((span) => span is TextSpan && (span.text ?? '').trim().isEmpty);
}

String _plainText(dom.Element element) {
  return element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Alignment _htmlAlignment(dom.Element element) {
  return switch (_htmlTextAlign(element)) {
    TextAlign.center => Alignment.center,
    TextAlign.right || TextAlign.end => Alignment.centerRight,
    _ => Alignment.centerLeft,
  };
}

TextAlign _htmlTextAlign(dom.Element element) {
  final align =
      '${element.attributes['align'] ?? ''} ${element.attributes['style'] ?? ''}'
          .toLowerCase();
  if (align.contains('center')) {
    return TextAlign.center;
  }
  if (align.contains('right')) {
    return TextAlign.right;
  }
  return TextAlign.start;
}

EdgeInsets _htmlBlockPadding(String tag) {
  return switch (tag) {
    'blockquote' => const EdgeInsets.fromLTRB(16, 4, 0, 14),
    'div' ||
    'section' ||
    'article' ||
    'main' ||
    'header' ||
    'footer' =>
      const EdgeInsets.only(bottom: 8),
    _ => const EdgeInsets.only(bottom: 14),
  };
}

TextStyle _styleFromHtml(dom.Element element, TextStyle base) {
  final style = element.attributes['style']?.toLowerCase() ?? '';
  var out = base;
  if (style.contains('font-weight:bold') ||
      style.contains('font-weight: bold')) {
    out = out.copyWith(fontWeight: FontWeight.w700);
  }
  if (style.contains('font-style:italic') ||
      style.contains('font-style: italic')) {
    out = out.copyWith(fontStyle: FontStyle.italic);
  }
  return out;
}

String _selectedFolderTitle(AppState state) {
  final folder = state.selectedFolder;
  return folder == null ? '收件箱' : _folderDisplayName(folder);
}

String _softWrapLongRuns(String value) {
  const chunkSize = 48;
  return value.splitMapJoin(
    RegExp(r'\S{' '$chunkSize' r',}'),
    onMatch: (match) {
      final text = match.group(0) ?? '';
      final buffer = StringBuffer();
      for (var index = 0; index < text.length; index += chunkSize) {
        if (index > 0) {
          buffer.write('\u200B');
        }
        final end = (index + chunkSize).clamp(0, text.length);
        buffer.write(text.substring(index, end));
      }
      return buffer.toString();
    },
    onNonMatch: (text) => text,
  );
}

List<InlineSpan> _trimTrailingBreaks(List<InlineSpan> spans) {
  final out = [...spans];
  while (out.isNotEmpty) {
    final last = out.last;
    if (last is TextSpan && (last.text ?? '').trim().isEmpty) {
      out.removeLast();
      continue;
    }
    break;
  }
  return out;
}
