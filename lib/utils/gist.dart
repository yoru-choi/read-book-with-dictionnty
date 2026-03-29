import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../types/word_entry.dart';
import 'secure_storage.dart';

const _gistDescription = 'vocapin-data';
const _kGistIdKey = 'vocapin_gist_id';

Future<String> _resolveGistId(String pat) async {
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString(_kGistIdKey);
  if (cached != null && cached.isNotEmpty) return cached;
  return _discoverOrCreateGistId(pat, prefs);
}

Future<String> _discoverOrCreateGistId(String pat, SharedPreferences prefs) async {
  final allGists = <Map<String, dynamic>>[];
  int page = 1;
  while (true) {
    final res = await http.get(
      Uri.parse('https://api.github.com/gists?per_page=100&page=$page'),
      headers: {'Authorization': 'Bearer $pat'},
    );
    if (res.statusCode != 200) throw Exception('GET /gists failed: ${res.statusCode}');
    final batch = jsonDecode(res.body) as List;
    allGists.addAll(batch.cast<Map<String, dynamic>>());
    if (batch.length < 100) break;
    page++;
  }

  final found = allGists.cast<Map<String, dynamic>>().where((g) => g['description'] == _gistDescription).firstOrNull;
  if (found != null) {
    final id = found['id'] as String;
    await prefs.setString(_kGistIdKey, id);
    return id;
  }

  // 없으면 새로 생성
  final res = await http.post(
    Uri.parse('https://api.github.com/gists'),
    headers: {'Authorization': 'Bearer $pat', 'Content-Type': 'application/json'},
    body: jsonEncode({
      'description': _gistDescription,
      'public': false,
      'files': {'dictionary.json': {'content': '{}'}},
    }),
  );
  if (res.statusCode != 201) throw Exception('POST /gists failed: ${res.statusCode}');
  final created = jsonDecode(res.body) as Map<String, dynamic>;
  final id = created['id'] as String;
  await prefs.setString(_kGistIdKey, id);
  return id;
}

/// Sync local Map to Gist via PATCH (single Gist)
Future<void> syncToGist(Map<String, WordEntry> words) async {
  final pat = await SecureStorage.instance.getGithubPat();
  if (pat == null || pat.isEmpty) return;

  final data = <String, dynamic>{};
  for (final e in words.values) {
    final json = e.toJson();
    // meanings 폴백: voca-pin 호환 (meanings가 비어있으면 definition으로 합성)
    if ((json['meanings'] as List?)?.isEmpty ?? true) {
      json['meanings'] = [{'pos': '', 'trans': [e.definition]}];
    }
    data[e.word] = json;
  }

  Future<void> patch(String gistId) async {
    final res = await http.patch(
      Uri.parse('https://api.github.com/gists/$gistId'),
      headers: {'Authorization': 'Bearer $pat', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'files': {'dictionary.json': {'content': jsonEncode(data)}},
      }),
    );
    if (res.statusCode == 401) throw Exception('GitHub token is invalid.');
    if (res.statusCode == 404) throw Exception('_404_');
    if (res.statusCode != 200) throw Exception('GitHub API ${res.statusCode}');
  }

  var gistId = await _resolveGistId(pat);
  try {
    await patch(gistId);
  } catch (e) {
    if (e.toString().contains('_404_')) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kGistIdKey);
      gistId = await _resolveGistId(pat);
      await patch(gistId);
    } else {
      rethrow;
    }
  }
}

/// Fetch all words from Gist (single Gist)
Future<Map<String, WordEntry>> fetchFromGist({bool forceRefresh = false}) async {
  final pat = await SecureStorage.instance.getGithubPat();
  if (pat == null || pat.isEmpty) return {};

  if (forceRefresh) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kGistIdKey);
  }
  final gistId = await _resolveGistId(pat);

  try {
    final metaRes = await http.get(
      Uri.parse('https://api.github.com/gists/$gistId'),
      headers: {'Authorization': 'Bearer $pat', 'Accept': 'application/vnd.github+json'},
    );
    if (metaRes.statusCode != 200) return {};
    final meta = jsonDecode(metaRes.body) as Map<String, dynamic>;
    final fileInfo = (meta['files'] as Map?)?['dictionary.json'] as Map?;

    String content;
    final inlineContent = fileInfo?['content'] as String?;
    final truncated = fileInfo?['truncated'] as bool? ?? false;

    if (inlineContent != null && !truncated) {
      content = inlineContent;
    } else {
      final rawUrl = fileInfo?['raw_url'] as String?;
      if (rawUrl == null) return {};
      final rawRes = await http.get(
        Uri.parse(rawUrl),
        headers: {'Authorization': 'Bearer $pat'},
      );
      if (rawRes.statusCode != 200) return {};
      content = rawRes.body;
    }

    final map = jsonDecode(content) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, WordEntry.fromJson(v as Map<String, dynamic>)));
  } catch (_) {
    return {};
  }
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
