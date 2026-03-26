import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../types/word_entry.dart';
import 'secure_storage.dart';

const _gistDescription = 'vocapin-shard';
const _kGistIdsKey = 'vocapin_gist_ids';

int _shardIndex(String word) {
  final c = word.isNotEmpty ? word[0].toLowerCase() : '';
  if (c.compareTo('t') >= 0) return 3;
  if (c.compareTo('n') >= 0) return 2;
  if (c.compareTo('g') >= 0) return 1;
  return 0;
}

Future<List<String>> _resolveGistIds(String pat) async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getStringList(_kGistIdsKey);
  if (cached != null && cached.length == 4) return cached;
  return _discoverOrCreateGistIds(pat, prefs);
}

Future<List<String>> _discoverOrCreateGistIds(String pat, SharedPreferences prefs) async {
  final allGists = <Map<String, dynamic>>[];
  int page = 1;
  while (true) {
    final res = await http.get(
      Uri.parse('https://api.github.com/gists?per_page=100&page=$page'),
      headers: {'Authorization': 'Bearer $pat'},
    );
    if (res.statusCode != 200) throw Exception('GET /gists failed: \${res.statusCode}');
    final batch = jsonDecode(res.body) as List;
    allGists.addAll(batch.cast<Map<String, dynamic>>());
    if (batch.length < 100) break;
    page++;
  }

  final vocapinGists = allGists
      .where((g) => g['description'] == _gistDescription)
      .toList()
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

  while (vocapinGists.length < 4) {
    final res = await http.post(
      Uri.parse('https://api.github.com/gists'),
      headers: {'Authorization': 'Bearer $pat', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'description': _gistDescription,
        'public': false,
        'files': {'dictionary.json': {'content': '{}'}},
      }),
    );
    if (res.statusCode != 201) throw Exception('POST /gists failed: \${res.statusCode}');
    final created = jsonDecode(res.body) as Map<String, dynamic>;
    vocapinGists.add(created);
    vocapinGists.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  }

  final ids = vocapinGists.take(4).map((g) => g['id'] as String).toList();
  await prefs.setStringList(_kGistIdsKey, ids);
  return ids;
}

/// Sync local Map to Gist via PATCH (4-shard)
Future<void> syncToGist(Map<String, WordEntry> words) async {
  final pat = await SecureStorage.instance.getGithubPat();
  if (pat == null || pat.isEmpty) return;

  // split by shard — normalize to shared voca-pin format (no Flutter-specific fields)
  final shards = [<String, dynamic>{}, <String, dynamic>{}, <String, dynamic>{}, <String, dynamic>{}];
  for (final e in words.values) {
    final json = e.toJson();
    // meanings 폴백: voca-pin 호환 (meanings가 비어있으면 definition으로 합성)
    if ((json['meanings'] as List?)?.isEmpty ?? true) {
      json['meanings'] = [{'pos': '', 'trans': [e.definition]}];
    }
    shards[_shardIndex(e.word)][e.word] = json;
  }

  Future<void> patch(List<String> ids) => Future.wait(List.generate(4, (i) async {
    final res = await http.patch(
      Uri.parse('https://api.github.com/gists/${ids[i]}'),
      headers: {'Authorization': 'Bearer $pat', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'files': {'dictionary.json': {'content': jsonEncode(shards[i])}},
      }),
    );
    if (res.statusCode == 401) throw Exception('GitHub token is invalid.');
    if (res.statusCode == 404) throw Exception('_404_');
    if (res.statusCode != 200) throw Exception('GitHub API \${res.statusCode}');
  }));

  var gistIds = await _resolveGistIds(pat);
  try {
    await patch(gistIds);
  } catch (e) {
    if (e.toString().contains('_404_')) {
      // cached IDs may be stale — clear and retry once
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kGistIdsKey);
      gistIds = await _resolveGistIds(pat);
      await patch(gistIds);
    } else {
      rethrow;
    }
  }
}

/// Fetch all words from Gist (4-shard, parallel)
Future<Map<String, WordEntry>> fetchFromGist({bool forceRefresh = false}) async {
  final pat = await SecureStorage.instance.getGithubPat();
  if (pat == null || pat.isEmpty) return {};

  if (forceRefresh) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kGistIdsKey);
  }
  final gistIds = await _resolveGistIds(pat);
  final results = await Future.wait(List.generate(4, (i) async {
    try {
      // 1) meta fetch → raw_url 추출
      final metaRes = await http.get(
        Uri.parse('https://api.github.com/gists/${gistIds[i]}'),
        headers: {'Authorization': 'Bearer $pat', 'Accept': 'application/vnd.github+json'},
      );
      if (metaRes.statusCode != 200) return <String, WordEntry>{};
      final meta = jsonDecode(metaRes.body) as Map<String, dynamic>;
      final fileInfo = (meta['files'] as Map?)?['dictionary.json'] as Map?;

      // content가 있으면 바로 사용, 없으면(truncated) raw_url로 별도 fetch
      String content;
      final inlineContent = fileInfo?['content'] as String?;
      final truncated = fileInfo?['truncated'] as bool? ?? false;

      if (inlineContent != null && !truncated) {
        content = inlineContent;
      } else {
        final rawUrl = fileInfo?['raw_url'] as String?;
        if (rawUrl == null) return <String, WordEntry>{};
        final rawRes = await http.get(
          Uri.parse(rawUrl),
          headers: {'Authorization': 'Bearer $pat'},
        );
        if (rawRes.statusCode != 200) return <String, WordEntry>{};
        content = rawRes.body;
      }

      final map = jsonDecode(content) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, WordEntry.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return <String, WordEntry>{};
    }
  }));

  return results.fold<Map<String, WordEntry>>(<String, WordEntry>{}, (acc, m) => <String, WordEntry>{...acc, ...m});
}

/// GitHub PAT connection test
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
