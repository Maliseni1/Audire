import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedTheme = 'system';
  bool _isCheckingUpdate = false;

  // New Personalization Settings
  double _defaultSpeed = 0.5;
  double _defaultPitch = 1.0;
  bool _keepScreenOn = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedTheme = prefs.getString('theme_mode') ?? 'system';
        _defaultSpeed = prefs.getDouble('default_speed') ?? 0.5;
        _defaultPitch = prefs.getDouble('default_pitch') ?? 1.0;
        _keepScreenOn = prefs.getBool('keep_screen_on') ?? false;
      });
    }
  }

  Future<void> _updateTheme(String newTheme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', newTheme);
    if (mounted) {
      setState(() {
        _selectedTheme = newTheme;
      });
    }

    ThemeMode mode;
    switch (newTheme) {
      case 'light':
        mode = ThemeMode.light;
        break;
      case 'dark':
        mode = ThemeMode.dark;
        break;
      default:
        mode = ThemeMode.system;
        break;
    }
    AudireApp.themeNotifier.value = mode;
  }

  // --- SAVE NEW PREFERENCES ---
  Future<void> _saveDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _checkUpdate() async {
    setState(() => _isCheckingUpdate = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Checking for updates..."),
        duration: Duration(seconds: 1),
      ),
    );

    final result = await UpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (result.containsKey('error')) {
      _showDialog("Info", "Could not check updates: ${result['error']}");
    } else if (result['updateAvailable'] == true) {
      _showUpdateDialog(
        result['latestVersion'],
        result['currentVersion'],
        result['downloadUrl'],
        result['body'],
      );
    } else {
      _showDialog(
        "Up to Date",
        "Version ${result['currentVersion']} is the latest.",
      );
    }
  }

  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(
    String latest,
    String current,
    String url,
    String notes,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Update Available!"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("New: $latest  (Current: $current)"),
              const SizedBox(height: 10),
              const Text(
                "Changes:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(notes),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Later"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              UpdateService.launchUpdateUrl(url);
            },
            child: const Text("Download"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color headerColor = isDark ? Colors.deepPurple.shade200 : Colors.deepPurple;

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- READER PREFERENCES ---
          _buildSectionHeader("Reader Defaults", headerColor),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speed, color: Colors.grey),
                      const SizedBox(width: 10),
                      Text(
                        "Default Speed: ${_defaultSpeed.toStringAsFixed(1)}x",
                      ),
                    ],
                  ),
                  Slider(
                    value: _defaultSpeed,
                    min: 0.1,
                    max: 2.0,
                    divisions: 19,
                    label: _defaultSpeed.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() => _defaultSpeed = v);
                      _saveDouble('default_speed', v);
                    },
                  ),

                  // Pitch Slider
                  Row(
                    children: [
                      const Icon(Icons.graphic_eq, color: Colors.grey),
                      const SizedBox(width: 10),
                      Text(
                        "Default Pitch: ${_defaultPitch.toStringAsFixed(1)}",
                      ),
                    ],
                  ),
                  Slider(
                    value: _defaultPitch,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _defaultPitch.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() => _defaultPitch = v);
                      _saveDouble('default_pitch', v);
                    },
                  ),

                  const Divider(),
                  SwitchListTile(
                    title: const Text("Keep Screen On"),
                    subtitle: const Text(
                      "Prevent phone from sleeping while reading",
                    ),
                    secondary: const Icon(Icons.screen_lock_portrait),
                    value: _keepScreenOn,
                    activeColor: Colors.deepPurple,
                    onChanged: (v) {
                      setState(() => _keepScreenOn = v);
                      _saveBool('keep_screen_on', v);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // --- APPEARANCE ---
          _buildSectionHeader("Appearance", headerColor),
          Card(
            elevation: 1,
            child: Column(
              children: [
                RadioListTile(
                  title: const Text("System Default"),
                  value: 'system',
                  groupValue: _selectedTheme,
                  activeColor: Colors.deepPurple,
                  onChanged: (v) => _updateTheme(v!),
                ),
                RadioListTile(
                  title: const Text("Light Mode"),
                  value: 'light',
                  groupValue: _selectedTheme,
                  activeColor: Colors.deepPurple,
                  onChanged: (v) => _updateTheme(v!),
                ),
                RadioListTile(
                  title: const Text("Dark Mode"),
                  value: 'dark',
                  groupValue: _selectedTheme,
                  activeColor: Colors.deepPurple,
                  onChanged: (v) => _updateTheme(v!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- SYSTEM ---
          _buildSectionHeader("System", headerColor),
          Card(
            elevation: 1,
            child: ListTile(
              leading: const Icon(
                Icons.system_update,
                color: Colors.deepPurple,
              ),
              title: const Text("Check for Updates"),
              subtitle: const Text("Online check via GitHub"),
              trailing: _isCheckingUpdate
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _checkUpdate,
            ),
          ),

          const SizedBox(height: 30),
          const Center(
            child: Text("Audire v2.1.0", style: TextStyle(color: Colors.grey)),
          ),
          const SizedBox(height: 10),
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
