import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../types/word_entry.dart';
import 'secure_storage.dart';
import 'storage.dart';

const _kModelsKey = 'gemini_cached_models';

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

  // 1. 로컬 캐시에서 먼저 로드 (콜드 스타트 시 API 호출 절약)
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getStringList(_kModelsKey);
  if (cached != null && cached.isNotEmpty) {
    _cachedModels = cached;
    // 백그라운드에서 최신 목록 갱신 (다음 세션용)
    _refreshModelsInBackground(apiKey, prefs);
    return cached;
  }

  // 2. 로컬 캐시 없으면 API 호출
  final models = await _fetchModels(apiKey);
  _cachedModels = models;
  await prefs.setStringList(_kModelsKey, models);
  return models;
}

Future<List<String>> _fetchModels(String apiKey) async {
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
      // voca-pin 동일 정렬: lite-preview > lite > flash-preview > flash > pro
      // tier score: pro=0, flash=1, flash-preview=2, lite=3, lite-preview=4
      int score(String s) {
        final l = s.toLowerCase();
        final tier = l.contains('pro') ? 0 : l.contains('lite') ? 3 : 1;
        final preview = (l.contains('preview') || l.contains('exp')) ? 1 : 0;
        return tier + preview;
      }
      int version(String s) {
        final m = RegExp(r'(\d+)(?:\.(\d+))?').firstMatch(s);
        if (m == null) return 0;
        return (int.tryParse(m.group(1)!) ?? 0) * 100
             + (int.tryParse(m.group(2) ?? '0') ?? 0);
      }
      models.sort((a, b) {
        final sc = score(b).compareTo(score(a));
        if (sc != 0) return sc;
        return version(b).compareTo(version(a));
      });
      if (models.isNotEmpty) return models;
    }
  } catch (_) {}
  return const ['gemini-2.5-flash'];
}

void _refreshModelsInBackground(String apiKey, SharedPreferences prefs) {
  _fetchModels(apiKey).then((models) {
    _cachedModels = models;
    prefs.setStringList(_kModelsKey, models);
  }).catchError((_) {});
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

/// Gemini API connection test (simple ping)
Future<bool> testGeminiConnection(String apiKey) async {
  try {
    final models = await _resolveModels(apiKey);
    if (models.isEmpty) return false;
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
