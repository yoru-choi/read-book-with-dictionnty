import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../types/word_entry.dart';
import '../utils/storage.dart';
import '../utils/gemini.dart' as gemini;
import '../utils/gist.dart' as gist;
import '../utils/normalize.dart';
import '../widgets/dict_popup.dart';

class WordListScreen extends StatefulWidget {
  const WordListScreen({super.key});

  static final refreshSignal = ValueNotifier<int>(0);

  @override
  State<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends State<WordListScreen>
    with SingleTickerProviderStateMixin {
  Map<String, WordEntry> _words = {};
  Map<String, bool> _hiddenWords = {};
  final _searchController = TextEditingController();
  List<WordEntry>? _sortedCache;
  bool _refreshing = false;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() => setState(() {}));
    _load();
    WordListScreen.refreshSignal.addListener(_load);
  }

  @override
  void dispose() {
    WordListScreen.refreshSignal.removeListener(_load);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final words = await AppStorage.instance.loadWords();
    final hidden = await AppStorage.instance.loadHiddenWords();
    if (mounted) {
      setState(() {
        _words = words;
        _hiddenWords = hidden;
        _sortedCache = null;
      });
    }
  }

  Future<void> _syncFromGist() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final remote = await gist.fetchFromGist(forceRefresh: true);
      await AppStorage.instance.saveWords(remote);
      if (mounted) {
        setState(() {
          _words = remote;
          _sortedCache = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synced ${remote.length} words from Gist'),
            backgroundColor: const Color(0xFF9B59B6),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      WordListScreen.refreshSignal.value++;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
    if (mounted) setState(() => _refreshing = false);
  }

  List<WordEntry> get _sortedWords =>
      _sortedCache ??= (_words.values.toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt)));

  List<WordEntry> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _sortedWords;
    return _sortedWords
        .where((e) =>
            e.word.toLowerCase().contains(q) || e.definition.contains(q))
        .toList();
  }

  Future<void> _delete(String key) async {
    await AppStorage.instance.deleteWord(key);
    final updated = Map<String, WordEntry>.from(_words)..remove(key);
    setState(() {
      _words = updated;
      _sortedCache = null;
    });
    WordListScreen.refreshSignal.value++;
    gist.syncToGist(updated);
  }


  Future<void> _setGloss(String key, int mIdx, int kIdx) async {
    final existing = _words[key];
    if (existing == null) return;
    final updated = {
      ..._words,
      key: existing.copyWith(glossMIdx: mIdx, glossKIdx: kIdx)
    };
    await AppStorage.instance.saveWords(updated);
    setState(() {
      _words = updated;
      _sortedCache = null;
    });
    WordListScreen.refreshSignal.value++;
    gist.syncToGist(updated);
  }

  Future<void> _toggleHiddenWord(String key) async {
    final updated = Map<String, bool>.from(_hiddenWords);
    if (updated.containsKey(key)) {
      updated.remove(key);
    } else {
      updated[key] = true;
    }
    await AppStorage.instance.saveHiddenWords(updated);
    if (mounted) setState(() => _hiddenWords = updated);
    WordListScreen.refreshSignal.value++;
  }

  String _resolveKey(String word) {
    final key = normalizeKey(word);
    if (_words.containsKey(key)) return key;
    for (final e in _words.entries) {
      if (normalizeKey(e.value.word) == key) return e.key;
    }
    final lemmaMatches = _words.entries
        .where((e) => e.value.lemma.isNotEmpty && normalizeKey(e.value.lemma) == key)
        .toList();
    if (lemmaMatches.length == 1) return lemmaMatches.first.key;
    return key;
  }

  Future<void> _lookUpWord(String word) async {
    if (word.trim().isEmpty) return;
    final key = _resolveKey(word);
    WordEntry? entry = _words[key];

    if (entry == null) {
      // Don't block UI while fetching — fire and show popup when ready
      gemini.fetchWordEntry(word, context: '').then((result) {
        if (result == null || !mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showLookUpPopup(key, result);
        });
      });
      return;
    }

    await _showLookUpPopup(key, entry);
  }

  Future<void> _showLookUpPopup(String key, WordEntry entry) async {
    await showDictPopup(
      context: context,
      entry: entry,
      isSaved: _words.containsKey(key),
      isMeaningHidden: _hiddenWords.containsKey(key),
      onSave: () => _saveWord(entry),
      onDelete: () => _delete(key),
      onGlossSelect: (mIdx, kIdx) => _setGloss(key, mIdx, kIdx),
      onToggleMeaningHidden: () => _toggleHiddenWord(key),
    );
  }

  Future<void> _saveWord(WordEntry entry) async {
    final updated = {..._words, normalizeKey(entry.word): entry};
    await AppStorage.instance.saveWords(updated);
    setState(() {
      _words = updated;
      _sortedCache = null;
    });
    WordListScreen.refreshSignal.value++;
    gist.syncToGist(updated);
  }

  Future<void> _showDetail(WordEntry entry) async {
    final key = normalizeKey(entry.word);
    await showDictPopup(
      context: context,
      entry: entry,
      isSaved: true,
      isMeaningHidden: _hiddenWords.containsKey(key),
      onSave: () {},
      onDelete: () => _delete(key),
      onGlossSelect: (mIdx, kIdx) => _setGloss(key, mIdx, kIdx),
      onToggleMeaningHidden: () => _toggleHiddenWord(key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: const Color(0xFF181825),
          child: SafeArea(
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF9B59B6),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              tabs: const [
                Tab(text: 'Flashcard'),
                Tab(text: 'List'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Study flashcard
          _StudyTab(
            words: _words,
            onDelete: _delete,
            onLookUp: _lookUpWord,
          ),
          // Tab 2: Word List
          _buildListTab(items),
        ],
      ),
    );
  }

  Widget _buildListTab(List<WordEntry> items) {
    return Column(
      children: [
        // search bar + refresh
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: const Color(0xFF9B59B6),
                  decoration: InputDecoration(
                    hintText: 'Search words…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF313244),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _refreshing ? null : _syncFromGist,
                icon: _refreshing
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9B59B6)),
                      )
                    : const Icon(Icons.sync_rounded, color: Colors.white54),
                tooltip: 'Sync from Gist',
              ),
            ],
          ),
        ),
        // word list
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    _words.isEmpty ? 'No saved words' : 'No results',
                    style: const TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final e = items[i];
                    final key = normalizeKey(e.word);
                    return _WordTile(
                      entry: e,
                      onTap: () => _showDetail(e),
                      onDelete: () => _delete(key),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Study Tab ────────────────────────────────────────────────

class _StudyTab extends StatefulWidget {
  final Map<String, WordEntry> words;
  final Future<void> Function(String key) onDelete;
  final Future<void> Function(String word) onLookUp;

  const _StudyTab({
    required this.words,
    required this.onDelete,
    required this.onLookUp,
  });

  @override
  State<_StudyTab> createState() => _StudyTabState();
}

class _StudyTabState extends State<_StudyTab> {
  int _currentIndex = 0;
  bool _revealed = false;
  final _tts = FlutterTts();
  final _flashCardKey = GlobalKey<_FlashCardState>();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.65);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  void _speak(String word) => _tts.speak(word);

  List<WordEntry> get _studyWords {
    return widget.words.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
  }

  void _handleStudy(int total) {
    setState(() {
      _currentIndex = (_currentIndex + 1) % total;
      _revealed = false;
    });
  }

  void _handleKnown(String key) {
    widget.onDelete(key);
    setState(() {
      _revealed = false;
      final remaining = _studyWords.length - 1;
      if (remaining <= 0) {
        _currentIndex = 0;
      } else if (_currentIndex >= remaining) {
        _currentIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final studyWords = _studyWords;

    if (studyWords.isEmpty) {
      return const Center(
        child: Text('No saved words', style: TextStyle(color: Colors.white38)),
      );
    }

    final safeIndex = _currentIndex.clamp(0, studyWords.length - 1);
    final entry = studyWords[safeIndex];
    final key = normalizeKey(entry.word);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '${safeIndex + 1} / ${studyWords.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
        // Flashcard
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (!_revealed) {
                setState(() => _revealed = true);
                _speak(entry.word);
              }
              _flashCardKey.currentState?._clearSelection();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _FlashCard(key: _flashCardKey, entry: entry, revealed: _revealed, onSpeak: _speak, onLookUp: widget.onLookUp),
            ),
          ),
        ),
        // Buttons
        if (_revealed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: Row(
              children: [
                Expanded(
                  child: _StudyButton(
                    icon: Icons.access_time_rounded,
                    label: 'Study',
                    color: const Color(0xFF2D8C8C),
                    onTap: () => _handleStudy(studyWords.length),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StudyButton(
                    icon: Icons.delete_outline_rounded,
                    label: 'I know this',
                    color: const Color(0xFFE74C3C),
                    onTap: () => _handleKnown(key),
                  ),
                ),
              ],
            ),
          )
      ],
    );
  }
}

// ── Flashcard Widget ─────────────────────────────────────────

class _FlashCard extends StatefulWidget {
  final WordEntry entry;
  final bool revealed;
  final void Function(String word) onSpeak;
  final Future<void> Function(String word) onLookUp;

  const _FlashCard({super.key, required this.entry, required this.revealed, required this.onSpeak, required this.onLookUp});

  @override
  State<_FlashCard> createState() => _FlashCardState();
}

class _FlashCardState extends State<_FlashCard> {
  String _lastSelectedText = '';

  void _clearSelection() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  WordEntry get entry => widget.entry;
  bool get revealed => widget.revealed;
  void Function(String) get onSpeak => widget.onSpeak;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: constraints.maxHeight,
              minHeight: revealed ? 0 : constraints.maxHeight * 0.55,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A3C),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth - 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildContent(context),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    return [
            // Word + speaker (스피커는 revealed일 때만)
            GestureDetector(
              onTap: revealed ? () => onSpeak(entry.word) : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    entry.word,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: revealed ? 42 : 64,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (revealed) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.volume_up_rounded, color: Colors.white38, size: 24),
                ],
              ],
            ),
          ),
          if (revealed) ...[
            const SizedBox(height: 6),
            // Meanings by POS — 품사 옆에 뜻
            ...entry.meanings.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.pos,
                        style: const TextStyle(
                          color: Color(0xFF50E3C2),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          m.trans.join(', '),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
            // Example sentence
            if (entry.example != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    SelectionArea(
                      onSelectionChanged: (content) {
                        _lastSelectedText = content?.plainText ?? '';
                      },
                      contextMenuBuilder: (ctx, selectableRegionState) {
                        final selected = _lastSelectedText.trim();
                        final extra = selected.isNotEmpty
                            ? <ContextMenuButtonItem>[
                                ContextMenuButtonItem(
                                  onPressed: () {
                                    ContextMenuController.removeAny();
                                    widget.onLookUp(selected);
                                  },
                                  label: 'Look up',
                                ),
                              ]
                            : <ContextMenuButtonItem>[];
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: selectableRegionState.contextMenuAnchors,
                          buttonItems: [...extra, ...selectableRegionState.contextMenuButtonItems],
                        );
                      },
                      child: GestureDetector(
                        onTap: () => onSpeak(entry.example!.en),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                entry.example!.en,
                                style: const TextStyle(color: Colors.white, fontSize: 22),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.volume_up_rounded, color: Colors.white38, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.example!.trans,
                      style: const TextStyle(color: Colors.white54, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ];
  }
}

// ── Study Button ─────────────────────────────────────────────

class _StudyButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _StudyButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Word Tile (list view) ────────────────────────────────────

class _WordTile extends StatelessWidget {
  final WordEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _WordTile(
      {required this.entry, required this.onTap, required this.onDelete});

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
          style: const TextStyle(
              color: Color(0xFFCBA6F7), fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.phonetic.isNotEmpty)
              Text(entry.phonetic,
                  style: const TextStyle(
                      color: Color(0xFF89DCFF), fontSize: 12)),
            Text(entry.definition,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13)),
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
