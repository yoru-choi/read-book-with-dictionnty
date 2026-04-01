import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../types/word_entry.dart';

/// Word dictionary popup modal
/// - IPA pronunciation, meanings by POS, TTS, save/gloss selection
class DictPopup extends StatefulWidget {
  final WordEntry entry;
  final bool isSaved;
  final bool isMeaningHidden;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final void Function(int mIdx, int kIdx) onGlossSelect;
  final VoidCallback onToggleMeaningHidden;

  const DictPopup({
    super.key,
    required this.entry,
    required this.isSaved,
    required this.isMeaningHidden,
    required this.onSave,
    required this.onDelete,
    required this.onGlossSelect,
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
  late bool _saved;
  late bool _meaningHidden;
  int? _selectedMIdx;
  int? _selectedKIdx;

  @override
  void initState() {
    super.initState();
    _saved = widget.isSaved;
    _meaningHidden = widget.isMeaningHidden;
    _selectedMIdx = widget.entry.glossMIdx ?? 0;
    _selectedKIdx = widget.entry.glossKIdx ?? 0;
    if (_sharedTtsReady) {
      _ttsReady = true;
    } else {
      _initTts();
    }
  }

  Future<void> _initTts() async {
    _sharedTts ??= FlutterTts();
    await _sharedTts!.setLanguage('en-US');
    await _sharedTts!.setSpeechRate(0.60);
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
    final screenHeight = MediaQuery.of(context).size.height;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: screenHeight * 0.35,
        maxHeight: screenHeight * 0.85,
      ),
      child: Container(
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
            // drag handle + close button
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 20),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                // 개별 뜻 표시 토글 (저장된 경우에만)
                if (_saved)
                  IconButton(
                    onPressed: () {
                      widget.onToggleMeaningHidden();
                      setState(() => _meaningHidden = !_meaningHidden);
                    },
                    icon: Icon(
                      _meaningHidden ? Icons.visibility_off : Icons.visibility,
                      color: _meaningHidden ? Colors.white38 : const Color(0xFF9B59B6),
                    ),
                    tooltip: _meaningHidden ? 'Show meaning' : 'Hide meaning',
                  ),
                // save/remove button
                IconButton(
                  onPressed: () {
                    if (_saved) {
                      widget.onDelete();
                    } else {
                      widget.onSave();
                    }
                    setState(() => _saved = !_saved);
                  },
                  icon: Icon(
                    _saved ? Icons.remove_circle_outline : Icons.add_circle_outline,
                    color: _saved ? const Color(0xFF9B59B6) : Colors.white54,
                  ),
                  tooltip: _saved ? 'Remove' : 'Save',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // meanings by part of speech
            ...entry.meanings.asMap().entries.map((e) => _MeaningRow(
                  mIdx: e.key,
                  meaning: e.value,
                  selectedMIdx: _selectedMIdx,
                  selectedKIdx: _selectedKIdx,
                  onSelectGloss: _saved
                      ? (mIdx, kIdx) {
                          widget.onGlossSelect(mIdx, kIdx);
                          setState(() {
                            _selectedMIdx = mIdx;
                            _selectedKIdx = kIdx;
                          });
                        }
                      : null,
                )),
            const SizedBox(height: 12),
            // 주석 선택 안내 (저장된 경우에만)
            if (_saved)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Tap a meaning to pin it above the word',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _MeaningRow extends StatelessWidget {
  final int mIdx;
  final Meaning meaning;
  final int? selectedMIdx;
  final int? selectedKIdx;
  final void Function(int mIdx, int kIdx)? onSelectGloss;

  const _MeaningRow({
    required this.mIdx,
    required this.meaning,
    required this.selectedMIdx,
    required this.selectedKIdx,
    this.onSelectGloss,
  });

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
                final enabled = onSelectGloss != null;
                final isSelected = enabled && mIdx == selectedMIdx && kIdx == selectedKIdx;
                return GestureDetector(
                  onTap: enabled ? () => onSelectGloss!(mIdx, kIdx) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF45475A),
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
  required void Function(int mIdx, int kIdx) onGlossSelect,
  required VoidCallback onToggleMeaningHidden,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DictPopup(
      entry: entry,
      isSaved: isSaved,
      isMeaningHidden: isMeaningHidden,
      onSave: onSave,
      onDelete: onDelete,
      onGlossSelect: onGlossSelect,
      onToggleMeaningHidden: onToggleMeaningHidden,
    ),
  );
}
