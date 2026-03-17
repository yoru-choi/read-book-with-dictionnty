class Meaning {
  final String pos;
  final List<String> ko;

  Meaning({required this.pos, required this.ko});

  factory Meaning.fromJson(Map<String, dynamic> json) {
    return Meaning(
      pos: json['pos'] as String? ?? '',
      ko: List<String>.from(json['ko'] as List? ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'pos': pos,
    'ko': ko,
  };
}

class WordEntry {
  final String word;
  final String lemma;
  final String form;
  final String phonetic;
  final String definitionKo;
  final List<Meaning> meanings;
  final int savedAt;
  String? furigana;

  WordEntry({
    required this.word,
    required this.lemma,
    required this.form,
    required this.phonetic,
    required this.definitionKo,
    required this.meanings,
    required this.savedAt,
    this.furigana,
  });

  factory WordEntry.fromJson(Map<String, dynamic> json) {
    return WordEntry(
      word: json['word'] as String? ?? '',
      lemma: json['lemma'] as String? ?? '',
      form: json['form'] as String? ?? '',
      phonetic: json['phonetic'] as String? ?? '',
      definitionKo: json['definitionKo'] as String? ?? '',
      meanings: (json['meanings'] as List?)
              ?.map((m) => Meaning.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      savedAt:
          json['savedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      furigana: json['furigana'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'lemma': lemma,
    'form': form,
    'phonetic': phonetic,
    'definitionKo': definitionKo,
    'meanings': meanings.map((m) => m.toJson()).toList(),
    'savedAt': savedAt,
    if (furigana != null) 'furigana': furigana,
  };

  WordEntry copyWith({String? furigana}) {
    return WordEntry(
      word: word,
      lemma: lemma,
      form: form,
      phonetic: phonetic,
      definitionKo: definitionKo,
      meanings: meanings,
      savedAt: savedAt,
      furigana: furigana ?? this.furigana,
    );
  }
}

typedef WordsDict = Map<String, WordEntry>;
