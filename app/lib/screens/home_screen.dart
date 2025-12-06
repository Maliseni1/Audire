import 'dart:io';
import 'dart:async'; // Required for Timer
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:permission_handler/permission_handler.dart'; 
import '../services/file_scanner.dart'; 
import '../services/audio_manager.dart'; // Import for globalAudioHandler
import 'reader_screen.dart';
import 'dictionary_screen.dart'; 
import 'settings_screen.dart'; 
import 'history_screen.dart'; 
import 'bookmarks_screen.dart'; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<FileSystemEntity> _allFiles = [];
  List<FileSystemEntity> _filteredFiles = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String _selectedCategory = 'All'; 
  
  // Sleep Timer State
  Timer? _sleepTimer;

  @override
  void initState() {
    super.initState();
    _scanFiles();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel(); // Clean up timer on close
    super.dispose();
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
        return path.endsWith('.pdf') || path.endsWith('.docx') || path.endsWith('.txt');
      }).toList();
    } else if (_selectedCategory == 'Photos') {
      temp = temp.where((f) {
        String path = f.path.toLowerCase();
        return path.endsWith('.jpg') || path.endsWith('.png') || path.endsWith('.jpeg');
      }).toList();
    }

    if (keyword.isNotEmpty) {
      temp = temp.where((file) => 
        file.path.split('/').last.toLowerCase().contains(keyword)
      ).toList();
    }

    setState(() {
      _filteredFiles = temp;
    });
  }

  Future<void> _pickFile() async {
    await Permission.storage.request();
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'docx', 'jpg', 'png'],
    );

    if (result != null) {
      _openReader(result.files.single.path!, result.files.single.name);
    }
  }

  Future<void> _scanDocument() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) status = await Permission.camera.request();

    if (status.isDenied) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Camera permission is required.")));
      return;
    }
    
    if (status.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Permission Required"),
            content: const Text("Camera access is permanently denied. Please enable it in Settings."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
              ElevatedButton(onPressed: () { Navigator.pop(ctx); openAppSettings(); }, child: const Text("Settings")),
            ],
          )
        );
      }
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        _openReader(photo.path, "Scanned Document");
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _openReader(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(filePath: path, fileName: name),
      ),
    ).then((_) {});
  }

  // --- SLEEP TIMER DIALOG ---
  void _showSleepTimerDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Set Sleep Timer", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                  // Show cancel button if timer is active
                  if (_sleepTimer != null && _sleepTimer!.isActive)
                    TextButton(
                      onPressed: () {
                        _sleepTimer?.cancel();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Timer Cancelled")));
                      },
                      child: const Text("Cancel", style: TextStyle(color: Colors.red)),
                    )
                ],
              ),
              const SizedBox(height: 10),
              ListTile(leading: const Icon(Icons.timer_10), title: const Text("10 Minutes"), onTap: () => _setTimer(10, ctx)),
              ListTile(leading: const Icon(Icons.timer), title: const Text("20 Minutes"), onTap: () => _setTimer(20, ctx)),
              ListTile(leading: const Icon(Icons.timelapse), title: const Text("30 Minutes"), onTap: () => _setTimer(30, ctx)),
              ListTile(leading: const Icon(Icons.hourglass_bottom), title: const Text("45 Minutes"), onTap: () => _setTimer(45, ctx)),
              ListTile(leading: const Icon(Icons.bedtime), title: const Text("60 Minutes"), onTap: () => _setTimer(60, ctx)),
            ],
          ),
        );
      }
    );
  }

  void _setTimer(int minutes, BuildContext ctx) {
    _sleepTimer?.cancel(); // Cancel existing
    Navigator.pop(ctx);
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Audio will stop in $minutes minutes")));
    
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      // Stop Audio Globally using the handler we exposed
      if (globalAudioHandler != null) {
        globalAudioHandler!.pause();
        globalAudioHandler!.stop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sleep Timer: Audio Paused")));
      }
    });
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("AUDIRE"),
        content: const Text("Version 2.0.0\nBuilt by Chiza Labs.\n\nThe Ultimate Offline Audio Reader."),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label) {
    bool isSelected = _selectedCategory == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {
          if (selected) {
            setState(() {
              _selectedCategory = label;
              _applyFilters();
            });
          }
        },
        selectedColor: Colors.deepPurple,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.deepPurple,
          fontWeight: FontWeight.bold
        ),
        backgroundColor: Colors.deepPurple.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? Colors.deepPurple : Colors.deepPurple.shade100),
        ),
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
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()))
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              onChanged: (val) => _applyFilters(), 
              decoration: InputDecoration(
                hintText: 'Search your library...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.grey[200],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
            
            const SizedBox(height: 20),
            const Text("Quick Actions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            GridView.count(
              crossAxisCount: 2, 
              shrinkWrap: true, 
              physics: const NeverScrollableScrollPhysics(), 
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.5, 
              children: [
                _buildQuickAction(Icons.camera_alt, "Scan Doc", Colors.orange, _scanDocument),
                _buildQuickAction(Icons.upload_file, "Import File", Colors.blue, _pickFile),
                _buildQuickAction(Icons.menu_book, "Dictionary", Colors.purple, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const DictionaryScreen()))),
                _buildQuickAction(Icons.history, "History", Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen()))),
              ],
            ),

            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Your Library", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _scanFiles),
              ],
            ),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  _buildCategoryChip('All'),
                  _buildCategoryChip('Documents'),
                  _buildCategoryChip('Photos'),
                ],
              ),
            ),
            
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredFiles.isEmpty
                      ? const Center(child: Text("No files found. Scan or Import one!"))
                      : ListView.builder(
                          itemCount: _filteredFiles.length,
                          padding: const EdgeInsets.only(bottom: 20),
                          itemBuilder: (context, index) {
                            File file = _filteredFiles[index] as File;
                            String name = file.path.split('/').last;
                            String ext = name.split('.').last.toUpperCase();
                            
                            IconData icon = Icons.insert_drive_file;
                            Color iconColor = Colors.grey;
                            if (ext == 'PDF') { icon = Icons.picture_as_pdf; iconColor = Colors.red; }
                            else if (ext == 'DOCX') { icon = Icons.description; iconColor = Colors.blue; }
                            else if (['JPG', 'PNG', 'JPEG'].contains(ext)) { icon = Icons.image; iconColor = Colors.purple; }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              color: isDark ? Colors.grey[900] : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.withOpacity(0.2))),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: Icon(icon, color: iconColor),
                                ),
                                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                                subtitle: Text(ext, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                onTap: () => _openReader(file.path, name),
                              ),
                            );
                          },
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
                  Text("AUDIRE", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          ListTile(leading: const Icon(Icons.library_books), title: const Text('My Library'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.history), title: const Text('History'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen())); }),
          
          ListTile(
            leading: const Icon(Icons.bookmarks), 
            title: const Text('Bookmarks'), 
            onTap: () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (context) => const BookmarksScreen())); 
            }
          ),

          ListTile(leading: const Icon(Icons.menu_book), title: const Text('Offline Dictionary'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const DictionaryScreen())); }),
          
          const Divider(),
          
          // --- NEW: SLEEP TIMER IN DRAWER ---
          ListTile(
            leading: const Icon(Icons.timer), 
            title: const Text('Sleep Timer'), 
            onTap: () { 
              Navigator.pop(context); 
              _showSleepTimerDialog(); 
            }
          ),

          ListTile(
            leading: const Icon(Icons.settings), 
            title: const Text('Settings'), 
            onTap: () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen())); 
            }
          ),
          ListTile(
            leading: const Icon(Icons.info_outline), 
            title: const Text('About'), 
            onTap: () { 
              Navigator.pop(context); 
              _showAboutDialog(); 
            }
          ),
          
          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("v2.0.0 • Chiza Labs", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}