import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
  
  // CATEGORY STATE
  String _selectedCategory = 'All'; // Options: All, Documents, Photos

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
        _applyFilters(); // Apply category + search logic immediately
        _isLoading = false;
      });
    }
  }

  // --- CENTRAL FILTER LOGIC ---
  void _applyFilters() {
    String keyword = _searchController.text.toLowerCase();
    
    // Start with all files
    List<FileSystemEntity> temp = _allFiles;

    // 1. Filter by Category
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

    // 2. Filter by Search Keyword
    if (keyword.isNotEmpty) {
      temp = temp.where((file) => 
        file.path.split('/').last.toLowerCase().contains(keyword)
      ).toList();
    }

    setState(() {
      _filteredFiles = temp;
    });
  }

  // MANUAL PICKER
  Future<void> _pickFile() async {
    await Permission.storage.request();
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // Allow all supported types
      allowedExtensions: ['pdf', 'txt', 'docx', 'jpg', 'png', 'jpeg'],
    );

    if (result != null) {
      _openReader(result.files.single.path!, result.files.single.name);
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

  // MENU FUNCTIONS
  void _openDictionary() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => const DictionaryScreen()));
  }
  void _openSettings() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
  }
  void _openHistory() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Your Library"),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _scanFiles)
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const DrawerHeader(
                    decoration: BoxDecoration(color: Colors.deepPurple),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.audio_file, color: Colors.white, size: 50),
                        SizedBox(height: 10),
                        Text("AUDIRE", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  ListTile(leading: const Icon(Icons.library_books), title: const Text('My Library'), onTap: () => Navigator.pop(context)),
                  ListTile(leading: const Icon(Icons.history), title: const Text('History'), onTap: _openHistory),
                  ListTile(leading: const Icon(Icons.menu_book), title: const Text('Offline Dictionary'), onTap: _openDictionary),
                  const Divider(),
                  ListTile(leading: const Icon(Icons.settings), title: const Text('Settings'), onTap: _openSettings),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Text("Powered by", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text("Chiza Labs", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _applyFilters(),
              decoration: InputDecoration(
                labelText: 'Search files',
                suffixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.0)),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade100,
              ),
            ),
          ),

          // --- CATEGORY CHIPS ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                _buildCategoryChip('All'),
                const SizedBox(width: 8),
                _buildCategoryChip('Documents'),
                const SizedBox(width: 8),
                _buildCategoryChip('Photos'),
              ],
            ),
          ),

          // File List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredFiles.isEmpty
                    ? const Center(child: Text("No items found."))
                    : ListView.builder(
                        itemCount: _filteredFiles.length,
                        padding: const EdgeInsets.only(bottom: 80),
                        itemBuilder: (context, index) {
                          File file = _filteredFiles[index] as File;
                          String name = file.path.split('/').last;
                          String ext = name.split('.').last.toUpperCase();
                          
                          // Dynamic Icons based on file type
                          IconData fileIcon = Icons.insert_drive_file;
                          if (['JPG', 'PNG', 'JPEG'].contains(ext)) fileIcon = Icons.image;
                          else if (ext == 'PDF') fileIcon = Icons.picture_as_pdf;
                          else if (ext == 'DOCX') fileIcon = Icons.description;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.deepPurple.shade100,
                                child: Icon(fileIcon, color: Colors.deepPurple, size: 20),
                              ),
                              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                              trailing: const Icon(Icons.play_circle_fill, color: Colors.deepPurple),
                              onTap: () => _openReader(file.path, name),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickFile,
        label: const Text("Import File"),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    );
  }

  // Helper for Chips
  Widget _buildCategoryChip(String label) {
    bool isSelected = _selectedCategory == label;
    return ChoiceChip(
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
      // Light purple background for unselected state
      backgroundColor: Colors.deepPurple.shade50, 
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? Colors.deepPurple : Colors.deepPurple.shade100),
      ),
    );
  }
}