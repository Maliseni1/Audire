import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load the saved theme setting before the app starts
  final prefs = await SharedPreferences.getInstance();
  final String themeName = prefs.getString('theme_mode') ?? 'system';
  
  runApp(AudireApp(initialTheme: themeName));
}

class AudireApp extends StatefulWidget {
  final String initialTheme;
  
  // This allows us to access the theme changer from anywhere in the app
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

  const AudireApp({super.key, required this.initialTheme});

  @override
  State<AudireApp> createState() => _AudireAppState();
}

class _AudireAppState extends State<AudireApp> {
  @override
  void initState() {
    super.initState();
    // Set the initial theme based on what we loaded
    AudireApp.themeNotifier.value = _getThemeMode(widget.initialTheme);
  }

  ThemeMode _getThemeMode(String name) {
    switch (name) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AudireApp.themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'Audire',
          debugShowCheckedModeBanner: false,
          
          // --- THEME CONFIGURATION ---
          themeMode: currentMode,
          
          // Light Theme Colors
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple, 
              brightness: Brightness.light
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
          
          // Dark Theme Colors
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple, 
              brightness: Brightness.dark
            ),
            useMaterial3: true,
            // Dark mode needs specific overrides to look good
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.grey.shade900,
              foregroundColor: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
            cardColor: const Color(0xFF1E1E1E),
          ),
          
          home: const HomeScreen(),
        );
      },
    );
  }
}