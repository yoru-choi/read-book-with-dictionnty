import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../types/word_entry.dart';

/// Word dictionary popup modal
/// - IPA pronunciation, meanings by POS, TTS, save/furigana selection
class DictPopup extends StatefulWidget {
  final WordEntry entry;
  final bool isSaved;
  final bool isMeaningHidden;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final void Function(int mIdx, int kIdx) onFuriganaSelect;
  final VoidCallback onToggleMeaningHidden;

  const DictPopup({
    super.key,
    required this.entry,
    required this.isSaved,
    required this.isMeaningHidden,
    required this.onSave,
    required this.onDelete,
    required this.onFuriganaSelect,
    required this.onToggleMeaningHidden,
  });

  @override
  State<DictPopup> createState() => _DictPopupState();
}

class _DictPopupState extends State<DictPopup> {
  // 팝업이 열릴 때마다 새 인스턴스를 생성하지 않도록 플랑폼 레벨 싱글턴 유지
  static FlutterTts? _sharedTts;
  static bool _sharedTtsReady = false;
  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();
    if (_sharedTtsReady) {
      _ttsReady = true;
    } else {
      _initTts();
    }
  }

  Future<void> _initTts() async {
    _sharedTts ??= FlutterTts();
    await _sharedTts!.setLanguage('en-US');
    await _sharedTts!.setSpeechRate(0.85);
    _sharedTtsReady = true;
    if (mounted) setState(() => _ttsReady = true);
  }

  @override
  void dispose() {
    _sharedTts?.stop();
    super.dispose();
  }

  Future<void> _speak() async {
    final word = widget.entry.lemma.isNotEmpty ? widget.entry.lemma : widget.entry.word;
    await _sharedTts!.speak(word);
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // word + IPA + TTS
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.word,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.lemma.isNotEmpty && entry.lemma != entry.word)
                        Text(
                          '← ${entry.lemma}  ${entry.form}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (entry.phonetic.isNotEmpty)
                        Text(
                          entry.phonetic,
                          style: const TextStyle(color: Color(0xFF89DCFF), fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (entry.definition.isNotEmpty)
                        Text(
                          entry.definition,
                          style: const TextStyle(color: Color(0xFFF5C2E7), fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // TTS button
                IconButton(
                  onPressed: _ttsReady ? _speak : null,
                  icon: const Icon(Icons.volume_up_rounded, color: Colors.white70),
                  tooltip: 'Play pronunciation',
                ),
                // 개별 한글 주석 표시 토글 (저장된 경우에만)
                if (widget.isSaved)
                  IconButton(
                    onPressed: widget.onToggleMeaningHidden,
                    icon: Icon(
                      widget.isMeaningHidden ? Icons.visibility_off : Icons.visibility,
                      color: widget.isMeaningHidden ? Colors.white38 : const Color(0xFF9B59B6),
                    ),
                    tooltip: widget.isMeaningHidden ? '한글 주석 표시' : '한글 주석 숨기기',
                  ),
                // save/remove pin button
                IconButton(
                  onPressed: widget.isSaved ? widget.onDelete : widget.onSave,
                  icon: Icon(
                    widget.isSaved ? Icons.remove_circle_outline : Icons.add_circle_outline,
                    color: widget.isSaved ? const Color(0xFF9B59B6) : Colors.white54,
                  ),
                  tooltip: widget.isSaved ? 'Remove' : 'Add',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // meanings by part of speech
            ...entry.meanings.asMap().entries.map((e) => _MeaningRow(
                  mIdx: e.key,
                  meaning: e.value,
                  onSelectFurigana: widget.onFuriganaSelect,
                )),
            const SizedBox(height: 12),
            // 한글 주석 선택 안내 (저장된 경우에만)
            if (widget.isSaved)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '뜻 칩을 탭하면 한글 주석으로 표시됩니다',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MeaningRow extends StatelessWidget {
  final int mIdx;
  final Meaning meaning;
  final void Function(int mIdx, int kIdx) onSelectFurigana;

  const _MeaningRow({required this.mIdx, required this.meaning, required this.onSelectFurigana});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2, right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF313244),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              meaning.pos,
              style: const TextStyle(color: Color(0xFFA6E3A1), fontSize: 11),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: meaning.trans.asMap().entries.map((e) {
                final kIdx = e.key;
                final ko = e.value;
                return GestureDetector(
                  onTap: () => onSelectFurigana(mIdx, kIdx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF45475A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(ko, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Show popup as bottom sheet
Future<void> showDictPopup({
  required BuildContext context,
  required WordEntry entry,
  required bool isSaved,
  bool isMeaningHidden = false,
  required VoidCallback onSave,
  required VoidCallback onDelete,
  required void Function(int mIdx, int kIdx) onFuriganaSelect,
  required VoidCallback onToggleMeaningHidden,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DictPopup(
      entry: entry,
      isSaved: isSaved,
      isMeaningHidden: isMeaningHidden,
      onSave: onSave,
      onDelete: onDelete,
      onFuriganaSelect: onFuriganaSelect,
      onToggleMeaningHidden: onToggleMeaningHidden,
    ),
  );
}
