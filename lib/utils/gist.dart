import 'dart:convert';
import 'package:http/http.dart' as http;
import '../types/word_entry.dart';
import 'secure_storage.dart';

// voca-pin 동일 4-샤드 Gist ID (확장과 공유)
const _gistIds = [
  '6028281502864981751d17d8f6632bca', // a-f
  'adb9fc3debc0ab17cfd98bda19624867', // g-m
  '52aec8ed2befb5a18a7b589b1c0f87c2', // n-s
  '48697c33f5711a448e141566132fa8e3', // t-z
];

int _shardIndex(String word) {
  final c = word.isNotEmpty ? word[0].toLowerCase() : '';
  if (c.compareTo('t') >= 0) return 3;
  if (c.compareTo('n') >= 0) return 2;
  if (c.compareTo('g') >= 0) return 1;
  return 0;
}

/// 4-샤드 단어를 로컬 Map → Gist PATCH
Future<void> syncToGist(Map<String, WordEntry> words) async {
  final pat = await SecureStorage.instance.getGithubPat();
  if (pat == null || pat.isEmpty) return;

  // 샤드 분할
  final shards = [<String, dynamic>{}, <String, dynamic>{}, <String, dynamic>{}, <String, dynamic>{}];
  for (final e in words.values) {
    shards[_shardIndex(e.word)][e.word] = e.toJson();
  }

  await Future.wait(List.generate(4, (i) async {
    final res = await http.patch(
      Uri.parse('https://api.github.com/gists/${_gistIds[i]}'),
      headers: {
        'Authorization': 'Bearer $pat',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'files': {
          'dictionary.json': {'content': jsonEncode(shards[i])},
        },
      }),
    );
    if (res.statusCode == 401) throw Exception('GitHub 토큰이 유효하지 않습니다.');
    if (res.statusCode == 404) throw Exception('Gist를 찾을 수 없습니다. Gist ID 또는 토큰 권한을 확인하세요.');
    if (res.statusCode != 200) throw Exception('GitHub API ${res.statusCode}');
  }));
}

/// Gist에서 모든 단어 가져오기 (4-샤드 병렬)
Future<Map<String, WordEntry>> fetchFromGist() async {
  final pat = await SecureStorage.instance.getGithubPat();
  if (pat == null || pat.isEmpty) return {};

  final results = await Future.wait(List.generate(4, (i) async {
    final res = await http.get(
      Uri.parse('https://api.github.com/gists/${_gistIds[i]}'),
      headers: {'Authorization': 'Bearer $pat', 'Accept': 'application/vnd.github+json'},
    );
    if (res.statusCode != 200) return <String, WordEntry>{};
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final content = (((data['files'] as Map?)?['dictionary.json'] as Map?)?['content'] as String?) ?? '{}';
    try {
      final map = jsonDecode(content) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, WordEntry.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return <String, WordEntry>{};
    }
  }));

  return results.fold<Map<String, WordEntry>>(<String, WordEntry>{}, (acc, m) => <String, WordEntry>{...acc, ...m});
}

/// GitHub PAT 연결 테스트
Future<bool> testGithubConnection(String pat) async {
  try {
    final res = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: {'Authorization': 'Bearer $pat'},
    );
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}
