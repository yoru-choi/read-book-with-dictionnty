import 'dart:convert';
import 'package:http/http.dart' as http;
import '../types/word_entry.dart';
import 'secure_storage.dart';

const _base = 'https://generativelanguage.googleapis.com/v1beta/models/';
const _models = [
  'gemini-3.1-flash-lite-preview',
  'gemini-3-flash-preview',
  'gemini-2.5-flash',
];

const _responseSchema = {
  'type': 'object',
  'properties': {
    'word': {'type': 'string'},
    'lemma': {'type': 'string'},
    'form': {'type': 'string'},
    'phonetic': {'type': 'string'},
    'definitionKo': {'type': 'string'},
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
          'ko': {'type': 'array', 'minItems': 1, 'items': {'type': 'string'}},
        },
        'required': ['pos', 'ko'],
      },
    },
  },
  'required': ['word', 'lemma', 'form', 'phonetic', 'definitionKo', 'meanings'],
};

const _validPos = {'n.', 'v.', 'adj.', 'adv.', 'pron.', 'prep.', 'conj.', 'int.', 'phrasal v.', 'idiom', 'phrase'};

bool _isValid(Map<String, dynamic> obj) {
  if ((obj['word'] as String? ?? '').trim().isEmpty) return false;
  if ((obj['lemma'] as String? ?? '').trim().isEmpty) return false;
  if ((obj['definitionKo'] as String? ?? '').trim().isEmpty) return false;
  final meanings = obj['meanings'];
  if (meanings is! List || meanings.isEmpty) return false;
  return meanings.every((m) {
    if (m is! Map) return false;
    final pos = m['pos'] as String? ?? '';
    if (!_validPos.contains(pos)) return false;
    final ko = m['ko'];
    if (ko is! List || ko.isEmpty) return false;
    return ko.every((x) => x is String && x.trim().isNotEmpty);
  });
}

String _buildPrompt(String word, String context) {
  final contextLine = context.isNotEmpty
      ? 'Context: ${jsonEncode(context.replaceAll('\n', ' ').substring(0, context.length.clamp(0, 300)))}\n'
      : '';
  return '''Explain the meaning of the English word, phrasal verb, or idiom for Korean learners.

Input: ${jsonEncode(word)}
${contextLine}Return JSON matching the schema.

Rules:
- word: the original input text as-is
- lemma: the base dictionary form (e.g. "rests" → "rest")
- form: grammatical form label such as "base form", "plural noun", "past tense", "past participle", "present participle", "3rd person singular"; empty string if not applicable
- phonetic: standard IPA string for the lemma (e.g. /wɜːrd/), empty string if unknown or multi-word
- definitionKo: ONE short Korean word or phrase representing the core meaning
- pos MUST be exactly one of: n. / v. / adj. / adv. / pron. / prep. / conj. / int. / phrasal v. / idiom / phrase
- meanings[]: each object represents one part of speech; ordered by frequency
- ko: ordered by frequency, at most 4 per pos
- If Context is provided, place the meaning that best fits the context first in ko[]
- Exclude archaic, highly technical, or very rare meanings''';
}

/// Gemini API 호출 (모델 캐스케이드)
Future<WordEntry?> fetchWordEntry(String word, {String context = ''}) async {
  final apiKey = await SecureStorage.instance.getGeminiKey();
  if (apiKey == null || apiKey.isEmpty) return null;

  final body = jsonEncode({
    'contents': [
      {
        'parts': [
          {'text': _buildPrompt(word, context)},
        ],
      },
    ],
    'generationConfig': {
      'responseMimeType': 'application/json',
      'responseSchema': _responseSchema,
    },
  });

  for (final model in _models) {
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
      if (res.statusCode == 429) continue; // 쿼터 초과 → 다음 모델
      if (res.statusCode != 200) continue;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = (((data['candidates'] as List?)?.first as Map?)?['content'] as Map?)?['parts'] as List?;
      final text = (raw?.first as Map?)?['text'] as String? ?? '';
      final parsed = jsonDecode(text) as Map<String, dynamic>;
      if (_isValid(parsed)) {
        return WordEntry.fromJson({
          ...parsed,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// Gemini API 연결 테스트 (단순 ping)
Future<bool> testGeminiConnection(String apiKey) async {
  try {
    final url = Uri.parse('${_base}${_models.first}:generateContent');
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
