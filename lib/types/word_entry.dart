class Meaning {
  final String pos;
  final List<String> trans;

  Meaning({required this.pos, required this.trans});

  factory Meaning.fromJson(Map<String, dynamic> json) {
    // migrate: 'ko' → 'trans'
    final list = json['trans'] as List? ?? json['ko'] as List? ?? [];
    return Meaning(
      pos: json['pos'] as String? ?? '',
      trans: List<String>.from(list),
    );
  }

  Map<String, dynamic> toJson() => {
    'pos': pos,
    'trans': trans,
  };
}

class Example {
  final String en;
  final String trans;

  Example({required this.en, required this.trans});

  factory Example.fromJson(Map<String, dynamic> json) {
    // migrate: 'ko' → 'trans'
    return Example(
      en: json['en'] as String? ?? '',
      trans: (json['trans'] as String? ?? json['ko'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {'en': en, 'trans': trans};
}

class WordEntry {
  final String word;
  final String lemma;
  final String form;
  final String phonetic;
  final String definition;
  final List<Meaning> meanings;
  final String sourceText;
  final Example? example;
  final int savedAt;
  int? furiganaMIdx;
  int? furiganaKIdx;

  WordEntry({
    required this.word,
    required this.lemma,
    required this.form,
    required this.phonetic,
    required this.definition,
    required this.meanings,
    this.sourceText = '',
    this.example,
    required this.savedAt,
    this.furiganaMIdx,
    this.furiganaKIdx,
  });

  String? get resolvedFurigana {
    final mIdx = furiganaMIdx ?? 0;
    final kIdx = furiganaKIdx ?? 0;
    if (mIdx >= meanings.length) return null;
    final list = meanings[mIdx].trans;
    if (kIdx >= list.length) return null;
    return list[kIdx];
  }

  factory WordEntry.fromJson(Map<String, dynamic> json) {
    final meanings = (json['meanings'] as List?)
            ?.map((m) => Meaning.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [];
    int? mIdx = json['furiganaMIdx'] as int?;
    int? kIdx = json['furiganaKIdx'] as int?;
    // legacy furigana string → migrate to index
    if (mIdx == null && json['furigana'] != null) {
      final legacy = json['furigana'] as String;
      outer:
      for (var mi = 0; mi < meanings.length; mi++) {
        for (var ki = 0; ki < meanings[mi].trans.length; ki++) {
          if (meanings[mi].trans[ki] == legacy) {
            mIdx = mi;
            kIdx = ki;
            break outer;
          }
        }
      }
    }

    // migrate: 'definitionKo' → 'definition'
    final def = json['definition'] as String? ?? json['definitionKo'] as String? ?? '';

    // migrate: 'examples' (array) → 'example' (single)
    Example? example;
    if (json['example'] is Map) {
      example = Example.fromJson(json['example'] as Map<String, dynamic>);
    } else if (json['examples'] is List && (json['examples'] as List).isNotEmpty) {
      example = Example.fromJson((json['examples'] as List).first as Map<String, dynamic>);
    }

    return WordEntry(
      word: json['word'] as String? ?? '',
      lemma: json['lemma'] as String? ?? '',
      form: json['form'] as String? ?? '',
      phonetic: json['phonetic'] as String? ?? '',
      definition: def,
      meanings: meanings,
      sourceText: json['sourceText'] as String? ?? '',
      example: example,
      savedAt:
          json['savedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      furiganaMIdx: mIdx,
      furiganaKIdx: kIdx,
    );
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'lemma': lemma,
    'form': form,
    'phonetic': phonetic,
    'definition': definition,
    'meanings': meanings.map((m) => m.toJson()).toList(),
    if (example != null) 'example': example!.toJson(),
    'savedAt': savedAt,
  };

  Map<String, dynamic> toFullJson() => {
    ...toJson(),
    if (sourceText.isNotEmpty) 'sourceText': sourceText,
    if (furiganaMIdx != null) 'furiganaMIdx': furiganaMIdx,
    if (furiganaKIdx != null) 'furiganaKIdx': furiganaKIdx,
  };

  WordEntry copyWith({int? furiganaMIdx, int? furiganaKIdx}) {
    return WordEntry(
      word: word,
      lemma: lemma,
      form: form,
      phonetic: phonetic,
      definition: definition,
      meanings: meanings,
      sourceText: sourceText,
      example: example,
      savedAt: savedAt,
      furiganaMIdx: furiganaMIdx ?? this.furiganaMIdx,
      furiganaKIdx: furiganaKIdx ?? this.furiganaKIdx,
    );
  }
}

typedef WordsDict = Map<String, WordEntry>;
