import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../types/word_entry.dart';

/// 단어 사전 팝업 모달
/// - IPA 발음, 품사별 한글 뜻, TTS, 저장/후리가나 선택
class DictPopup extends StatefulWidget {
  final WordEntry entry;
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final void Function(String furigana) onFuriganaSelect;

  const DictPopup({
    super.key,
    required this.entry,
    required this.isSaved,
    required this.onSave,
    required this.onDelete,
    required this.onFuriganaSelect,
  });

  @override
  State<DictPopup> createState() => _DictPopupState();
}

class _DictPopupState extends State<DictPopup> {
  final _tts = FlutterTts();
  bool _ttsReady = false;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.85);
    if (mounted) setState(() => _ttsReady = true);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak() async {
    final word = widget.entry.lemma.isNotEmpty ? widget.entry.lemma : widget.entry.word;
    await _tts.speak(word);
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
            // 드래그 핸들
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
            // 단어 + IPA + TTS
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
                      ),
                      if (entry.lemma.isNotEmpty && entry.lemma != entry.word)
                        Text(
                          '← ${entry.lemma}  ${entry.form}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      if (entry.phonetic.isNotEmpty)
                        Text(
                          entry.phonetic,
                          style: const TextStyle(color: Color(0xFF89DCFF), fontSize: 14),
                        ),
                    ],
                  ),
                ),
                // TTS 버튼
                IconButton(
                  onPressed: _ttsReady ? _speak : null,
                  icon: const Icon(Icons.volume_up_rounded, color: Colors.white70),
                  tooltip: '발음 듣기',
                ),
                // 저장/삭제 핀 버튼
                IconButton(
                  onPressed: widget.isSaved ? widget.onDelete : widget.onSave,
                  icon: Icon(
                    widget.isSaved ? Icons.push_pin : Icons.push_pin_outlined,
                    color: widget.isSaved ? const Color(0xFF9B59B6) : Colors.white54,
                  ),
                  tooltip: widget.isSaved ? '저장 해제' : '저장',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 품사별 뜻 목록
            ...entry.meanings.map((m) => _MeaningRow(meaning: m, onSelectFurigana: widget.onFuriganaSelect)),
            const SizedBox(height: 12),
            // 후리가나 선택 안내 (저장된 경우에만)
            if (widget.isSaved)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '뜻 칩을 탭하면 하이라이트 위에 표시됩니다',
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
  final Meaning meaning;
  final void Function(String) onSelectFurigana;

  const _MeaningRow({required this.meaning, required this.onSelectFurigana});

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
              children: meaning.ko.map((ko) {
                return GestureDetector(
                  onTap: () => onSelectFurigana(ko),
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

/// 하단 시트로 팝업 표시
Future<void> showDictPopup({
  required BuildContext context,
  required WordEntry entry,
  required bool isSaved,
  required VoidCallback onSave,
  required VoidCallback onDelete,
  required void Function(String furigana) onFuriganaSelect,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DictPopup(
      entry: entry,
      isSaved: isSaved,
      onSave: onSave,
      onDelete: onDelete,
      onFuriganaSelect: onFuriganaSelect,
    ),
  );
}
