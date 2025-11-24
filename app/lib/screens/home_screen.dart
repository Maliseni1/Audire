import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/file_scanner.dart'; 
import 'reader_screen.dart';
import 'dictionary_screen.dart'; 
import 'settings_screen.dart'; 
import 'history_screen.dart'; // <--- 1. Import History

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
      allowedExtensions: ['pdf', 'txt'],
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
    ).then((_) {
      // Refresh logic if needed when returning
    });
  }

  void _openDictionary() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => const DictionaryScreen()));
  }

  void _openSettings() {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
  }

  // <--- 2. Open History Function
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanFiles,
          )
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
                  ListTile(
                    leading: const Icon(Icons.library_books),
                    title: const Text('My Library'),
                    onTap: () => Navigator.pop(context),
                  ),
                  // <--- 3. HISTORY BUTTON ADDED
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('History'),
                    onTap: _openHistory,
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book),
                    title: const Text('Offline Dictionary'),
                    onTap: _openDictionary,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: const Text('Settings'),
                    onTap: _openSettings, 
                  ),
                ],
              ),
            ),
            // Footer Branding
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
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _runFilter(value),
              decoration: InputDecoration(
                labelText: 'Search files',
                suffixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.0)),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade100,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredFiles.isEmpty
                    ? const Center(child: Text("No documents found."))
                    : ListView.builder(
                        itemCount: _filteredFiles.length,
                        padding: const EdgeInsets.only(bottom: 80),
                        itemBuilder: (context, index) {
                          File file = _filteredFiles[index] as File;
                          String name = file.path.split('/').last;
                          String ext = name.split('.').last.toUpperCase();
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.deepPurple.shade100,
                                child: Text(ext.length > 3 ? ext.substring(0, 3) : ext, style: const TextStyle(fontSize: 10, color: Colors.deepPurple, fontWeight: FontWeight.bold)),
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
}