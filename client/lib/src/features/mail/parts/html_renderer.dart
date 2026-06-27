part of '../mail_home_screen.dart';

String _sanitizeMailHtml(String html) {
  var value = html.trim();
  if (value.isEmpty) {
    return '';
  }
  value = value.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  value = value.replaceAll(
      RegExp(
          r'<\s*(script|style|head|iframe|object|embed|form)\b[^>]*>.*?<\s*/\s*\1\s*>',
          caseSensitive: false,
          dotAll: true),
      '');
  value = value.replaceAll(
      RegExp(
          r'<\s*(script|style|meta|link|iframe|object|embed|form)\b[^>]*/?\s*>',
          caseSensitive: false),
      '');
  value =
      value.replaceAll(RegExp(r'<\s*img\b[^>]*>', caseSensitive: false), '');
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
    final text = _readableTextNode(node.text);
    if (text.isEmpty) {
      return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SelectableText(_softWrapLongRuns(text), style: style),
      ),
    ];
  }
  if (node is! dom.Element) {
    return const [];
  }
  if (_isHiddenHtml(node)) {
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
      return const [];
    case 'a':
      final spans = _htmlInlineSpans(context, node.nodes, style);
      if (_isBlankSpans(spans)) {
        return const [];
      }
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Align(
            alignment: align,
            child: SelectableText.rich(
              TextSpan(style: style, children: spans),
              textAlign: _htmlTextAlign(node),
            ),
          ),
        ),
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
        return const [];
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
      return _htmlTableToWidgets(context, node, style);
    case 'tr':
      return _htmlTableRowToWidgets(context, node, style);
    case 'td':
    case 'th':
      return _htmlTableCellToWidgets(context, node, style);
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
    final text = _readableTextNode(node.text, trim: false);
    if (text.isEmpty) {
      return const [];
    }
    return [TextSpan(text: _softWrapLongRuns(text), style: style)];
  }
  if (node is! dom.Element) {
    return const [];
  }
  if (_isHiddenHtml(node)) {
    return const [];
  }
  final tag = node.localName?.toLowerCase() ?? '';
  switch (tag) {
    case 'br':
      return const [TextSpan(text: '\n')];
    case 'img':
      return const [];
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
      final text = _readableLinkText(label, href);
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

List<Widget> _htmlTableToWidgets(
  BuildContext context,
  dom.Element element,
  TextStyle style,
) {
  if (_isDataTable(element)) {
    return [_HtmlTable(element: element, baseStyle: style)];
  }
  return [_HtmlLayoutTable(element: element, baseStyle: style)];
}

List<Widget> _htmlTableRowToWidgets(
  BuildContext context,
  dom.Element row,
  TextStyle style,
) {
  if (_isHiddenHtml(row)) {
    return const [];
  }
  final cells = row.children
      .where((item) => item.localName == 'td' || item.localName == 'th')
      .toList(growable: false);
  if (cells.isEmpty) {
    return [
      for (final child in row.nodes)
        ..._htmlNodeToWidgets(context, child, style),
    ];
  }
  return [
    for (final cell in cells) ..._htmlTableCellToWidgets(context, cell, style),
  ];
}

List<Widget> _htmlTableCellToWidgets(
  BuildContext context,
  dom.Element cell,
  TextStyle style,
) {
  if (_isHiddenHtml(cell)) {
    return const [];
  }
  return [
    for (final child in cell.nodes)
      ..._htmlNodeToWidgets(context, child, style),
  ];
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
    final rows = [
      for (final row in element.querySelectorAll('tr'))
        row.children
            .where((item) => item.localName == 'td' || item.localName == 'th')
            .toList(growable: false),
    ].where((cells) => cells.isNotEmpty).toList(growable: false);
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
            for (final cells in rows)
              TableRow(
                children: [
                  for (final cell in cells)
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

class _HtmlLayoutTable extends StatelessWidget {
  const _HtmlLayoutTable({required this.element, required this.baseStyle});

  final dom.Element element;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final rows = _htmlLayoutRows(element)
        .map((row) => row.where(_nodeHasReadableContent).toList())
        .where((row) => row.isNotEmpty)
        .toList(growable: false);
    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in element.nodes)
            ..._htmlNodeToWidgets(context, child, baseStyle),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: _htmlAlignment(element),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = _htmlPreferredWidth(element, constraints.maxWidth);
            final table = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows)
                  _HtmlLayoutRow(cells: row, baseStyle: baseStyle),
              ],
            );
            if (width == null) {
              return table;
            }
            return SizedBox(width: width, child: table);
          },
        ),
      ),
    );
  }
}

class _HtmlLayoutRow extends StatelessWidget {
  const _HtmlLayoutRow({required this.cells, required this.baseStyle});

  final List<dom.Element> cells;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    if (cells.length == 1) {
      return _HtmlLayoutCell(cell: cells.single, baseStyle: baseStyle);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = constraints.maxWidth < 360;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final cell in cells)
                _HtmlLayoutCell(cell: cell, baseStyle: baseStyle),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < cells.length; index++) ...[
                if (index > 0) const SizedBox(width: 12),
                Expanded(
                  flex: _htmlCellFlex(cells[index]),
                  child:
                      _HtmlLayoutCell(cell: cells[index], baseStyle: baseStyle),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HtmlLayoutCell extends StatelessWidget {
  const _HtmlLayoutCell({required this.cell, required this.baseStyle});

  final dom.Element cell;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final child in cell.nodes)
        ..._htmlNodeToWidgets(context, child, baseStyle),
    ];
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: Align(
        alignment: _htmlAlignment(cell),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

List<List<dom.Element>> _htmlLayoutRows(dom.Element table) {
  final rows = <List<dom.Element>>[];
  for (final child in table.children) {
    if (_isHiddenHtml(child)) {
      continue;
    }
    final tag = child.localName?.toLowerCase() ?? '';
    if (tag == 'tr') {
      final cells = _htmlDirectCells(child);
      if (cells.isNotEmpty) {
        rows.add(cells);
      }
      continue;
    }
    if (tag == 'tbody' || tag == 'thead' || tag == 'tfoot') {
      for (final row in child.children) {
        if (!_isHiddenHtml(row) && row.localName?.toLowerCase() == 'tr') {
          final cells = _htmlDirectCells(row);
          if (cells.isNotEmpty) {
            rows.add(cells);
          }
        }
      }
    }
  }
  return rows;
}

List<dom.Element> _htmlDirectCells(dom.Element row) {
  return row.children.where((item) {
    final tag = item.localName?.toLowerCase();
    return !_isHiddenHtml(item) && (tag == 'td' || tag == 'th');
  }).toList(growable: false);
}

bool _nodeHasReadableContent(dom.Node node) {
  if (node is dom.Text) {
    return _readableTextNode(node.text).trim().isNotEmpty;
  }
  if (node is! dom.Element || _isHiddenHtml(node)) {
    return false;
  }
  final tag = node.localName?.toLowerCase() ?? '';
  if (tag == 'img' ||
      tag == 'script' ||
      tag == 'style' ||
      tag == 'meta' ||
      tag == 'link') {
    return false;
  }
  if (tag == 'a') {
    return _readableLinkText(
      _plainText(node),
      node.attributes['href']?.trim() ?? '',
    ).isNotEmpty;
  }
  return node.nodes.any(_nodeHasReadableContent);
}

double? _htmlPreferredWidth(dom.Element element, double maxWidth) {
  final declared = _htmlCssLength(element.attributes['width']) ??
      _htmlCssLength(_styleDeclaration(element, 'width')) ??
      _htmlCssLength(_styleDeclaration(element, 'max-width'));
  if (declared == null || declared <= 0 || maxWidth.isInfinite) {
    return null;
  }
  return math.min(declared, maxWidth);
}

int _htmlCellFlex(dom.Element cell) {
  final colspan = int.tryParse(cell.attributes['colspan']?.trim() ?? '') ?? 1;
  final width = cell.attributes['width'] ?? _styleDeclaration(cell, 'width');
  final percent = RegExp(r'([0-9]+(?:\.[0-9]+)?)%').firstMatch(width ?? '');
  if (percent != null) {
    final value = double.tryParse(percent.group(1) ?? '');
    if (value != null && value > 0) {
      return value.clamp(1, 100).round();
    }
  }
  return colspan.clamp(1, 6).toInt();
}

double? _htmlCssLength(String? value) {
  if (value == null) {
    return null;
  }
  final match =
      RegExp(r'^\s*([0-9]+(?:\.[0-9]+)?)(?:px)?\s*$', caseSensitive: false)
          .firstMatch(value);
  if (match == null) {
    return null;
  }
  return double.tryParse(match.group(1) ?? '');
}

String? _styleDeclaration(dom.Element element, String property) {
  final style = element.attributes['style'];
  if (style == null || style.trim().isEmpty) {
    return null;
  }
  for (final declaration in style.split(';')) {
    final parts = declaration.split(':');
    if (parts.length < 2) {
      continue;
    }
    if (parts.first.trim().toLowerCase() == property) {
      return parts.sublist(1).join(':').trim();
    }
  }
  return null;
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
    'tbody',
    'td',
    'tfoot',
    'th',
    'thead',
    'tr',
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

bool _isHiddenHtml(dom.Element element) {
  if (element.attributes.containsKey('hidden')) {
    return true;
  }
  if (element.attributes['aria-hidden']?.toLowerCase() == 'true') {
    return true;
  }
  final style = (element.attributes['style'] ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '');
  if (style.contains('display:none') ||
      style.contains('visibility:hidden') ||
      style.contains('mso-hide:all')) {
    return true;
  }
  return style.contains('max-height:0') && style.contains('overflow:hidden');
}

bool _isDataTable(dom.Element element) {
  final role = element.attributes['role']?.toLowerCase();
  if (role == 'presentation') {
    return false;
  }
  if (role == 'grid' || role == 'table') {
    return true;
  }
  if (element.querySelectorAll('th').isNotEmpty) {
    return true;
  }
  final border = int.tryParse(element.attributes['border']?.trim() ?? '');
  return border != null && border > 0;
}

String _readableLinkText(String label, String href) {
  final text = label.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) {
    return '';
  }
  if (_looksLikeUrl(text)) {
    if (_isTrackingUrl(text) || _isTrackingUrl(href)) {
      return '';
    }
    if (text.length > 96 || text.contains('%')) {
      return _urlHost(text);
    }
  }
  return text;
}

String _readableTextNode(String value, {bool trim = true}) {
  final collapsed = value.replaceAll(RegExp(r'\s+'), ' ');
  final text = collapsed.trim();
  if (text.isEmpty) {
    return '';
  }
  if (_looksLikeUrl(text)) {
    return _readableLinkText(text, text);
  }
  return trim ? text : collapsed;
}

bool _looksLikeUrl(String value) {
  return RegExp(r'^https?://', caseSensitive: false).hasMatch(value.trim());
}

bool _isTrackingUrl(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('redditmail.com') ||
      normalized.contains('doubleclick.net') ||
      normalized.contains('googleadservices.com') ||
      normalized.startsWith('https://click.') ||
      normalized.startsWith('http://click.')) {
    return true;
  }
  final uri = Uri.tryParse(normalized);
  final host = uri?.host.toLowerCase() ?? '';
  if (host.isEmpty) {
    return false;
  }
  return host.contains('redditmail.com') ||
      host.contains('doubleclick.net') ||
      host.contains('googleadservices.com') ||
      host.startsWith('click.') ||
      (host == 'www.google.com' && (uri?.path ?? '').startsWith('/url'));
}

String _urlHost(String value) {
  final host = Uri.tryParse(value.trim())?.host;
  if (host == null || host.isEmpty) {
    return '';
  }
  return host.replaceFirst(RegExp(r'^www\.'), '');
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
