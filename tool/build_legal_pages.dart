import 'dart:io';

/// Generates the public privacy and terms pages from the Markdown in docs/.
///
/// The Markdown files are the source. Hand-writing the HTML as well would mean
/// two copies of a legal document drifting apart — and the copy users read
/// being the one nobody edits.
///
///   dart run tool/build_legal_pages.dart
Future<void> main() async {
  const pages = {
    'docs/privacy-policy.md': ('web/privacy.html', 'Privacy Policy'),
    'docs/terms-of-service.md': ('web/terms.html', 'Terms of Service'),
  };

  for (final entry in pages.entries) {
    final source = File(entry.key);

    if (!source.existsSync()) {
      stderr.writeln('Missing ${entry.key}');
      exitCode = 1;
      return;
    }

    final (destination, title) = entry.value;
    final html = _render(source.readAsStringSync(), title);

    File(destination).writeAsStringSync(html);
    stdout.writeln('${entry.key} -> $destination');
  }
}

String _render(String markdown, String title) {
  final body = StringBuffer();
  final lines = markdown.split(RegExp(r'\r?\n'));

  var inList = false;
  var inTable = false;
  var paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    body.writeln('<p>${_inline(paragraph.join(' '))}</p>');
    paragraph = [];
  }

  void closeBlocks() {
    flushParagraph();
    if (inList) {
      body.writeln('</ul>');
      inList = false;
    }
    if (inTable) {
      body.writeln('</tbody></table>');
      inTable = false;
    }
  }

  for (final line in lines) {
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      closeBlocks();
      continue;
    }

    if (trimmed.startsWith('# ')) {
      closeBlocks();
      body.writeln('<h1>${_inline(trimmed.substring(2))}</h1>');
    } else if (trimmed.startsWith('## ')) {
      closeBlocks();
      body.writeln('<h2>${_inline(trimmed.substring(3))}</h2>');
    } else if (trimmed == '---') {
      closeBlocks();
      body.writeln('<hr>');
    } else if (trimmed.startsWith('- ')) {
      flushParagraph();
      if (!inList) {
        body.writeln('<ul>');
        inList = true;
      }
      body.writeln('<li>${_inline(trimmed.substring(2))}</li>');
    } else if (trimmed.startsWith('|')) {
      flushParagraph();
      // The separator row carries no content — it only tells Markdown that the
      // row above it was a header.
      if (RegExp(r'^\|[\s|:-]+\|$').hasMatch(trimmed)) continue;

      final cells = trimmed
          .split('|')
          .map((cell) => cell.trim())
          .where((cell) => cell.isNotEmpty)
          .toList();

      if (!inTable) {
        body.writeln('<table><thead><tr>');
        for (final cell in cells) {
          body.writeln('<th>${_inline(cell)}</th>');
        }
        body.writeln('</tr></thead><tbody>');
        inTable = true;
      } else {
        body.writeln('<tr>');
        for (final cell in cells) {
          body.writeln('<td>${_inline(cell)}</td>');
        }
        body.writeln('</tr>');
      }
    } else {
      if (inList || inTable) closeBlocks();
      paragraph.add(trimmed);
    }
  }

  closeBlocks();

  return _template(title, body.toString());
}

/// Bold, code, and links — the only inline markup these documents use.
String _inline(String text) {
  var out = text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  out = out.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
    (m) => '<a href="${_href(m[2]!)}">${m[1]}</a>',
  );
  out = out.replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (m) => '<strong>${m[1]}</strong>',
  );
  out = out.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => '<code>${m[1]}</code>');
  out = out.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => '<em>${m[1]}</em>');

  return out;
}

/// Rewrites the cross-link between the two documents to its published path.
String _href(String target) => switch (target) {
  'privacy-policy.md' => '/privacy',
  'terms-of-service.md' => '/terms',
  _ => target,
};

String _template(String title, String body) =>
    '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title — Painter Reference</title>
<style>
  :root {
    --ground: #fdfcfa; --ink: #23202b; --dim: #6b6678;
    --edge: #e5e1da; --accent: #6b4ea8;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --ground: #16151b; --ink: #e9e6f0; --dim: #9a95a8;
      --edge: #2c2a35; --accent: #b3a0e8;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0 auto; padding: 48px 24px 96px; max-width: 68ch;
    background: var(--ground); color: var(--ink);
    font: 17px/1.65 Georgia, "Iowan Old Style", "Times New Roman", serif;
  }
  h1 {
    font-size: 30px; line-height: 1.2; margin: 0 0 6px;
    text-wrap: balance; letter-spacing: -0.01em;
  }
  h2 {
    font-size: 20px; margin: 40px 0 12px; text-wrap: balance;
    padding-top: 20px; border-top: 1px solid var(--edge);
  }
  p { margin: 0 0 16px; }
  ul { margin: 0 0 16px; padding-left: 22px; }
  li { margin-bottom: 8px; }
  a { color: var(--accent); }
  code {
    font: 0.86em ui-monospace, "Cascadia Mono", Consolas, monospace;
    background: color-mix(in srgb, var(--edge) 60%, transparent);
    padding: 1px 5px; border-radius: 4px;
  }
  hr { border: none; border-top: 1px solid var(--edge); margin: 32px 0; }
  table {
    border-collapse: collapse; width: 100%; margin: 0 0 20px;
    font-size: 15px; display: block; overflow-x: auto;
  }
  th, td {
    text-align: left; padding: 9px 12px;
    border-bottom: 1px solid var(--edge); vertical-align: top;
  }
  th { font-size: 13px; text-transform: uppercase; letter-spacing: .05em; color: var(--dim); }
  footer {
    margin-top: 56px; padding-top: 20px; border-top: 1px solid var(--edge);
    font-size: 15px; color: var(--dim);
  }
  footer a { margin-right: 18px; }
</style>
</head>
<body>
$body
<footer>
  <a href="/">Painter Reference</a>
  <a href="/privacy">Privacy Policy</a>
  <a href="/terms">Terms of Service</a>
</footer>
</body>
</html>
''';
