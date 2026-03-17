import 'dart:convert';
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
  String _text = '';
  String _fileName = '';
  Map<String, WordEntry> _words = {};
  double _fontSize = 18.0;
  bool _furiganaVisible = true;
  bool _loading = false;

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
    final words = await AppStorage.instance.loadWords();
    final fontSize = await AppStorage.instance.loadFontSize();
    final furigana = await AppStorage.instance.loadFuriganaVisible();
    final lastText = await AppStorage.instance.loadLastText();
    if (mounted) {
      setState(() {
        _words = words;
        _fontSize = fontSize;
        _furiganaVisible = furigana;
        _text = lastText;
      });
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any, // 웹에서 custom+allowedExtensions가 버튼 먹통을 유발할 수 있음
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    // bytes 우선, 없으면 readStream 폴백 (Flutter 웹에서 필요)
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
          const SnackBar(content: Text('파일을 읽을 수 없습니다'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    // UTF-8 디코딩 (BOM 제거 포함)
    String text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    await AppStorage.instance.saveLastText(text);
    setState(() {
      _text = text;
      _fileName = file.name;
    });
  }

  Future<void> _onWordSelect(String word) async {
    if (word.trim().isEmpty) return;
    final key = normalizeKey(word);
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
      onSave: () {
        _saveWord(entry!);
        Navigator.pop(context);
      },
      onDelete: () {
        _deleteWord(key);
        Navigator.pop(context);
      },
      onFuriganaSelect: (furigana) {
        _setFurigana(key, furigana);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _saveWord(WordEntry entry) async {
    final updated = {..._words, normalizeKey(entry.word): entry};
    await AppStorage.instance.saveWords(updated);
    setState(() => _words = updated);
    _syncGist(updated);
  }

  Future<void> _deleteWord(String key) async {
    final updated = Map<String, WordEntry>.from(_words)..remove(key);
    await AppStorage.instance.saveWords(updated);
    setState(() => _words = updated);
    _syncGist(updated);
  }

  Future<void> _setFurigana(String key, String furigana) async {
    final existing = _words[key];
    if (existing == null) return;
    final updated = {..._words, key: existing.copyWith(furigana: furigana)};
    await AppStorage.instance.saveWords(updated);
    setState(() => _words = updated);
    _syncGist(updated);
  }

  void _syncGist(Map<String, WordEntry> words) {
    gist.syncToGist(words).catchError((_) {});
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
          // 후리가나 토글
          IconButton(
            icon: Icon(
              _furiganaVisible ? Icons.translate : Icons.translate_outlined,
              color: _furiganaVisible ? const Color(0xFF9B59B6) : Colors.white54,
            ),
            tooltip: '뜻 ON/OFF',
            onPressed: _toggleFurigana,
          ),
          // 폰트 축소
          IconButton(
            icon: const Icon(Icons.text_decrease, color: Colors.white70),
            onPressed: () => _adjustFont(-1),
          ),
          // 폰트 확대
          IconButton(
            icon: const Icon(Icons.text_increase, color: Colors.white70),
            onPressed: () => _adjustFont(1),
          ),
          // 파일 불러오기
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: Colors.white70),
            tooltip: 'TXT 파일 열기',
            onPressed: _pickFile,
          ),
        ],
      ),
      body: Stack(
        children: [
          _ReadView(
            text: _text,
            words: _words,
            fontSize: _fontSize,
            furiganaVisible: _furiganaVisible,
            onWordSelect: _onWordSelect,
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

// ── 읽기 뷰 ──────────────────────────────────────────────────
class _ReadView extends StatefulWidget {
  final String text;
  final Map<String, WordEntry> words;
  final double fontSize;
  final bool furiganaVisible;
  final Future<void> Function(String word) onWordSelect;

  const _ReadView({
    required this.text,
    required this.words,
    required this.fontSize,
    required this.furiganaVisible,
    required this.onWordSelect,
  });

  @override
  State<_ReadView> createState() => _ReadViewState();
}

class _ReadViewState extends State<_ReadView> {
  List<InlineSpan>? _spans; // null = 빌드 중

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(_ReadView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text ||
        old.words != widget.words ||
        old.furiganaVisible != widget.furiganaVisible ||
        old.fontSize != widget.fontSize) {
      _rebuild();
    }
  }

  Future<void> _rebuild() async {
    if (widget.text.isEmpty || widget.words.isEmpty) {
      if (mounted) setState(() => _spans = []);
      return;
    }
    if (mounted) setState(() => _spans = null);
    final spans = await _buildSpans(
        widget.text, widget.words, widget.fontSize, widget.furiganaVisible);
    if (mounted) setState(() => _spans = spans);
  }

  static Future<List<InlineSpan>> _buildSpans(
      String text,
      Map<String, WordEntry> words,
      double fontSize,
      bool furiganaVisible) async {
    final pattern = RegExp(
      '(' + words.keys.map(RegExp.escape).join('|') + ')',
      caseSensitive: false,
    );
    final base = TextStyle(color: Colors.white, fontSize: fontSize, height: 1.7);
    final spans = <InlineSpan>[];
    int cursor = 0;
    int count = 0;

    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start), style: base));
      }
      final matched = m.group(0)!;
      final entry = words[normalizeKey(matched)];
      final furigana = furiganaVisible
          ? (entry?.furigana?.isNotEmpty == true
              ? entry!.furigana
              : entry?.definitionKo)
          : null;

      if (furigana != null && furigana.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(furigana,
                  style: TextStyle(
                      fontSize: fontSize * 0.5,
                      color: const Color(0xFFF38BA8),
                      height: 1.2)),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF9B59B6).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(matched,
                    style: base.copyWith(color: const Color(0xFFCBA6F7))),
              ),
            ],
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: matched,
          style: base.copyWith(
            color: const Color(0xFFCBA6F7),
            backgroundColor:
                const Color(0xFF9B59B6).withValues(alpha: 0.25),
          ),
        ));
      }

      cursor = m.end;
      count++;
      if (count % 500 == 0) await Future.delayed(Duration.zero);
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
              'TXT 파일을 열어 읽기를 시작하세요',
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
              label: const Text('파일 열기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9B59B6),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    Widget contextMenu(BuildContext ctx, EditableTextState es) {
      final sel = es.textEditingValue.selection;
      final raw = es.textEditingValue.text;
      final selected = sel.isCollapsed ? '' : sel.textInside(raw).trim();
      final extra = selected.isNotEmpty
          ? [
              ContextMenuButtonItem(
                onPressed: () {
                  ContextMenuController.removeAny();
                  widget.onWordSelect(selected);
                },
                label: '사전 조회',
              ),
            ]
          : <ContextMenuButtonItem>[];
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: es.contextMenuAnchors,
        buttonItems: [...extra, ...es.contextMenuButtonItems],
      );
    }

    final textStyle =
        TextStyle(color: Colors.white, fontSize: widget.fontSize, height: 1.7);
    const padding = EdgeInsets.fromLTRB(16, 16, 16, 32);

    // 빌드 중이거나 저장 단어 없음 → 일반 텍스트 즉시 표시
    if (_spans == null || _spans!.isEmpty) {
      return SingleChildScrollView(
        padding: padding,
        child: SelectableText(widget.text,
            style: textStyle, contextMenuBuilder: contextMenu),
      );
    }

    return SingleChildScrollView(
      padding: padding,
      child: SelectableText.rich(
        TextSpan(style: textStyle, children: _spans),
        contextMenuBuilder: contextMenu,
      ),
    );
  }
}
