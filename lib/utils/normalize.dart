// word key normalization, tokenization, context extraction

/// Normalize a word to a lowercase trimmed key
String normalizeKey(String word) => word.trim().toLowerCase();

/// Extract ±150 chars around the tapped position as context.
String extractContext(String text, int tapCharOffset) {
  final start = (tapCharOffset - 150).clamp(0, text.length);
  final end = (tapCharOffset + 150).clamp(0, text.length);
  return text.substring(start, end);
}

/// Split text into word token spans.
/// Returns List<_Span> — start/end/text/isWord
List<TextSpan2> tokenize(String text) {
  final spans = <TextSpan2>[];
  // letters + hyphens (phrasal/hyphenated), or punctuation/whitespace
  final re = RegExp(r"[A-Za-z][A-Za-z'\-]*|[^\w]|\d+");
  int cursor = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan2(text.substring(cursor, m.start), false, cursor, m.start));
    }
    final tok = m.group(0)!;
    final isWord = RegExp(r'^[A-Za-z]').hasMatch(tok);
    spans.add(TextSpan2(tok, isWord, m.start, m.end));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan2(text.substring(cursor), false, cursor, text.length));
  }
  return spans;
}

/// Tokenize without blocking the UI on web.
/// Yields control to the event loop every 1000 tokens to prevent JS thread freeze.
Future<List<TextSpan2>> tokenizeAsync(String text) async {
  final spans = <TextSpan2>[];
  final re = RegExp(r"[A-Za-z][A-Za-z'\-]*|[^\w]|\d+");
  int cursor = 0;
  int count = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan2(text.substring(cursor, m.start), false, cursor, m.start));
    }
    final tok = m.group(0)!;
    final isWord = RegExp(r'^[A-Za-z]').hasMatch(tok);
    spans.add(TextSpan2(tok, isWord, m.start, m.end));
    cursor = m.end;
    count++;
    if (count % 1000 == 0) {
      await Future.delayed(Duration.zero);
    }
  }
  if (cursor < text.length) {
    spans.add(TextSpan2(text.substring(cursor), false, cursor, text.length));
  }
  return spans;
}

class TextSpan2 {
  final String text;
  final bool isWord;
  final int start;
  final int end;
  const TextSpan2(this.text, this.isWord, this.start, this.end);
}
