// 단어 키 정규화, 토큰화, 컨텍스트 추출

/// 단어를 소문자 + 앞뒤 공백 제거한 키로 정규화
String normalizeKey(String word) => word.trim().toLowerCase();

/// 원문 텍스트에서 단어(한 token)를 token index 기준으로 추출하고
/// 탭 위치 앞뒤 ±150 문자를 컨텍스트로 반환.
String extractContext(String text, int tapCharOffset) {
  final start = (tapCharOffset - 150).clamp(0, text.length);
  final end = (tapCharOffset + 150).clamp(0, text.length);
  return text.substring(start, end);
}

/// 텍스트를 '단어' 토큰 스팬 리스트로 분해.
/// 반환: List<_Span> — start/end/text/isWord
List<TextSpan2> tokenize(String text) {
  final spans = <TextSpan2>[];
  // 알파벳 + 하이픈(phrasal/hyphenated) 연속, 또는 단독 구두점/공백
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

/// 웹에서 UI 블로킹 없이 토크나이즈.
/// 1000 토큰마다 이벤트 루프에 제어권을 반환해 JS 스레드 프리즈 방지.
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
