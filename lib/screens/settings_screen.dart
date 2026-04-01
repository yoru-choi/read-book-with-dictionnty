import 'package:flutter/material.dart';
import '../utils/secure_storage.dart';
import '../utils/storage.dart';
import '../utils/gemini.dart' as gemini;
import '../utils/gist.dart' as gist;

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
  String _nativeLang = 'ko';

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final gKey = await SecureStorage.instance.getGeminiKey();
    final pat = await SecureStorage.instance.getGithubPat();
    final lang = await AppStorage.instance.loadNativeLang();
    if (mounted) {
      setState(() {
        _geminiCtrl.text = gKey ?? '';
        _githubCtrl.text = pat ?? '';
        _nativeLang = lang;
      });
    }
  }

  Future<void> _testGemini() async {
    final key = _geminiCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _testingGemini = true;
      _geminiOk = null;
    });
    await SecureStorage.instance.setGeminiKey(key);
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
    await SecureStorage.instance.setGithubPat(pat);
    final ok = await gist.testGithubConnection(pat);
    if (mounted) {
      setState(() {
        _testingGithub = false;
        _githubOk = ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181825),
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Native Language
          _SectionHeader('Native Language'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF313244),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _nativeLang,
                isExpanded: true,
                dropdownColor: const Color(0xFF313244),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: const [
                  DropdownMenuItem(value: 'ko', child: Text('Korean')),
                  DropdownMenuItem(value: 'ja', child: Text('Japanese')),
                  DropdownMenuItem(value: 'zh', child: Text('Chinese')),
                  DropdownMenuItem(value: 'es', child: Text('Spanish')),
                  DropdownMenuItem(value: 'fr', child: Text('French')),
                  DropdownMenuItem(value: 'de', child: Text('German')),
                  DropdownMenuItem(value: 'vi', child: Text('Vietnamese')),
                  DropdownMenuItem(value: 'th', child: Text('Thai')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _nativeLang = v);
                    AppStorage.instance.saveNativeLang(v);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 8),
          const Text(
            '* Shares the same Gist as the voca-pin extension\n* Words are auto-imported from Gist on app startup',
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
                  : const Text('Test connection'),
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
                    testResult! ? 'Connected' : 'Failed',
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
