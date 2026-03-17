import 'package:flutter/material.dart';
import '../utils/secure_storage.dart';
import '../utils/gemini.dart' as gemini;
import '../utils/gist.dart' as gist;
import '../utils/storage.dart';
import 'word_list_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _geminiCtrl = TextEditingController();
  final _githubCtrl = TextEditingController();
  bool _geminiObscure = true;
  bool _githubObscure = true;
  bool _testingGemini = false;
  bool _testingGithub = false;
  bool? _geminiOk;
  bool? _githubOk;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final gKey = await SecureStorage.instance.getGeminiKey();
    final pat = await SecureStorage.instance.getGithubPat();
    if (mounted) {
      setState(() {
        _geminiCtrl.text = gKey ?? '';
        _githubCtrl.text = pat ?? '';
      });
    }
  }

  Future<void> _save() async {
    await SecureStorage.instance.setGeminiKey(_geminiCtrl.text.trim());
    await SecureStorage.instance.setGithubPat(_githubCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장됨'),
          backgroundColor: Color(0xFF9B59B6),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _testGemini() async {
    final key = _geminiCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _testingGemini = true;
      _geminiOk = null;
    });
    final ok = await gemini.testGeminiConnection(key);
    if (mounted) {
      setState(() {
        _testingGemini = false;
        _geminiOk = ok;
      });
    }
  }

  Future<void> _testGithub() async {
    final pat = _githubCtrl.text.trim();
    if (pat.isEmpty) return;
    setState(() {
      _testingGithub = true;
      _githubOk = null;
    });
    final ok = await gist.testGithubConnection(pat);
    if (mounted) {
      setState(() {
        _testingGithub = false;
        _githubOk = ok;
      });
    }
  }

  Future<void> _importFromGist() async {
    await SecureStorage.instance.setGithubPat(_githubCtrl.text.trim());
    try {
      final remote = await gist.fetchFromGist();
      final local = await AppStorage.instance.loadWords();
      final merged = {...remote, ...local}; // 로컬 우선
      await AppStorage.instance.saveWords(merged);
      WordListScreen.refreshSignal.value++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gist에서 ${remote.length}개 단어 가져옴'),
            backgroundColor: const Color(0xFF9B59B6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('가져오기 실패: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181825),
        title: const Text('설정', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('저장', style: TextStyle(color: Color(0xFF9B59B6), fontSize: 15)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // GitHub PAT
          _SectionHeader('GitHub Personal Access Token'),
          _ApiKeyField(
            controller: _githubCtrl,
            label: 'GitHub PAT (gist scope)',
            obscure: _githubObscure,
            onToggleObscure: () => setState(() => _githubObscure = !_githubObscure),
            testing: _testingGithub,
            testResult: _githubOk,
            onTest: _testGithub,
          ),
          const SizedBox(height: 24),
          // Gemini API Key
          _SectionHeader('Gemini API Key'),
          _ApiKeyField(
            controller: _geminiCtrl,
            label: 'Gemini API Key',
            obscure: _geminiObscure,
            onToggleObscure: () => setState(() => _geminiObscure = !_geminiObscure),
            testing: _testingGemini,
            testResult: _geminiOk,
            onTest: _testGemini,
          ),
          const SizedBox(height: 16),
          // Gist 가져오기
          OutlinedButton.icon(
            onPressed: _importFromGist,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Gist에서 단어 가져오기'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF89DCFF),
              side: const BorderSide(color: Color(0xFF89DCFF)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '* voca-pin 확장 프로그램과 동일한 Gist를 공유합니다',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _geminiCtrl.dispose();
    _githubCtrl.dispose();
    super.dispose();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 0.5)),
    );
  }
}

class _ApiKeyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool testing;
  final bool? testResult;
  final VoidCallback onTest;

  const _ApiKeyField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggleObscure,
    required this.testing,
    required this.testResult,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: const Color(0xFF313244),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white38),
              onPressed: onToggleObscure,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: testing ? null : onTest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF45475A),
                foregroundColor: Colors.white,
              ),
              child: testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('연결 테스트'),
            ),
            const SizedBox(width: 12),
            if (testResult != null)
              Row(
                children: [
                  Icon(
                    testResult! ? Icons.check_circle : Icons.error,
                    color: testResult! ? const Color(0xFFA6E3A1) : Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    testResult! ? '연결 성공' : '연결 실패',
                    style: TextStyle(
                      color: testResult! ? const Color(0xFFA6E3A1) : Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
