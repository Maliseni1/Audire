import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/file_scanner.dart';
import '../services/audio_manager.dart';
import '../services/daily_word_service.dart';
import 'reader_screen.dart';
import 'dictionary_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'bookmarks_screen.dart';
import 'stats_screen.dart';
import 'library_screen.dart'; // Import for View All

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // We keep a small preview list here
  List<FileSystemEntity> _recentFiles = [];
  bool _isLoading = true;
  bool _hasPermission = false;

  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Timer? _sleepTimer;
  Map<String, dynamic>? _dailyWord;

  @override
  void initState() {
    super.initState();
    _loadDailyWord();
    // Check Permissions quietly first. If granted, scan. If not, wait for user action in UI.
    _checkPermissionAndScan(silent: true);
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissionAndScan({bool silent = false}) async {
    // Check status of storage permissions
    // Android 11+ uses ManageExternalStorage, older uses Storage
    bool granted = false;
    if (await Permission.manageExternalStorage.isGranted) {
      granted = true;
    } else if (await Permission.storage.isGranted) {
      granted = true;
    }

    if (granted) {
      if (mounted) setState(() => _hasPermission = true);
      _scanFiles();
    } else {
      if (mounted) setState(() => _hasPermission = false);
      if (!silent) {
        // If not silent (user clicked button), request them
        await _requestPermissions();
      }
    }
  }

  Future<void> _requestPermissions() async {
    // Try requesting appropriate permission
    if (await Permission.manageExternalStorage.request().isGranted) {
      setState(() => _hasPermission = true);
      _scanFiles();
    } else if (await Permission.storage.request().isGranted) {
      setState(() => _hasPermission = true);
      _scanFiles();
    } else {
      // Still denied
      if (mounted) {
        openAppSettings(); // Guide user to settings if permanently denied or stuck
      }
    }
  }

  Future<void> _loadDailyWord() async {
    var word = await DailyWordService.getTodaysWord();
    if (mounted) {
      setState(() {
        _dailyWord = word;
      });
    }
  }

  Future<void> _scanFiles() async {
    setState(() => _isLoading = true);
    var files = await FileScanner.scanDeviceForFiles();
    if (mounted) {
      setState(() {
        // Just show top 5-10 here for performance in the sheet
        _recentFiles = files.take(10).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    // Standard picker handles its own temporary permission usually
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'docx', 'jpg', 'png'],
    );
    if (result != null) {
      _openReader(result.files.single.path!, result.files.single.name);
    }
  }

  Future<void> _scanDocument() async {
    var status = await Permission.camera.request();
    if (status.isGranted) {
      try {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
        );
        if (photo != null) _openReader(photo.path, "Scanned Document");
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } else {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Camera permission required")),
        );
    }
  }

  void _openReader(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(filePath: path, fileName: name),
      ),
    );
  }

  Future<void> _exitApp() async {
    if (globalAudioHandler != null) await globalAudioHandler!.stop();
    SystemNavigator.pop();
  }

  void _showSleepTimerDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Set Sleep Timer",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  if (_sleepTimer != null && _sleepTimer!.isActive)
                    TextButton(
                      onPressed: () {
                        _sleepTimer?.cancel();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Timer Cancelled")),
                        );
                      },
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.timer_10),
                title: const Text("10 Minutes"),
                onTap: () => _setTimer(10, ctx),
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text("20 Minutes"),
                onTap: () => _setTimer(20, ctx),
              ),
              ListTile(
                leading: const Icon(Icons.timelapse),
                title: const Text("30 Minutes"),
                onTap: () => _setTimer(30, ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  void _setTimer(int minutes, BuildContext ctx) {
    _sleepTimer?.cancel();
    Navigator.pop(ctx);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Audio will stop in $minutes minutes")),
    );
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      if (globalAudioHandler != null) {
        globalAudioHandler!.pause();
        globalAudioHandler!.stop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sleep Timer: Audio Paused")),
        );
      }
    });
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("AUDIRE"),
        content: const Text("Version 2.1.0\nBuilt by Chiza Labs."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Audire Home"),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          // --- MAIN BACKGROUND CONTENT ---
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  // Search (Navigates to full library mostly, or we could link it to library screen)
                  TextField(
                    controller: _searchController,
                    readOnly: true, // Make it a button to open library
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LibraryScreen(),
                      ),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search your library...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.grey[800] : Colors.grey[200],
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),

                  // Word of the Day
                  if (_dailyWord != null) _buildWordOfTheDay(),

                  const SizedBox(height: 20),
                  const Text(
                    "Quick Actions",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.5,
                    children: [
                      _buildQuickAction(
                        Icons.camera_alt,
                        "Scan Doc",
                        Colors.orange,
                        _scanDocument,
                      ),
                      _buildQuickAction(
                        Icons.upload_file,
                        "Import File",
                        Colors.blue,
                        _pickFile,
                      ),
                      _buildQuickAction(
                        Icons.menu_book,
                        "Dictionary",
                        Colors.purple,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DictionaryScreen(),
                          ),
                        ),
                      ),
                      _buildQuickAction(
                        Icons.history,
                        "History",
                        Colors.green,
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HistoryScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 100), // Space for bottom sheet
                ],
              ),
            ),
          ),

          // --- DRAGGABLE LIBRARY SHEET ---
          DraggableScrollableSheet(
            initialChildSize: 0.4, // Starts covering 40% of screen
            minChildSize: 0.15, // Header visible
            maxChildSize: 0.95, // Almost full screen
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 10,
                      color: Colors.black.withValues(alpha: 0.2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10),
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Your Library",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (!_hasPermission)
                            TextButton(
                              onPressed: () => _checkPermissionAndScan(),
                              child: const Text("Allow Access"),
                            ),
                        ],
                      ),
                    ),
                    const Divider(),
                    // List or Permission Warning
                    Expanded(
                      child: !_hasPermission
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.lock_outline,
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text("Storage permission needed"),
                                  TextButton(
                                    onPressed: () => _checkPermissionAndScan(),
                                    child: const Text("Grant Access"),
                                  ),
                                ],
                              ),
                            )
                          : _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              controller:
                                  scrollController, // Important: Connects scrolling to sheet drag
                              itemCount: _recentFiles.length + 1,
                              itemBuilder: (context, index) {
                                if (index == _recentFiles.length) {
                                  // View All button at bottom
                                  return Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: ElevatedButton(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const LibraryScreen(),
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.deepPurple,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text("View Full Library"),
                                    ),
                                  );
                                }
                                File file = _recentFiles[index] as File;
                                String name = file.path.split('/').last;

                                // Simple Icon logic
                                IconData icon = Icons.insert_drive_file;
                                if (name.toLowerCase().endsWith('.pdf'))
                                  icon = Icons.picture_as_pdf;
                                else if (name.toLowerCase().endsWith('.docx'))
                                  icon = Icons.description;
                                else if (name.toLowerCase().endsWith('.jpg'))
                                  icon = Icons.image;

                                return ListTile(
                                  leading: Icon(icon, color: Colors.deepPurple),
                                  title: Text(name),
                                  onTap: () => _openReader(file.path, name),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWordOfTheDay() {
    if (_dailyWord == null) return const SizedBox.shrink();

    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 20, top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.deepPurple.shade900.withValues(alpha: 0.5)
            : Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Word of the Day",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              Text(
                _dailyWord!['language'] ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _dailyWord!['word'] ?? '',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            _dailyWord!['meaning'] ?? '',
            style: const TextStyle(fontSize: 16, color: Colors.deepPurple),
          ),
          const SizedBox(height: 10),
          Text(
            "\"${_dailyWord!['example'] ?? ''}\"",
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.audio_file, color: Colors.white, size: 50),
                  Text(
                    "AUDIRE",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.library_books),
            title: const Text('My Library'),
            onTap: () => Navigator.pop(context),
          ),

          ListTile(
            leading: const Icon(Icons.bar_chart, color: Colors.deepPurple),
            title: const Text('Your Progress'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StatsScreen()),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.bookmarks),
            title: const Text('Bookmarks'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BookmarksScreen(),
                ),
              );
            },
          ),

          ListTile(
            leading: const Icon(Icons.menu_book),
            title: const Text('Offline Dictionary'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DictionaryScreen(),
                ),
              );
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.timer),
            title: const Text('Sleep Timer'),
            onTap: () {
              Navigator.pop(context);
              _showSleepTimerDialog();
            },
          ),

          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              _showAboutDialog();
            },
          ),

          const Divider(),

          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            title: const Text(
              'Exit App',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: _exitApp,
          ),

          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text(
              "v2.1.0 • Chiza Labs",
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
