import 'dart:convert';
import 'package:http/http.dart' as http;
import '../types/word_entry.dart';
import 'secure_storage.dart';
import 'storage.dart';

const _base = 'https://generativelanguage.googleapis.com/v1beta/models/';

const _langNames = {
  'ko': 'Korean',
  'ja': 'Japanese',
  'zh': 'Chinese',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'vi': 'Vietnamese',
  'th': 'Thai',
};

const _responseSchema = {
  'type': 'object',
  'properties': {
    'word': {'type': 'string'},
    'lemma': {'type': 'string'},
    'form': {'type': 'string'},
    'phonetic': {'type': 'string'},
    'definition': {'type': 'string'},
    'meanings': {
      'type': 'array',
      'minItems': 1,
      'items': {
        'type': 'object',
        'properties': {
          'pos': {
            'type': 'string',
            'enum': ['n.', 'v.', 'adj.', 'adv.', 'pron.', 'prep.', 'conj.', 'int.', 'phrasal v.', 'idiom', 'phrase'],
          },
          'trans': {'type': 'array', 'minItems': 1, 'items': {'type': 'string'}},
        },
        'required': ['pos', 'trans'],
      },
    },
    'example': {
      'type': 'object',
      'properties': {
        'en': {'type': 'string'},
        'trans': {'type': 'string'},
      },
      'required': ['en', 'trans'],
      'nullable': true,
    },
  },
  'required': ['word', 'lemma', 'form', 'phonetic', 'definition', 'meanings', 'example'],
};

const _validPos = {'n.', 'v.', 'adj.', 'adv.', 'pron.', 'prep.', 'conj.', 'int.', 'phrasal v.', 'idiom', 'phrase'};

bool _isValid(Map<String, dynamic> obj) {
  if ((obj['word'] as String? ?? '').trim().isEmpty) return false;
  if ((obj['lemma'] as String? ?? '').trim().isEmpty) return false;
  if ((obj['definition'] as String? ?? '').trim().isEmpty) return false;
  final meanings = obj['meanings'];
  if (meanings is! List || meanings.isEmpty) return false;
  final meaningsOk = meanings.every((m) {
    if (m is! Map) return false;
    final pos = m['pos'] as String? ?? '';
    if (!_validPos.contains(pos)) return false;
    final trans = m['trans'];
    if (trans is! List || trans.isEmpty) return false;
    return trans.every((x) => x is String && x.trim().isNotEmpty);
  });
  if (!meaningsOk) return false;
  final example = obj['example'];
  if (example != null && example is Map) {
    if (example['en'] is! String || example['trans'] is! String) return false;
  }
  return true;
}

// Cached model list per session
List<String>? _cachedModels;

Future<List<String>> _resolveModels(String apiKey) async {
  if (_cachedModels != null) return _cachedModels!;
  try {
    final res = await http.get(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=$apiKey'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final models = (data['models'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((m) {
            final name = (m['name'] as String? ?? '').toLowerCase();
            final methods = (m['supportedGenerationMethods'] as List?)?.cast<String>() ?? [];
            if (!methods.contains('generateContent')) return false;
            if (!name.contains('gemini')) return false;
            const exclude = ['tts', 'image', 'computer-use', 'robotics', 'customtools'];
            if (exclude.any((e) => name.contains(e))) return false;
            return true;
          })
          .map((m) => (m['name'] as String).replaceFirst('models/', ''))
          .toList();
      // 버전 파싱: "gemini-2.5-flash-lite" → major=2, minor=5, isLite=true, isPro=false
      // 무료 쿼터 우선: flash-lite > flash > pro, stable > preview, 최신 버전 우선
      int parseMajor(String s) => int.tryParse(RegExp(r'(\d+)').firstMatch(s)?.group(1) ?? '') ?? 0;
      int parseMinor(String s) => int.tryParse(RegExp(r'\d+\.(\d+)').firstMatch(s)?.group(1) ?? '') ?? 0;
      models.sort((a, b) {
        final al = a.toLowerCase(), bl = b.toLowerCase();
        // 1) pro는 무료 쿼터 거의 없음 → 최후순위
        final aPro = al.contains('pro'), bPro = bl.contains('pro');
        if (aPro != bPro) return aPro ? 1 : -1;
        // 2) preview/exp 불안정 → 후순위
        final aPrev = al.contains('preview') || al.contains('exp');
        final bPrev = bl.contains('preview') || bl.contains('exp');
        if (aPrev != bPrev) return aPrev ? 1 : -1;
        // 3) lite 먼저 (무료 쿼터 넉넉)
        final aLite = al.contains('lite'), bLite = bl.contains('lite');
        if (aLite != bLite) return aLite ? -1 : 1;
        // 4) 최신 버전 우선
        final aMaj = parseMajor(a), bMaj = parseMajor(b);
        if (bMaj != aMaj) return bMaj.compareTo(aMaj);
        return parseMinor(b).compareTo(parseMinor(a));
      });
      if (models.isNotEmpty) {
        _cachedModels = models;
        return models;
      }
    }
  } catch (_) {}
  // Fallback
  const fallback = ['gemini-2.5-flash'];
  _cachedModels = fallback;
  return fallback;
}

String _buildPrompt(String word, String context, String nativeLang) {
  final contextLine = context.isNotEmpty
      ? 'Context: ${jsonEncode(context.replaceAll('\n', ' ').substring(0, context.length.clamp(0, 300)))}\n'
      : '';
  return '''Explain the meaning of the English word, phrasal verb, or idiom for $nativeLang learners.

Input: ${jsonEncode(word)}
${contextLine}Return JSON matching the schema.

Rules:
- word: the original input text as-is
- lemma: the base dictionary form of the input (e.g. "rests" → "rest", "running" → "run")
- form: grammatical form label such as "base form", "plural noun", "past tense", "past participle", "present participle", "3rd person singular", "comparative", "superlative"; use empty string if not applicable (e.g. for idioms, phrases)
- For phrases or idioms that do not inflect, lemma should be the same as word
- phonetic: standard IPA string for the lemma (e.g. /wɜːrd/), empty string if unknown or multi-word
- definition: ONE short $nativeLang word or phrase representing the core meaning (not a list)
- pos MUST be exactly one of: n. / v. / adj. / adv. / pron. / prep. / conj. / int. / phrasal v. / idiom / phrase
- meanings[]: each object represents one part of speech
- trans: array of $nativeLang meanings for that pos
- If Context is provided, place the meaning that best fits the context as the first item in trans[] of the most relevant pos; still include other common meanings after
- Order meanings[] by frequency: most commonly used part of speech first
- Order trans[] by frequency: most common meaning first
- Include only common, modern meanings useful for language learners
- For each part of speech, return at most 4 meanings
- Exclude archaic, highly technical, or very rare meanings unless commonly encountered
- Provide concise $nativeLang interpretations rather than literal translations
- example: provide exactly 1 natural English example sentence (max 12 words) using the lemma form, with a $nativeLang translation (trans); if Context is provided, prioritize a sentence similar to the context''';
}

/// Gemini API call (dynamic model discovery + cascade)
Future<WordEntry?> fetchWordEntry(String word, {String context = ''}) async {
  final apiKey = await SecureStorage.instance.getGeminiKey();
  if (apiKey == null || apiKey.isEmpty) return null;

  final langCode = await AppStorage.instance.loadNativeLang();
  final nativeLang = _langNames[langCode] ?? 'Korean';
  final models = await _resolveModels(apiKey);

  final body = jsonEncode({
    'contents': [
      {
        'parts': [
          {'text': _buildPrompt(word, context, nativeLang)},
        ],
      },
    ],
    'generationConfig': {
      'responseMimeType': 'application/json',
      'responseSchema': _responseSchema,
    },
  });

  for (final model in models) {
    try {
      final url = Uri.parse('$_base$model:generateContent');
      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-goog-api-key': apiKey,
        },
        body: body,
      );
      if (res.statusCode == 429) continue;
      if (res.statusCode != 200) continue;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = (((data['candidates'] as List?)?.first as Map?)?['content'] as Map?)?['parts'] as List?;
      final text = (raw?.first as Map?)?['text'] as String? ?? '';
      final parsed = jsonDecode(text) as Map<String, dynamic>;
      if (_isValid(parsed)) {
        return WordEntry.fromJson({
          ...parsed,
          'sourceText': context,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// Extract surrounding context for a word at a given index in text.
String extractContext(String text, int index) {
  const radius = 120;
  final start = (index - radius).clamp(0, text.length);
  final end = (index + radius).clamp(0, text.length);
  return text.substring(start, end);
}

/// Gemini API connection test (simple ping)
Future<bool> testGeminiConnection(String apiKey) async {
  try {
    final models = await _resolveModels(apiKey);
    final url = Uri.parse('$_base${models.first}:generateContent');
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json', 'X-goog-api-key': apiKey},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': 'Reply with the single word: ok'},
            ],
          },
        ],
      }),
    );
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}
