import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../types/word_entry.dart';

const _kWordsKey = 'readbook_words';
const _kFontSizeKey = 'readbook_font_size';
const _kFuriganaVisibleKey = 'readbook_furigana_visible';
const _kLastTextKey = 'readbook_last_text';
const _kLastFileNameKey = 'readbook_last_file_name';
const _kHiddenWordsKey = 'readbook_hidden_words';
const _kReaderPageKey = 'readbook_reader_page';
const _kReaderBookmarksKey = 'readbook_reader_bookmarks';
const _kKnownWordsKey = 'readbook_known_words';
const _kNativeLangKey = 'readbook_native_lang';

/// SharedPreferences-based word/settings storage
class AppStorage {
  AppStorage._();
  static final AppStorage instance = AppStorage._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── �E��E��E� ──────────────────────────────────────────────────

  Future<Map<String, WordEntry>> loadWords() async {
    final p = await _p;
    final raw = p.getString(_kWordsKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, WordEntry.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveWords(Map<String, WordEntry> words) async {
    final p = await _p;
    final encoded = jsonEncode(words.map((k, v) => MapEntry(k, v.toFullJson())));
    await p.setString(_kWordsKey, encoded);
  }

  Future<void> deleteWord(String key) async {
    final words = await loadWords();
    words.remove(key);
    await saveWords(words);
  }

  // ── UI �E��E�E─────────────────────────────────────────────────

  Future<double> loadFontSize() async {
    final p = await _p;
    return p.getDouble(_kFontSizeKey) ?? 18.0;
  }

  Future<void> saveFontSize(double size) async {
    final p = await _p;
    await p.setDouble(_kFontSizeKey, size);
  }

  Future<bool> loadFuriganaVisible() async {
    final p = await _p;
    return p.getBool(_kFuriganaVisibleKey) ?? true;
  }

  Future<void> saveFuriganaVisible(bool v) async {
    final p = await _p;
    await p.setBool(_kFuriganaVisibleKey, v);
  }

  Future<String> loadLastText() async {
    final p = await _p;
    return p.getString(_kLastTextKey) ?? '';
  }

  Future<void> saveLastText(String text) async {
    final p = await _p;
    await p.setString(_kLastTextKey, text);
  }

  Future<String> loadLastFileName() async {
    final p = await _p;
    return p.getString(_kLastFileNameKey) ?? '';
  }

  Future<void> saveLastFileName(String name) async {
    final p = await _p;
    await p.setString(_kLastFileNameKey, name);
  }

  Future<Map<String, bool>> loadHiddenWords() async {
    final p = await _p;
    final raw = p.getString(_kHiddenWordsKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as bool));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveHiddenWords(Map<String, bool> hidden) async {
    final p = await _p;
    await p.setString(_kHiddenWordsKey, jsonEncode(hidden));
  }

  Future<Map<String, int>> loadReaderPages() async {
    final p = await _p;
    final raw = p.getString(_kReaderPageKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as int));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveReaderPage(String docId, int page) async {
    final p = await _p;
    final pages = await loadReaderPages();
    pages[docId] = page;
    await p.setString(_kReaderPageKey, jsonEncode(pages));
  }

  Future<Map<String, List<Map<String, dynamic>>>> loadReaderBookmarks() async {
    final p = await _p;
    final raw = p.getString(_kReaderBookmarksKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) {
        final list = v as List;
        // migrate old format (list of ints ? map with page + savedAt)
        final converted = list.map((e) {
          if (e is int) return <String, dynamic>{'page': e, 'savedAt': 0};
          return Map<String, dynamic>.from(e as Map);
        }).toList();
        return MapEntry(k, converted);
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> saveReaderBookmarks(
      String docId, List<Map<String, dynamic>> bookmarks) async {
    final p = await _p;
    final all = await loadReaderBookmarks();
    all[docId] = bookmarks;
    await p.setString(_kReaderBookmarksKey, jsonEncode(all));
  }

  // ── Known words (study feature) ─────────────────────────────

  Future<Map<String, bool>> loadKnownWords() async {
    final p = await _p;
    final raw = p.getString(_kKnownWordsKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as bool));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveKnownWords(Map<String, bool> known) async {
    final p = await _p;
    await p.setString(_kKnownWordsKey, jsonEncode(known));
  }

  Future<String> loadNativeLang() async {
    final p = await _p;
    return p.getString(_kNativeLangKey) ?? 'ko';
  }

  Future<void> saveNativeLang(String lang) async {
    final p = await _p;
    await p.setString(_kNativeLangKey, lang);
  }
}
