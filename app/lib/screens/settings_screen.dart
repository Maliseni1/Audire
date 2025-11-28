import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/update_service.dart'; // Ensure this file exists in lib/services/

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedTheme = 'system'; 
  bool _isCheckingUpdate = false;

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

    ThemeMode mode;
    switch (newTheme) {
      case 'light': mode = ThemeMode.light; break;
      case 'dark': mode = ThemeMode.dark; break;
      default: mode = ThemeMode.system; break;
    }
    AudireApp.themeNotifier.value = mode;
  }

  // --- UPDATE CHECK LOGIC ---
  Future<void> _checkUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Checking for updates... (Requires Internet)"),
        duration: Duration(seconds: 2),
      )
    );

    final result = await UpdateService.checkForUpdate();

    if (!mounted) return;
    setState(() {
      _isCheckingUpdate = false;
    });

    if (result.containsKey('error')) {
      _showDialog("Error", "Could not check for updates.\nCheck your internet connection or try again later.\n\nTechnical: ${result['error']}");
    } else if (result['updateAvailable'] == true) {
      _showUpdateDialog(
        result['latestVersion'], 
        result['currentVersion'], 
        result['downloadUrl'],
        result['body']
      );
    } else {
      _showDialog("Up to Date", "You are using the latest version (${result['currentVersion']}).");
    }
  }

  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      ),
    );
  }

  void _showUpdateDialog(String latest, String current, String url, String notes) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Update Available!"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("New Version: $latest", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              Text("Current: $current", style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 15),
              const Text("What's New:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(notes, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Later")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              UpdateService.launchUpdateUrl(url);
            }, 
            child: const Text("Download")
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    Color headerColor = isDarkMode ? Colors.deepPurple.shade200 : Colors.deepPurple;

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- APPEARANCE ---
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

          // --- SYSTEM SECTION (Update & About) ---
          _buildSectionHeader("System", headerColor),
          Card(
            elevation: 2,
            child: Column(
              children: [
                // THIS IS THE BUTTON YOU WERE MISSING
                ListTile(
                  leading: const Icon(Icons.system_update, color: Colors.deepPurple),
                  title: const Text("Check for Updates"),
                  subtitle: const Text("Online check via GitHub"),
                  trailing: _isCheckingUpdate 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _checkUpdate,
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(Icons.code, size: 50, color: Colors.deepPurple),
                      const SizedBox(height: 10),
                      const Text(
                        "AUDIRE",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 5),
                      const Text("The Ultimate Offline Audio Reader"),
                      const SizedBox(height: 20),
                      
                      const Text("Built with ❤️ by", style: TextStyle(color: Colors.grey, fontSize: 12)),
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
                      const Text("© 2025 All Rights Reserved", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
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
        style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }
}