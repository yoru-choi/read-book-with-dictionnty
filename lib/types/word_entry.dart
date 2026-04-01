class Meaning {
  final String pos;
  final List<String> trans;

  Meaning({required this.pos, required this.trans});

  factory Meaning.fromJson(Map<String, dynamic> json) {
    final list = json['trans'] as List? ?? [];
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
    return Example(
      en: json['en'] as String? ?? '',
      trans: json['trans'] as String? ?? '',
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
  int? glossMIdx;
  int? glossKIdx;

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
    this.glossMIdx,
    this.glossKIdx,
  });

  String? get resolvedGloss {
    final mIdx = glossMIdx ?? 0;
    final kIdx = glossKIdx ?? 0;
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
    final mIdx = json['glossMIdx'] as int?;
    final kIdx = json['glossKIdx'] as int?;

    final def = json['definition'] as String? ?? '';

    final example = json['example'] is Map
        ? Example.fromJson(json['example'] as Map<String, dynamic>)
        : null;

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
      glossMIdx: mIdx,
      glossKIdx: kIdx,
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
    if (glossMIdx != null) 'glossMIdx': glossMIdx,
    if (glossKIdx != null) 'glossKIdx': glossKIdx,
  };

  WordEntry copyWith({int? glossMIdx, int? glossKIdx}) {
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
      glossMIdx: glossMIdx ?? this.glossMIdx,
      glossKIdx: glossKIdx ?? this.glossKIdx,
    );
  }
}

typedef WordsDict = Map<String, WordEntry>;
