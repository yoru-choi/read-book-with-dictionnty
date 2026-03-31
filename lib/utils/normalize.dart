// word key normalization, tokenization, context extraction

/// Normalize a word to a lowercase trimmed key
String normalizeKey(String word) => word.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Extract ±150 chars around the tapped position as context.
String extractContext(String text, int tapCharOffset) {
  final start = (tapCharOffset - 150).clamp(0, text.length);
  final end = (tapCharOffset + 150).clamp(0, text.length);
  return text.substring(start, end);
}

