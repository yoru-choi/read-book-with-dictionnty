import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../types/word_entry.dart';
import '../utils/normalize.dart';
import '../utils/storage.dart';
import '../utils/gemini.dart' as gemini;
import '../utils/gist.dart' as gist;
import '../widgets/dict_popup.dart';
import 'word_list_screen.dart';

/// Launched when the user selects text in any app and taps "ReadBook에 저장"
/// from the text-selection context menu (ACTION_PROCESS_TEXT).
///
/// Shows a loading spinner while Gemini fetches the word,
/// then presents [DictPopup]. After the user saves/dismisses, the Activity finishes.
class ProcessTextSaveScreen extends StatefulWidget {
  const ProcessTextSaveScreen({super.key});

  @override
  State<ProcessTextSaveScreen> createState() => _ProcessTextSaveScreenState();
}

class _ProcessTextSaveScreenState extends State<ProcessTextSaveScreen> {
  static const _channel = MethodChannel('com.readbook/process_text');

  bool _loading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final raw = await _channel.invokeMethod<String>('getSelectedText');
    final word = raw?.trim() ?? '';
    if (word.isEmpty) {
      _close();
      return;
    }

    final results = await Future.wait<dynamic>([
      AppStorage.instance.loadWords(),
      AppStorage.instance.loadHiddenWords(),
    ]);
    final words = results[0] as Map<String, WordEntry>;
    final hiddenWords = results[1] as Map<String, bool>;

    final key = _resolveKey(words, word);
    WordEntry? entry = words[key];

    entry ??= await gemini.fetchWordEntry(word, context: '');

    if (!mounted) return;

    if (entry == null) {
      setState(() {
        _loading = false;
        _errorMsg = 'Could not look up "$word".\nPlease check your Gemini API key.';
      });
      return;
    }

    setState(() => _loading = false);
    final captured = entry;

    await Future.delayed(Duration.zero);
    if (!mounted) return;

    await showDictPopup(
      context: context,
      entry: captured,
      isSaved: words.containsKey(key),
      isMeaningHidden: hiddenWords[key] ?? false,
      onSave: () => _saveWord(words, captured),
      onDelete: () => _deleteWord(words, key),
      onGlossSelect: (mIdx, kIdx) => _setGloss(words, key, mIdx, kIdx, captured),
      onToggleMeaningHidden: () => _toggleHidden(hiddenWords, key),
    );

    _close();
  }

  String _resolveKey(Map<String, WordEntry> words, String word) {
    final key = normalizeKey(word);
    if (words.containsKey(key)) return key;
    for (final e in words.entries) {
      if (normalizeKey(e.value.word) == key) return e.key;
    }
    final lemmaMatches = words.entries
        .where((e) =>
            e.value.lemma.isNotEmpty && normalizeKey(e.value.lemma) == key)
        .toList();
    if (lemmaMatches.length == 1) return lemmaMatches.first.key;
    return key;
  }

  Future<void> _saveWord(Map<String, WordEntry> words, WordEntry entry) async {
    final updated = {...words, normalizeKey(entry.word): entry};
    await AppStorage.instance.saveWords(updated);
    WordListScreen.refreshSignal.value++;
    gist.syncToGist(updated);
  }

  Future<void> _deleteWord(Map<String, WordEntry> words, String key) async {
    final updated = Map<String, WordEntry>.from(words)..remove(key);
    await AppStorage.instance.saveWords(updated);
    WordListScreen.refreshSignal.value++;
    gist.syncToGist(updated);
  }

  Future<void> _setGloss(Map<String, WordEntry> words, String key,
      int mIdx, int kIdx, WordEntry existing) async {
    final updated = {
      ...words,
      key: existing.copyWith(glossMIdx: mIdx, glossKIdx: kIdx),
    };
    await AppStorage.instance.saveWords(updated);
    WordListScreen.refreshSignal.value++;
    gist.syncToGist(updated);
  }

  Future<void> _toggleHidden(Map<String, bool> hidden, String key) async {
    final updated = Map<String, bool>.from(hidden);
    if (updated.containsKey(key)) {
      updated.remove(key);
    } else {
      updated[key] = true;
    }
    await AppStorage.instance.saveHiddenWords(updated);
  }

  Future<void> _close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _errorMsg != null
          ? _buildErrorCard(context)
          : _loading
              ? _buildLoadingCard(context)
              : const SizedBox.shrink(),
    );
  }

  Widget _buildLoadingCard(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 24,
          left: 24,
          right: 24,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Color(0xFF9B59B6), strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Text('Looking up word...',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 24,
          left: 24,
          right: 24,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
            const SizedBox(height: 12),
            Text(
              _errorMsg!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _close, child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
