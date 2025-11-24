import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/file_scanner.dart'; 
import 'reader_screen.dart';
import 'dictionary_screen.dart'; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // We keep two lists: one for all data, one for display (filtered)
  List<FileSystemEntity> _allFiles = [];
  List<FileSystemEntity> _filteredFiles = [];
  
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Start scanning for files as soon as the app opens
    _scanFiles();
  }

  // --- AUTOMATIC SCANNING ---
  Future<void> _scanFiles() async {
    setState(() => _isLoading = true);
    
    // Call our service to scan folders
    var files = await FileScanner.scanDeviceForFiles();
    
    if (mounted) {
      setState(() {
        _allFiles = files;
        _filteredFiles = files; // Initially, show all files
        _isLoading = false;
      });
    }
  }

  // --- SEARCH LOGIC ---
  void _runFilter(String enteredKeyword) {
    List<FileSystemEntity> results = [];
    if (enteredKeyword.isEmpty) {
      // If the search field is empty, show all files
      results = _allFiles;
    } else {
      // Filter list based on file name
      results = _allFiles
          .where((file) => file.path
              .split('/')
              .last
              .toLowerCase()
              .contains(enteredKeyword.toLowerCase()))
          .toList();
    }

    // Refresh the UI with filtered results
    setState(() {
      _filteredFiles = results;
    });
  }

  // --- MANUAL PICKER (Backup option) ---
  Future<void> _pickFile() async {
    // Request storage permission
    await Permission.storage.request();
    
    // Open system file picker
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt'],
    );

    if (result != null) {
      // If user picked a file, open it immediately
      _openReader(result.files.single.path!, result.files.single.name);
    }
  }

  // --- NAVIGATION HELPERS ---
  void _openReader(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(filePath: path, fileName: name),
      ),
    );
  }

  // Open the Dictionary Screen
  void _openDictionary() {
    Navigator.pop(context); // Close the drawer first
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DictionaryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Your Library"),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanFiles,
            tooltip: "Rescan Files",
          )
        ],
      ),
      
      // --- DRAWER (This creates the Hamburger Menu ≡ in top left) ---
      drawer: Drawer(
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
            ListTile(
              leading: const Icon(Icons.library_books),
              title: const Text('My Library'),
              onTap: () => Navigator.pop(context), // Close drawer (already on home)
            ),
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('Offline Dictionary'),
              onTap: _openDictionary, // <--- Opens the Dictionary
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.settings, color: Colors.grey),
              title: Text('Settings', style: TextStyle(color: Colors.grey)),
              enabled: false, // Placeholder for future features
            ),
          ],
        ),
      ),
      
      body: Column(
        children: [
          // --- SEARCH BAR ---
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _runFilter(value),
              decoration: InputDecoration(
                labelText: 'Search files',
                suffixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
          ),

          // --- FILE LIST ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredFiles.isEmpty
                    ? _buildEmptyState()
                    : _buildFileList(),
          ),
        ],
      ),
      
      // --- FLOATING ACTION BUTTON ---
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickFile,
        label: const Text("Import File"),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    );
  }

  // Helper widget to build the list of files
  Widget _buildFileList() {
    return ListView.builder(
      itemCount: _filteredFiles.length,
      padding: const EdgeInsets.only(bottom: 80), // Space for FAB
      itemBuilder: (context, index) {
        File file = _filteredFiles[index] as File;
        String name = file.path.split('/').last;
        // Get extension (PDF/TXT)
        String ext = name.split('.').last.toUpperCase();

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.deepPurple.shade100,
              child: Text(
                ext.length > 3 ? ext.substring(0, 3) : ext, // Prevent overflow
                style: const TextStyle(fontSize: 10, color: Colors.deepPurple, fontWeight: FontWeight.bold)
              ),
            ),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
            trailing: const Icon(Icons.play_circle_fill, color: Colors.deepPurple),
            onTap: () => _openReader(file.path, name),
          ),
        );
      },
    );
  }

  // Helper widget to build the "No Files Found" view
  Widget _buildEmptyState() {
    bool isSearching = _searchController.text.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isSearching ? Icons.search_off : Icons.folder_off, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            Text(
              isSearching 
                ? "No file found matching '${_searchController.text}'" 
                : "No documents found in standard folders.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            if (!isSearching)
              const Text("Make sure you have PDFs or TXT files in your Download or Documents folder, or import one manually!", 
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)
              ),
          ],
        ),
      ),
    );
  }
}