import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../types/word_entry.dart';
import '../utils/normalize.dart';
import '../utils/storage.dart';
import '../utils/gemini.dart' as gemini;
import '../utils/gist.dart' as gist;
import '../widgets/dict_popup.dart';

/// Full-screen OCR overlay launched via the home-button long-press (ACTION_ASSIST).
///
/// Flow:
///   1. Receives the screenshot path from [AssistActivity] via MethodChannel.
///   2. Runs ML Kit Latin OCR on the image.
///   3. Draws bounding-box overlays on the screenshot.
///   4. Tap   → look up the tapped word  → show [DictPopup] → save.
///   5. Drag  → collect words inside the drag rect → same popup → save.
class OcrOverlayScreen extends StatefulWidget {
  const OcrOverlayScreen({super.key});

  @override
  State<OcrOverlayScreen> createState() => _OcrOverlayScreenState();
}

class _OcrOverlayScreenState extends State<OcrOverlayScreen> {
  static const _channel = MethodChannel('com.readbook/assist');

  // ── image state ──────────────────────────────────────────────────────────
  String? _imagePath;
  ui.Image? _uiImage; // used for size only
  Size _imageSize = Size.zero;

  // ── OCR results ───────────────────────────────────────────────────────────
  List<_WordBox> _wordBoxes = [];

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _loadingOcr = true;
  bool _processingWord = false;
  String? _errorMsg;

  // ── storage ───────────────────────────────────────────────────────────────
  Map<String, WordEntry> _words = {};
  Map<String, bool> _hiddenWords = {};

  // ── gesture state ─────────────────────────────────────────────────────────
  Offset? _dragStart;
  Offset? _dragCurrent;

  // Updated from LayoutBuilder on every build; used inside gesture callbacks.
  _ImageLayout _layout = const _ImageLayout(1, 0, 0);

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _uiImage?.dispose();
    super.dispose();
  }

  // ── initialisation ────────────────────────────────────────────────────────

  Future<void> _init() async {
    try {
      final path = await _channel.invokeMethod<String>('getScreenshotPath');
      if (path == null || !File(path).existsSync()) {
        if (mounted) {
          setState(() {
            _loadingOcr = false;
            _errorMsg = 'Unable to capture screenshot.\nGo to Settings → Default apps → Digital assistant and select ReadBook.';
          });
        }
        return;
      }
      _imagePath = path;

      // Load words and image in parallel.
      final results = await Future.wait<dynamic>([
        AppStorage.instance.loadWords(),
        AppStorage.instance.loadHiddenWords(),
        _loadUiImage(path),
      ]);

      _words = results[0] as Map<String, WordEntry>;
      _hiddenWords = results[1] as Map<String, bool>;
      final imageData = results[2] as (ui.Image, Size);
      _uiImage = imageData.$1;
      _imageSize = imageData.$2;

      // Run on-device OCR (Latin script — English).
      final inputImage = InputImage.fromFilePath(path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      RecognizedText recognized;
      try {
        recognized = await recognizer.processImage(inputImage);
      } finally {
        await recognizer.close();
      }

      final boxes = <_WordBox>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final t = element.text.trim();
            if (t.isEmpty) continue;
            boxes.add(_WordBox(
              text: t,
              rect: element.boundingBox,
              lineText: line.text,
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _wordBoxes = boxes;
          _loadingOcr = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingOcr = false;
          _errorMsg = 'OCR error: $e';
        });
      }
    }
  }

  Future<(ui.Image, Size)> _loadUiImage(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    return (img, Size(img.width.toDouble(), img.height.toDouble()));
  }

  // ── coordinate helpers ────────────────────────────────────────────────────

  /// Compute scale + offset for BoxFit.contain mapping.
  _ImageLayout _computeLayout(Size screenSize) {
    if (_imageSize == Size.zero) return const _ImageLayout(1, 0, 0);
    final scale = min(
      screenSize.width / _imageSize.width,
      screenSize.height / _imageSize.height,
    );
    final displayW = _imageSize.width * scale;
    final displayH = _imageSize.height * scale;
    return _ImageLayout(
      scale,
      (screenSize.width - displayW) / 2,
      (screenSize.height - displayH) / 2,
    );
  }

  /// Transform an OCR rect (image pixels) to screen coordinates.
  Rect _toScreen(Rect r) => Rect.fromLTRB(
        r.left * _layout.scale + _layout.offsetX,
        r.top * _layout.scale + _layout.offsetY,
        r.right * _layout.scale + _layout.offsetX,
        r.bottom * _layout.scale + _layout.offsetY,
      );

  // ── hit testing ───────────────────────────────────────────────────────────

  /// Find the word box under [pos] (with a small 4-px inflate for easy tapping).
  _WordBox? _hitTest(Offset pos) {
    for (final box in _wordBoxes.reversed) {
      if (_toScreen(box.rect).inflate(4).contains(pos)) return box;
    }
    return null;
  }

  /// Return all word boxes whose screen rects overlap with [selRect],
  /// sorted in reading order (top-to-bottom, left-to-right).
  List<_WordBox> _boxesInSelectionRect(Rect selRect) {
    return _wordBoxes
        .where((b) => selRect.overlaps(_toScreen(b.rect)))
        .toList()
      ..sort((a, b) {
        final dy = a.rect.top.compareTo(b.rect.top);
        return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
      });
  }

  // ── word lookup helpers (mirrors reader_screen.dart) ─────────────────────

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

  Future<void> _onWordSelect(String word, String textCtx) async {
    if (word.trim().isEmpty || _processingWord) return;

    final key = _resolveKey(word);
    WordEntry? entry = _words[key];

    if (entry == null) {
      setState(() => _processingWord = true);
      entry = await gemini.fetchWordEntry(word, context: textCtx);
      if (mounted) setState(() => _processingWord = false);
    }

    if (entry == null || !mounted) return;
    final captured = entry;

    await showDictPopup(
      context: context,
      entry: captured,
      isSaved: _words.containsKey(key),
      isMeaningHidden: _hiddenWords[key] ?? false,
      onSave: () => _saveWord(captured),
      onDelete: () => _deleteWord(key),
      onFuriganaSelect: (mIdx, kIdx) => _setFurigana(key, mIdx, kIdx, captured),
      onToggleMeaningHidden: () => _toggleHiddenWord(key),
    );
  }

  // ── storage helpers (mirrors reader_screen.dart) ──────────────────────────

  Future<void> _saveWord(WordEntry entry) async {
    final updated = {..._words, normalizeKey(entry.word): entry};
    await AppStorage.instance.saveWords(updated);
    if (mounted) setState(() => _words = updated);
    gist.syncToGist(updated);
  }

  Future<void> _deleteWord(String key) async {
    final updated = Map<String, WordEntry>.from(_words)..remove(key);
    await AppStorage.instance.saveWords(updated);
    if (mounted) setState(() => _words = updated);
    gist.syncToGist(updated);
  }

  Future<void> _setFurigana(
      String key, int mIdx, int kIdx, WordEntry existing) async {
    final updated = {
      ..._words,
      key: existing.copyWith(furiganaMIdx: mIdx, furiganaKIdx: kIdx),
    };
    await AppStorage.instance.saveWords(updated);
    if (mounted) setState(() => _words = updated);
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
  }

  // ── close ─────────────────────────────────────────────────────────────────

  Future<void> _close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } catch (_) {}
  }

  // ── gesture dispatch ──────────────────────────────────────────────────────

  /// Called by onTapUp — single word lookup.
  void _handleTap(Offset pos) {
    final box = _hitTest(pos);
    if (box != null) _onWordSelect(box.text, box.lineText);
  }

  /// Called by onPanEnd — drag = phrase selection (pan never fires for taps).
  void _handlePanEnd(Offset start, Offset end) {
    final selRect = Rect.fromPoints(start, end);
    final selected = _boxesInSelectionRect(selRect);
    if (selected.isEmpty) return;
    final phrase = selected.map((b) => b.text).join(' ');
    final textCtx = selected.map((b) => b.lineText).toSet().join(' ');
    _onWordSelect(phrase, textCtx);
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingOcr) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF9B59B6)),
            SizedBox(height: 12),
            Text('Analyzing screen...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMsg!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _close, child: const Text('Close')),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        // Keep layout in sync so gesture callbacks always have fresh values.
        _layout = _computeLayout(
          Size(constraints.maxWidth, constraints.maxHeight),
        );

        return GestureDetector(
          // Tap  → single word lookup (pan does NOT fire for taps due to slop).
          onTapUp: _processingWord
              ? null
              : (d) => _handleTap(d.localPosition),
          // Drag → phrase selection (fires only when finger moves > ~25dp).
          onPanStart: _processingWord
              ? null
              : (d) => setState(() {
                    _dragStart = d.localPosition;
                    _dragCurrent = d.localPosition;
                  }),
          onPanUpdate: _processingWord
              ? null
              : (d) => setState(() => _dragCurrent = d.localPosition),
          onPanEnd: _processingWord
              ? null
              : (_) {
                  final start = _dragStart;
                  final end = _dragCurrent;
                  setState(() {
                    _dragStart = null;
                    _dragCurrent = null;
                  });
                  if (start != null && end != null) {
                    _handlePanEnd(start, end);
                  }
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── screenshot ─────────────────────────────────────────────
              if (_imagePath != null)
                Image.file(
                  File(_imagePath!),
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),

              // ── OCR bounding-box overlay ───────────────────────────────
              CustomPaint(
                painter: _WordBoxPainter(
                  wordBoxes: _wordBoxes,
                  layout: _layout,
                  dragStart: _dragStart,
                  dragCurrent: _dragCurrent,
                ),
              ),

              // ── close button ───────────────────────────────────────────
              Positioned(
                top: MediaQuery.of(ctx).padding.top + 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  onPressed: _close,
                  tooltip: 'Close',
                ),
              ),

              // ── word-count badge ───────────────────────────────────────
              if (!_loadingOcr && _wordBoxes.isNotEmpty)
                Positioned(
                  top: MediaQuery.of(ctx).padding.top + 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_wordBoxes.length} words detected',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),

              // ── "looking up" spinner ───────────────────────────────────
              if (_processingWord)
                const ColoredBox(
                  color: Color(0x66000000),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF9B59B6)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Data models ────────────────────────────────────────────────────────────

class _WordBox {
  final String text;
  final Rect rect; // in original image-pixel coordinates
  final String lineText; // full line text — used as Gemini context

  const _WordBox({
    required this.text,
    required this.rect,
    required this.lineText,
  });
}

class _ImageLayout {
  final double scale;
  final double offsetX;
  final double offsetY;

  const _ImageLayout(this.scale, this.offsetX, this.offsetY);
}

// ── CustomPainter ──────────────────────────────────────────────────────────

class _WordBoxPainter extends CustomPainter {
  final List<_WordBox> wordBoxes;
  final _ImageLayout layout;
  final Offset? dragStart;
  final Offset? dragCurrent;

  _WordBoxPainter({
    required this.wordBoxes,
    required this.layout,
    this.dragStart,
    this.dragCurrent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw subtle outlines around every recognised word.
    final outlinePaint = Paint()
      ..color = const Color(0xFF9B59B6).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final box in wordBoxes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(_toScreen(box.rect), const Radius.circular(3)),
        outlinePaint,
      );
    }

    // 2. Highlight words inside the live drag rectangle.
    if (dragStart != null && dragCurrent != null) {
      final selRect = Rect.fromPoints(dragStart!, dragCurrent!);

      final fillPaint = Paint()
        ..color = const Color(0xFF9B59B6).withValues(alpha: 0.40)
        ..style = PaintingStyle.fill;

      for (final box in wordBoxes) {
        final r = _toScreen(box.rect);
        if (selRect.overlaps(r)) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(3)),
            fillPaint,
          );
        }
      }

      // Draw the selection rectangle itself.
      final selPaint = Paint()
        ..color = const Color(0xFF9B59B6).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(selRect, const Radius.circular(4)),
        selPaint,
      );
    }
  }

  Rect _toScreen(Rect r) => Rect.fromLTRB(
        r.left * layout.scale + layout.offsetX,
        r.top * layout.scale + layout.offsetY,
        r.right * layout.scale + layout.offsetX,
        r.bottom * layout.scale + layout.offsetY,
      );

  @override
  bool shouldRepaint(_WordBoxPainter old) =>
      !identical(old.wordBoxes, wordBoxes) ||
      old.dragStart != dragStart ||
      old.dragCurrent != dragCurrent;
}
