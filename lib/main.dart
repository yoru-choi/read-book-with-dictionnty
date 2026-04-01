import 'package:flutter/material.dart';
import 'screens/reader_screen.dart';
import 'screens/word_list_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/process_text_save_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReadBookApp());
}

class ReadBookApp extends StatelessWidget {
  const ReadBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    final initialRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;

    return MaterialApp(
      title: 'ReadBook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B59B6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      initialRoute: '/',
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => initialRoute == '/process-text'
            ? const ProcessTextSaveScreen()
            : const _Shell(),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;

  static const _screens = [
    ReaderScreen(),
    WordListScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF181825),
        indicatorColor: const Color(0xFF9B59B6),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Reader',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'Vocab',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
