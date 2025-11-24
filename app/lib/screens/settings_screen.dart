import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Import main to access the themeNotifier

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedTheme = 'system'; // system, light, dark

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedTheme = prefs.getString('theme_mode') ?? 'system';
    });
  }

  Future<void> _updateTheme(String newTheme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', newTheme);

    setState(() {
      _selectedTheme = newTheme;
    });

    // Notify the main app to rebuild
    ThemeMode mode;
    switch (newTheme) {
      case 'light': mode = ThemeMode.light; break;
      case 'dark': mode = ThemeMode.dark; break;
      default: mode = ThemeMode.system; break;
    }
    AudireApp.themeNotifier.value = mode;
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    Color headerColor = isDarkMode ? Colors.deepPurple.shade200 : Colors.deepPurple;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- APPEARANCE SECTION ---
          _buildSectionHeader("Appearance", headerColor),
          Card(
            elevation: 2,
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text("System Default"),
                  value: 'system',
                  groupValue: _selectedTheme,
                  activeColor: Colors.deepPurple,
                  onChanged: (val) => _updateTheme(val!),
                ),
                RadioListTile<String>(
                  title: const Text("Light Mode"),
                  value: 'light',
                  groupValue: _selectedTheme,
                  activeColor: Colors.deepPurple,
                  onChanged: (val) => _updateTheme(val!),
                ),
                RadioListTile<String>(
                  title: const Text("Dark Mode"),
                  value: 'dark',
                  groupValue: _selectedTheme,
                  activeColor: Colors.deepPurple,
                  onChanged: (val) => _updateTheme(val!),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // --- ABOUT SECTION (BRANDING) ---
          _buildSectionHeader("About", headerColor),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Icon(Icons.code, size: 50, color: Colors.deepPurple),
                  const SizedBox(height: 10),
                  const Text(
                    "AUDIRE v1.0.0",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  const Text("The Ultimate Offline Audio Reader"),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),
                  
                  // CHIZA LABS BRANDING
                  const Text(
                    "Built with ❤️ by",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Chiza Labs",
                    style: TextStyle(
                      fontSize: 22, 
                      fontWeight: FontWeight.bold, 
                      color: isDarkMode ? Colors.white : Colors.black87
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "© 2025 All Rights Reserved",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}