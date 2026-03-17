import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../types/word_entry.dart';

const _kWordsKey = 'readbook_words';
const _kFontSizeKey = 'readbook_font_size';
const _kFuriganaVisibleKey = 'readbook_furigana_visible';
const _kLastTextKey = 'readbook_last_text';

/// SharedPreferences 기반 단어/설정 저장소
class AppStorage {
  AppStorage._();
  static final AppStorage instance = AppStorage._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── 단어장 ──────────────────────────────────────────────────

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
    final encoded = jsonEncode(words.map((k, v) => MapEntry(k, v.toJson())));
    await p.setString(_kWordsKey, encoded);
  }

  Future<void> upsertWord(WordEntry entry) async {
    final words = await loadWords();
    words[entry.word.toLowerCase()] = entry;
    await saveWords(words);
  }

  Future<void> deleteWord(String key) async {
    final words = await loadWords();
    words.remove(key);
    await saveWords(words);
  }

  Future<void> clearWords() async {
    final words = await loadWords();
    words.clear();
    await saveWords(words);
  }

  // ── UI 설정 ─────────────────────────────────────────────────

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
}
