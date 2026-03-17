import 'package:flutter/material.dart';
import '../types/word_entry.dart';
import '../utils/storage.dart';
import '../utils/gist.dart' as gist;
import '../widgets/dict_popup.dart';

class WordListScreen extends StatefulWidget {
  const WordListScreen({super.key});

  static final refreshSignal = ValueNotifier<int>(0);

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen> {
  Map<String, WordEntry> _words = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    WordListScreen.refreshSignal.addListener(_load);
  }

  @override
  void dispose() {
    WordListScreen.refreshSignal.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final words = await AppStorage.instance.loadWords();
    if (mounted) setState(() => _words = words);
  }

  List<WordEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    final all = _words.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    if (q.isEmpty) return all;
    return all.where((e) => e.word.toLowerCase().contains(q) || e.definitionKo.contains(q)).toList();
  }

  Future<void> _delete(String key) async {
    await AppStorage.instance.deleteWord(key);
    final updated = Map<String, WordEntry>.from(_words)..remove(key);
    setState(() => _words = updated);
    gist.syncToGist(updated).catchError((_) {});
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF313244),
        title: const Text('전체 삭제', style: TextStyle(color: Colors.white)),
        content: const Text('저장된 단어를 모두 삭제할까요?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppStorage.instance.clearWords();
    setState(() => _words = {});
    gist.syncToGist({}).catchError((_) {});
  }

  Future<void> _setFurigana(String key, String furigana) async {
    final existing = _words[key];
    if (existing == null) return;
    final updated = {..._words, key: existing.copyWith(furigana: furigana)};
    await AppStorage.instance.saveWords(updated);
    setState(() => _words = updated);
    gist.syncToGist(updated).catchError((_) {});
  }

  Future<void> _showDetail(WordEntry entry) async {
    final key = entry.word.toLowerCase();
    await showDictPopup(
      context: context,
      entry: entry,
      isSaved: true,
      onSave: () => Navigator.pop(context),
      onDelete: () {
        _delete(key);
        Navigator.pop(context);
      },
      onFuriganaSelect: (furigana) {
        _setFurigana(key, furigana);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181825),
        title: const Text('단어장', style: TextStyle(color: Colors.white)),
        actions: [
          if (_words.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              tooltip: '전체 삭제',
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: Column(
        children: [
          // 검색창
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              cursorColor: const Color(0xFF9B59B6),
              decoration: InputDecoration(
                hintText: '단어 검색…',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF313244),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          // 단어 목록
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      _words.isEmpty ? '저장된 단어가 없습니다' : '검색 결과 없음',
                      style: const TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final e = items[i];
                      final key = e.word.toLowerCase();
                      return _WordTile(
                        entry: e,
                        onTap: () => _showDetail(e),
                        onDelete: () => _delete(key),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WordTile extends StatelessWidget {
  final WordEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _WordTile({required this.entry, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF313244),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: onTap,
        title: Text(
          entry.word,
          style: const TextStyle(color: Color(0xFFCBA6F7), fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.phonetic.isNotEmpty)
              Text(entry.phonetic, style: const TextStyle(color: Color(0xFF89DCFF), fontSize: 12)),
            Text(entry.definitionKo, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
