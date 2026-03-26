import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../types/word_entry.dart';
import '../utils/normalize.dart';
import '../utils/storage.dart';
import '../utils/gemini.dart' as gemini;
import '../utils/gist.dart' as gist;
import '../widgets/dict_popup.dart';
import 'word_list_screen.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final GlobalKey<_ReadViewState> _readViewKey = GlobalKey<_ReadViewState>();
  String _text = '';
  String _fileName = '';
  Map<String, WordEntry> _words = {};
  Map<String, bool> _hiddenWords = {};
  double _fontSize = 18.0;
  bool _furiganaVisible = true;
  bool _loading = false;
  int _currentPage = 0;
  int _totalPages = 1;
  int _initialPage = 0;
  List<Map<String, dynamic>> _bookmarks = [];

  String _docIdFor(String text, String fileName) {
    final head = text.isEmpty ? '' : text.substring(0, min(40, text.length));
    return '$fileName|${text.length}|$head';
  }

  String get _docId => _docIdFor(_text, _fileName);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    WordListScreen.refreshSignal.addListener(_reloadWords);
  }

  @override
  void dispose() {
    WordListScreen.refreshSignal.removeListener(_reloadWords);
    super.dispose();
  }

  Future<void> _reloadWords() async {
    final words = await AppStorage.instance.loadWords();
    if (mounted) setState(() => _words = words);
  }

  Future<void> _loadPrefs() async {
    // 병렬로 모든 설정 로드
    final results = await Future.wait<dynamic>([
      AppStorage.instance.loadWords(),
      AppStorage.instance.loadHiddenWords(),
      AppStorage.instance.loadFontSize(),
      AppStorage.instance.loadFuriganaVisible(),
      AppStorage.instance.loadLastText(),
      AppStorage.instance.loadLastFileName(),
      AppStorage.instance.loadReaderPages(),
      AppStorage.instance.loadReaderBookmarks(),
    ]);
    final words = results[0] as Map<String, WordEntry>;
    final hidden = results[1] as Map<String, bool>;
    final fontSize = results[2] as double;
    final furigana = results[3] as bool;
    final lastText = results[4] as String;
    final lastFileName = results[5] as String;
    final pageMap = results[6] as Map<String, int>;
    final bookmarkMap = results[7] as Map<String, List<Map<String, dynamic>>>;
    final docId = _docIdFor(lastText, lastFileName);
    if (mounted) {
      setState(() {
        _words = words;
        _hiddenWords = hidden;
        _fontSize = fontSize;
        _furiganaVisible = furigana;
        _text = lastText;
        _fileName = lastFileName;
        _initialPage = pageMap[docId] ?? 0;
        _bookmarks = List<Map<String, dynamic>>.from(bookmarkMap[docId] ?? [])
          ..sort((a, b) => (b['savedAt'] as int).compareTo(a['savedAt'] as int));
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any, // custom+allowedExtensions can cause button issues on web
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    // bytes first, fall back to readStream if null (needed on Flutter web)
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.readStream != null) {
      final chunks = <int>[];
      await for (final chunk in file.readStream!) {
        chunks.addAll(chunk);
      }
      bytes = Uint8List.fromList(chunks);
    }

    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read the file'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    // UTF-8 decode (strip BOM if present)
    String text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    await AppStorage.instance.saveLastText(text);
    await AppStorage.instance.saveLastFileName(file.name);
    final pageMap = await AppStorage.instance.loadReaderPages();
    final bookmarkMap = await AppStorage.instance.loadReaderBookmarks();
    final docId = _docIdFor(text, file.name);
    setState(() {
      _text = text;
      _fileName = file.name;
      _initialPage = pageMap[docId] ?? 0;
      _bookmarks = List<Map<String, dynamic>>.from(bookmarkMap[docId] ?? [])
        ..sort((a, b) => (b['savedAt'] as int).compareTo(a['savedAt'] as int));
    });
  }

  Future<void> _onPageChanged(int page, int total) async {
    if (!mounted) return;
    setState(() {
      _currentPage = page;
      _totalPages = total;
    });
    if (_text.isNotEmpty) {
      await AppStorage.instance.saveReaderPage(_docId, page);
    }
  }

  Future<void> _addBookmark() async {
    if (_text.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Remove existing bookmark for same page, add new entry with fresh timestamp
    final updated = _bookmarks.where((b) => b['page'] != _currentPage).toList();
    updated.add({'page': _currentPage, 'savedAt': now});
    updated.sort((a, b) => (b['savedAt'] as int).compareTo(a['savedAt'] as int));
    await AppStorage.instance.saveReaderBookmarks(_docId, updated);
    if (mounted) {
      setState(() => _bookmarks = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bookmark saved: page ${_currentPage + 1}')),
      );
    }
  }

  Future<void> _openBookmarks() async {
    if (_bookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bookmarks yet')),
      );
      return;
    }

    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (ctx) {
        // newest first (already sorted, snapshot for safety)
        final sorted = List<Map<String, dynamic>>.from(_bookmarks)
          ..sort((a, b) => (b['savedAt'] as int).compareTo(a['savedAt'] as int));
        return SafeArea(
          child: ListView.separated(
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
            itemBuilder: (_, i) {
              final bm = sorted[i];
              final page = bm['page'] as int;
              final savedAt = bm['savedAt'] as int;
              final dt = savedAt > 0
                  ? DateTime.fromMillisecondsSinceEpoch(savedAt)
                  : null;
              final dateStr = dt != null
                  ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}'
                  : '';
              final label = dateStr.isEmpty
                  ? 'Page ${page + 1}'
                  : 'Page ${page + 1} · $dateStr';
              return ListTile(
                title: Text(label, style: const TextStyle(color: Colors.white)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white54),
                  onPressed: () async {
                    final updated = _bookmarks
                        .where((b) => !(b['page'] == page && b['savedAt'] == savedAt))
                        .toList();
                    await AppStorage.instance.saveReaderBookmarks(_docId, updated);
                    if (mounted) setState(() => _bookmarks = updated);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                onTap: () => Navigator.pop(ctx, page),
              );
            },
          ),
        );
      },
    );

    if (picked != null) {
      _readViewKey.currentState?.jumpToPage(picked);
    }
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

  Future<void> _onWordSelect(String word) async {
    if (word.trim().isEmpty) return;
    final key = _resolveKey(word);
    WordEntry? entry = _words[key];

    if (entry == null) {
      setState(() => _loading = true);
      final idx = _text.indexOf(word);
      final ctx = idx >= 0 ? extractContext(_text, idx) : '';
      entry = await gemini.fetchWordEntry(word, context: ctx);
      setState(() => _loading = false);
    }

    if (entry == null || !mounted) return;

    await showDictPopup(
      context: context,
      entry: entry,
      isSaved: _words.containsKey(key),
      isMeaningHidden: _hiddenWords.containsKey(key),
      onSave: () {
        _saveWord(entry!);
        Navigator.pop(context);
      },
      onDelete: () {
        _deleteWord(key);
        Navigator.pop(context);
      },
      onFuriganaSelect: (mIdx, kIdx) {
        _setFurigana(key, mIdx, kIdx);
        Navigator.pop(context);
      },
      onToggleMeaningHidden: () {
        _toggleHiddenWord(key);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _saveWord(WordEntry entry) async {
    final updated = {..._words, normalizeKey(entry.word): entry};
    await AppStorage.instance.saveWords(updated);
    setState(() => _words = updated);
    WordListScreen.refreshSignal.value++;
    _syncGist(updated);
  }

  Future<void> _deleteWord(String key) async {
    final updated = Map<String, WordEntry>.from(_words)..remove(key);
    await AppStorage.instance.saveWords(updated);
    setState(() => _words = updated);
    WordListScreen.refreshSignal.value++;
    _syncGist(updated);
  }

  Future<void> _setFurigana(String key, int mIdx, int kIdx) async {
    final existing = _words[key];
    if (existing == null) return;
    final updated = {..._words, key: existing.copyWith(furiganaMIdx: mIdx, furiganaKIdx: kIdx)};
    await AppStorage.instance.saveWords(updated);
    setState(() => _words = updated);
    _syncGist(updated);
  }

  Future<void> _toggleHiddenWord(String key) async {
    final updated = Map<String, bool>.from(_hiddenWords);
    if (updated.containsKey(key)) {
      updated.remove(key);
    } else {
      updated[key] = true;
    }
    await AppStorage.instance.saveHiddenWords(updated);
    setState(() => _hiddenWords = updated);
  }

  void _syncGist(Map<String, WordEntry> words) {
    gist.syncToGist(words).catchError((_) {});
  }

  Widget _appBarIcon(IconData icon, VoidCallback? onPressed, {Color color = Colors.white70}) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: 20,
        icon: Icon(icon, color: onPressed == null ? Colors.white24 : color),
        onPressed: onPressed,
      ),
    );
  }

  void _adjustFont(double delta) {
    final newSize = (_fontSize + delta).clamp(12.0, 28.0);
    setState(() => _fontSize = newSize);
    AppStorage.instance.saveFontSize(newSize);
  }

  void _toggleFurigana() {
    setState(() => _furiganaVisible = !_furiganaVisible);
    AppStorage.instance.saveFuriganaVisible(_furiganaVisible);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181825),
        title: Text(
          _fileName.isEmpty ? 'ReadBook' : _fileName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                '${_currentPage + 1}/$_totalPages',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ),
          _appBarIcon(Icons.bookmark_add_outlined, _text.isEmpty ? null : _addBookmark),
          _appBarIcon(Icons.bookmarks_outlined, _openBookmarks),
          _appBarIcon(
            _furiganaVisible ? Icons.translate : Icons.translate_outlined,
            _toggleFurigana,
            color: _furiganaVisible ? const Color(0xFF9B59B6) : Colors.white54,
          ),
          _appBarIcon(Icons.text_decrease, () => _adjustFont(-1)),
          _appBarIcon(Icons.text_increase, () => _adjustFont(1)),
          _appBarIcon(Icons.folder_open_rounded, _pickFile),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          _ReadView(
            key: _readViewKey,
            text: _text,
            words: _words,
            hiddenWords: _hiddenWords,
            fontSize: _fontSize,
            furiganaVisible: _furiganaVisible,
            onWordSelect: _onWordSelect,
            initialPage: _initialPage,
            onPageChanged: _onPageChanged,
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF9B59B6)),
            ),
        ],
      ),
    );
  }
}

// ── Reader View ─────────────────────────────────────────────
class _ReadView extends StatefulWidget {
  final String text;
  final Map<String, WordEntry> words;
  final Map<String, bool> hiddenWords;
  final double fontSize;
  final bool furiganaVisible;
  final Future<void> Function(String word) onWordSelect;
  final int initialPage;
  final Future<void> Function(int page, int total) onPageChanged;

  const _ReadView({
    super.key,
    required this.text,
    required this.words,
    required this.hiddenWords,
    required this.fontSize,
    required this.furiganaVisible,
    required this.onWordSelect,
    required this.initialPage,
    required this.onPageChanged,
  });

  @override
  State<_ReadView> createState() => _ReadViewState();
}

class _ReadViewState extends State<_ReadView> {
  static const _baseCharsPerPage = 1700;
  late ScrollController _scrollController;
  List<String> _pages = [];
  List<GlobalKey> _pageKeys = [];
  double? _estimatedPageHeight; // 페이지 1개 높이 추정치 (lazy 스크롤 추적용)
  List<List<InlineSpan>?>? _pageSpans; // null = building
  int _currentPage = 0;

  String _lastSelectedText = '';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _rebuild(keepPage: false);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ReadView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _rebuild(keepPage: false);
      return;
    }
    if (old.words != widget.words ||
        old.hiddenWords != widget.hiddenWords ||
        old.furiganaVisible != widget.furiganaVisible ||
        old.fontSize != widget.fontSize) {
      _rebuild(keepPage: true);
    }
  }

  int _charsPerPage(double fontSize) {
    final scaled = (_baseCharsPerPage * (18.0 / fontSize)).round();
    return scaled.clamp(700, 2600);
  }

  List<String> _paginateText(String text, int charsPerPage) {
    if (text.isEmpty) return [];
    final pages = <String>[];
    int start = 0;
    while (start < text.length) {
      int end = min(start + charsPerPage, text.length);
      if (end < text.length) {
        final seekStart = max(start + (charsPerPage * 0.6).round(), start);
        final newline = text.lastIndexOf('\n', end);
        final space = text.lastIndexOf(' ', end);
        if (newline >= seekStart) {
          end = newline + 1;
        } else if (space >= seekStart) {
          end = space + 1;
        }
      }
      pages.add(text.substring(start, end));
      start = end;
    }
    return pages;
  }

  Future<void> jumpToPage(int page) async {
    if (_pages.isEmpty || !_scrollController.hasClients) return;
    final target = page.clamp(0, _pages.length - 1);
    final hgt = _estimatedPageHeight;
    final dest = hgt != null && hgt > 0
        ? (target * hgt).clamp(0.0, _scrollController.position.maxScrollExtent)
        : _scrollController.position.maxScrollExtent *
            (_pages.length <= 1 ? 0.0 : target / (_pages.length - 1));
    await _scrollController.animateTo(
      dest,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onScroll() {
    final hgt = _estimatedPageHeight;
    if (hgt == null || hgt <= 0 || _pages.isEmpty) return;
    final page = (_scrollController.offset / hgt).floor().clamp(0, _pages.length - 1);
    if (page != _currentPage) {
      _currentPage = page;
      widget.onPageChanged(page, max(1, _pages.length));
    }
  }

  Future<void> _rebuild({required bool keepPage}) async {
    if (widget.text.isEmpty) {
      if (mounted) {
        setState(() {
          _pages = [];
          _pageSpans = [];
          _pageKeys = [];
          _currentPage = 0;
        });
      }
      await widget.onPageChanged(0, 1);
      return;
    }
    if (mounted) setState(() => _pageSpans = null);

    final pages = _paginateText(widget.text, _charsPerPage(widget.fontSize));

    // lemmaIndex + RegExp를 모든 페이지에 공유되는 1회 사전 계산
    Map<String, String> lemmaIndex = {};
    RegExp? highlightPattern;
    if (widget.words.isNotEmpty) {
      for (final e in widget.words.entries) {
        final lemma = normalizeKey(e.value.lemma);
        if (lemma.isNotEmpty && !widget.words.containsKey(lemma) && !lemmaIndex.containsKey(lemma)) {
          lemmaIndex[lemma] = e.key;
        }
      }
      final allPatterns = {...widget.words.keys, ...lemmaIndex.keys}.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      if (allPatterns.isNotEmpty) {
        highlightPattern = RegExp(
          '(' + allPatterns.map(RegExp.escape).join('|') + ')',
          caseSensitive: false,
        );
      }
    }

    final spansByPage = <List<InlineSpan>?>[];
    for (final p in pages) {
      if (highlightPattern == null) {
        spansByPage.add([]);
      } else {
        spansByPage.add(await _buildSpans(
          p, widget.fontSize, highlightPattern,
          widget.words, widget.hiddenWords, lemmaIndex, widget.furiganaVisible,
        ));
      }
    }

    final target = pages.isEmpty
        ? 0
        : (keepPage ? _currentPage : widget.initialPage).clamp(0, pages.length - 1);

    if (!mounted) return;
    setState(() {
      _pages = pages;
      _estimatedPageHeight = null;
      _pageSpans = spansByPage;
      _pageKeys = List.generate(pages.length, (_) => GlobalKey());
      _currentPage = target;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _pages.isEmpty) return;
      _measurePageHeight();
      if (!keepPage) {
        final hgt = _estimatedPageHeight;
        final dest = hgt != null && hgt > 0
            ? (target * hgt).clamp(0.0, _scrollController.position.maxScrollExtent)
            : _scrollController.position.maxScrollExtent *
                (_pages.length <= 1 ? 0.0 : target / (_pages.length - 1));
        _scrollController.jumpTo(dest);
      }
      _onScroll();
    });
    await widget.onPageChanged(target, max(1, pages.length));
  }

  /// 현재 화면에 렌더링된 페이지 중 하나의 높이를 측정해 _estimatedPageHeight를 갱신.
  /// ListView.separated는 화면 밖 항목을 빌드하지 않으므로
  /// 보이는 항목 키를 순회하며 첫 번째 측정 성공 시 종료한다.
  void _measurePageHeight() {
    for (final key in _pageKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.size.height > 0) {
        // 페이지 패딩(16+32=48) + 구분자(~28) 포함 슬롯 높이
        _estimatedPageHeight = box.size.height + 28;
        return;
      }
    }
  }

  static Future<List<InlineSpan>> _buildSpans(
    String text,
    double fontSize,
    RegExp pattern,
    Map<String, WordEntry> words,
    Map<String, bool> hiddenWords,
    Map<String, String> lemmaIndex,
    bool showFurigana,
  ) async {
    final base = TextStyle(color: Colors.white, fontSize: fontSize, height: 1.7);
    final highlighted = base.copyWith(color: const Color(0xFFFF9800));
    final furiganaSize = fontSize * 0.6;
    final spans = <InlineSpan>[];
    int cursor = 0;
    int count = 0;

    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start), style: base));
      }

      final matched = m.group(0)!;
      String? furigana;
      if (showFurigana) {
        final nk = normalizeKey(matched);
        final resolvedKey = words.containsKey(nk) ? nk : (lemmaIndex[nk] ?? nk);
        if (!hiddenWords.containsKey(resolvedKey)) {
          final entry = words[resolvedKey];
          furigana = entry?.resolvedFurigana ?? entry?.definition;
          if (furigana != null && furigana.isEmpty) furigana = null;
        }
      }

      if (furigana != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _RubySpan(
            word: matched,
            furigana: furigana,
            wordStyle: highlighted,
            furiganaSize: furiganaSize,
          ),
        ));
      } else {
        spans.add(TextSpan(text: matched, style: highlighted));
      }

      cursor = m.end;
      count++;
      if (count % 200 == 0) await Future.delayed(Duration.zero);
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: base));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_rounded, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Open a TXT file to start reading',
              style: TextStyle(color: Colors.white38, fontSize: 15),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                final state =
                    context.findAncestorStateOfType<_ReaderScreenState>();
                state?._pickFile();
              },
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Open File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9B59B6),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    final textStyle =
        TextStyle(color: Colors.white, fontSize: widget.fontSize, height: 1.7);
    final strut = StrutStyle(
      fontSize: widget.fontSize,
      height: 1.7,
      forceStrutHeight: true,
    );
    const padding = EdgeInsets.fromLTRB(16, 16, 16, 32);

    if (_pageSpans == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF9B59B6)),
      );
    }

    if (_pages.isEmpty) {
      return const SizedBox.shrink();
    }

    return SelectionArea(
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
                    widget.onWordSelect(selected);
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
      child: ListView.separated(
        controller: _scrollController,
        cacheExtent: 1200,
        itemCount: _pages.length,
        separatorBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Expanded(child: Divider(color: Colors.white24, thickness: 1)),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF313244),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Page ${i + 1}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
              const Expanded(child: Divider(color: Colors.white24, thickness: 1)),
            ],
          ),
        ),
        itemBuilder: (_, i) {
          final spans = _pageSpans![i];
          // Text.rich는 RenderParagraph를 사용 → TextPainter 측정과 동일한 좌표 체계
          final textWidget = spans == null || spans.isEmpty
              ? Text(_pages[i], style: textStyle, strutStyle: strut)
              : Text.rich(
                  TextSpan(style: textStyle, children: spans),
                  strutStyle: strut,
                );
          return Padding(
            key: _pageKeys[i],
            padding: padding,
            child: textWidget,
          );
        },
      ),
    );
  }
}

// ── Ruby (furigana) 인라인 위젯 ─────────────────────────────────────
// WidgetSpan 안에서 단어 크기만큼만 공간을 차지하면서
// furigana를 단어 바로 위로 Clip.none Stack으로 그린다.
// SizedBox가 단어 텍스트 크기만 점유 → 줄 높이(strut)에 영향 없음.

class _RubySpan extends StatelessWidget {
  final String word;
  final String furigana;
  final TextStyle wordStyle;
  final double furiganaSize;

  const _RubySpan({
    required this.word,
    required this.furigana,
    required this.wordStyle,
    required this.furiganaSize,
  });

  @override
  Widget build(BuildContext context) {
    // 단어 크기 측정
    final wordPainter = TextPainter(
      text: TextSpan(text: word, style: wordStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final wordW = wordPainter.width;
    final wordH = wordPainter.height;
    wordPainter.dispose();

    final rubyStyle = TextStyle(
      fontSize: furiganaSize,
      color: const Color(0xFFFF9800),
      height: 1.0,
    );

    // SizedBox로 WidgetSpan의 점유 크기를 단어 크기에 고정.
    // Stack(Clip.none)으로 furigana가 위로 넘쳐 보인다.
    return SizedBox(
      width: wordW,
      height: wordH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 단어 (하단에 고정) — textScaler 끔 (부모 Text.rich가 이미 적용)
          Positioned(
            left: 0,
            bottom: 0,
            child: Text(word, style: wordStyle, textScaler: TextScaler.noScaling),
          ),
          // 한글 뜻 (단어 바로 위)
          Positioned(
            left: 0,
            bottom: wordH * 0.75,
            child: Text(furigana, style: rubyStyle, textScaler: TextScaler.noScaling),
          ),
        ],
      ),
    );
  }
}

