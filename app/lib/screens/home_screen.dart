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
import 'library_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<FileSystemEntity> _allFiles = [];
  List<FileSystemEntity> _filteredFiles = [];
  bool _isLoading = true;
  bool _hasPermission = false;

  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String _selectedCategory = 'All';

  Timer? _sleepTimer;
  Map<String, dynamic>? _dailyWord;

  @override
  void initState() {
    super.initState();
    _scanFiles();
    _loadDailyWord();
    _checkPermissionAndScan(silent: true);
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissionAndScan({bool silent = false}) async {
    bool granted =
        await Permission.manageExternalStorage.isGranted ||
        await Permission.storage.isGranted;
    if (granted) {
      if (mounted) setState(() => _hasPermission = true);
      _scanFiles();
    } else {
      if (mounted) setState(() => _hasPermission = false);
      if (!silent) await _requestPermissions();
    }
  }

  Future<void> _requestPermissions() async {
    if (await Permission.manageExternalStorage.request().isGranted ||
        await Permission.storage.request().isGranted) {
      setState(() => _hasPermission = true);
      _scanFiles();
    } else {
      if (mounted) openAppSettings();
    }
  }

  Future<void> _loadDailyWord() async {
    var word = await DailyWordService.getTodaysWord();
    if (mounted) setState(() => _dailyWord = word);
  }

  Future<void> _scanFiles() async {
    setState(() => _isLoading = true);
    var files = await FileScanner.scanDeviceForFiles();
    if (mounted) {
      setState(() {
        _allFiles = files;
        _applyFilters();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    String keyword = _searchController.text.toLowerCase();
    List<FileSystemEntity> temp = _allFiles;

    if (_selectedCategory == 'Documents') {
      temp = temp.where((f) {
        String path = f.path.toLowerCase();
        return path.endsWith('.pdf') ||
            path.endsWith('.docx') ||
            path.endsWith('.txt');
      }).toList();
    } else if (_selectedCategory == 'Photos') {
      temp = temp.where((f) {
        String path = f.path.toLowerCase();
        return path.endsWith('.jpg') ||
            path.endsWith('.png') ||
            path.endsWith('.jpeg');
      }).toList();
    }

    if (keyword.isNotEmpty) {
      temp = temp
          .where(
            (file) => file.path.split('/').last.toLowerCase().contains(keyword),
          )
          .toList();
    }

    setState(() {
      _filteredFiles = temp;
    });
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'docx', 'jpg', 'png'],
    );
    if (result != null)
      _openReader(result.files.single.path!, result.files.single.name);
  }

  Future<void> _scanDocument() async {
    if (await Permission.camera.request().isGranted) {
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
              const Text(
                "Set Sleep Timer",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.timer_10),
                title: const Text("10 Minutes"),
                onTap: () => _setTimer(10, ctx),
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text("30 Minutes"),
                onTap: () => _setTimer(30, ctx),
              ),
              if (_sleepTimer?.isActive ?? false)
                ListTile(
                  leading: const Icon(Icons.cancel, color: Colors.red),
                  title: const Text(
                    "Cancel Timer",
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    _sleepTimer?.cancel();
                    Navigator.pop(ctx);
                  },
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Stopping in $minutes mins")));
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      if (globalAudioHandler != null) {
        globalAudioHandler!.pause();
        globalAudioHandler!.stop();
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

  // --- UPDATED "ALIVE" QUICK ACTION ---
  Widget _buildQuickAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 4,
      shadowColor: color.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.2),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
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
      ),
    );
  }

  Widget _buildCategoryChip(String label) {
    bool isSelected = _selectedCategory == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {
          if (selected)
            setState(() {
              _selectedCategory = label;
              _applyFilters();
            });
        },
        selectedColor: Colors.deepPurple,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.deepPurple,
          fontWeight: FontWeight.bold,
        ),
        backgroundColor: Colors.white,
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : Colors.deepPurple.withValues(alpha: 0.2),
        ),
        elevation: isSelected ? 2 : 0,
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
          // MAIN CONTENT
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  // Word of the Day Widget
                  if (_dailyWord != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20, top: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.deepPurple.shade400,
                            Colors.deepPurple.shade700,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.deepPurple.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Word of the Day",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _dailyWord!['word'],
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _dailyWord!['meaning'],
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "\"${_dailyWord!['example']}\"",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),

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
                  const SizedBox(height: 100), // Space for sheet
                ],
              ),
            ),
          ),

          // DRAGGABLE LIBRARY SHEET (FIXED: Handle pulls sheet)
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.12,
            maxChildSize: 0.95,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.grey[50],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 15,
                      color: Colors.black.withValues(alpha: 0.2),
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ListView(
                  controller:
                      scrollController, // Single controller for everything ensures drag works everywhere
                  padding: EdgeInsets.zero,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 5,
                      ),
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

                    // Categories (Now inside sheet)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          _buildCategoryChip('All'),
                          _buildCategoryChip('Documents'),
                          _buildCategoryChip('Photos'),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Content
                    if (!_hasPermission)
                      Padding(
                        padding: const EdgeInsets.all(40.0),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.lock,
                              size: 40,
                              color: Colors.grey,
                            ),
                            const Text("Permission needed to show files."),
                          ],
                        ),
                      )
                    else if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_filteredFiles.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Center(child: Text("No files found.")),
                      )
                    else
                      // Since we are inside a ListView already, we use spread operator or builder logic carefully
                      // But ListView inside ListView is bad.
                      // Solution: We are using a single ListView for the whole sheet.
                      // We map the files to widgets here.
                      ..._filteredFiles.map((file) {
                        String name = file.path.split('/').last;
                        IconData icon = Icons.insert_drive_file;
                        Color color = Colors.grey;
                        if (name.endsWith('.pdf')) {
                          icon = Icons.picture_as_pdf;
                          color = Colors.red;
                        } else if (name.endsWith('.docx')) {
                          icon = Icons.description;
                          color = Colors.blue;
                        } else if (name.endsWith('.jpg')) {
                          icon = Icons.image;
                          color = Colors.purple;
                        }

                        return ListTile(
                          leading: Icon(icon, color: color),
                          title: Text(name),
                          onTap: () => _openReader(file.path, name),
                        );
                      }).toList(),

                    // Bottom Padding
                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        // Changed to ListView to prevent overflow
        padding: EdgeInsets.zero,
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
            leading: const Icon(Icons.bar_chart),
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
            title: const Text('Exit App', style: TextStyle(color: Colors.red)),
            onTap: _exitApp,
          ),
        ],
      ),
    );
  }
}
