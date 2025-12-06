import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:permission_handler/permission_handler.dart'; 
import '../services/file_scanner.dart'; 
import 'reader_screen.dart';
import 'dictionary_screen.dart'; 
import 'settings_screen.dart'; 
import 'history_screen.dart'; 

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

  @override
  void initState() {
    super.initState();
    _scanFiles();
  }

  Future<void> _scanFiles() async {
    setState(() => _isLoading = true);
    var files = await FileScanner.scanDeviceForFiles();
    if (mounted) {
      setState(() {
        _allFiles = files;
        _filteredFiles = files;
        _isLoading = false;
      });
    }
  }

  void _runFilter(String enteredKeyword) {
    List<FileSystemEntity> results = [];
    if (enteredKeyword.isEmpty) {
      results = _allFiles;
    } else {
      results = _allFiles
          .where((file) => file.path.split('/').last.toLowerCase().contains(enteredKeyword.toLowerCase()))
          .toList();
    }
    setState(() {
      _filteredFiles = results;
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
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (status.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Camera permission is required to scan documents."))
        );
      }
      return;
    }
    
    if (status.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Permission Required"),
            content: const Text("Camera access is permanently denied. Please enable it in your phone settings to scan documents."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), 
                child: const Text("Cancel")
              ),
              ElevatedButton(
                onPressed: () { 
                  Navigator.pop(ctx); 
                  openAppSettings(); 
                }, 
                child: const Text("Open Settings")
              ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error opening camera: $e"))
        );
      }
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

  // --- NEW: ABOUT DIALOG ---
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.audio_file, color: Colors.deepPurple),
            SizedBox(width: 10),
            Text("AUDIRE"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text("Version 2.0.0", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text("The Ultimate Offline Audio Reader."),
            SizedBox(height: 20),
            Text("Features:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
            Text("• Universal Document Reader"),
            Text("• Offline Translation (Bemba, Nyanja)"),
            Text("• Smart History & Resume"),
            SizedBox(height: 20),
            Divider(),
            SizedBox(height: 10),
            Text("Built with ❤️ by Chiza Labs"),
            Text("© 2025 All Rights Reserved", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close", style: TextStyle(color: Colors.deepPurple)),
          ),
        ],
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
              onChanged: _runFilter,
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
          ListTile(
            leading: const Icon(Icons.settings), 
            title: const Text('Settings'), 
            onTap: () { 
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen())); 
            }
          ),
          // --- CONNECTED ABOUT DIALOG ---
          ListTile(
            leading: const Icon(Icons.info_outline), 
            title: const Text('About'), 
            onTap: () { 
              Navigator.pop(context); // Close drawer first
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