import 'dart:io';
import 'package:flutter/material.dart';
import '../services/file_scanner.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<FileSystemEntity> _allFiles = [];
  List<FileSystemEntity> _filteredFiles = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';

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
        _applyFilters();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    String keyword = _searchController.text.toLowerCase();
    List<FileSystemEntity> temp = _allFiles;

    if (_selectedCategory == 'Documents') {
      temp = temp
          .where(
            (f) =>
                f.path.toLowerCase().endsWith('.pdf') ||
                f.path.toLowerCase().endsWith('.docx') ||
                f.path.toLowerCase().endsWith('.txt'),
          )
          .toList();
    } else if (_selectedCategory == 'Photos') {
      temp = temp
          .where(
            (f) =>
                f.path.toLowerCase().endsWith('.jpg') ||
                f.path.toLowerCase().endsWith('.png') ||
                f.path.toLowerCase().endsWith('.jpeg'),
          )
          .toList();
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

  void _openReader(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(filePath: path, fileName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Library")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => _applyFilters(),
              decoration: InputDecoration(
                hintText: 'Search files...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                filled: true,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text("All"),
                  selected: _selectedCategory == 'All',
                  onSelected: (v) {
                    setState(() {
                      _selectedCategory = 'All';
                      _applyFilters();
                    });
                  },
                ),
                const SizedBox(width: 5),
                ChoiceChip(
                  label: const Text("Documents"),
                  selected: _selectedCategory == 'Documents',
                  onSelected: (v) {
                    setState(() {
                      _selectedCategory = 'Documents';
                      _applyFilters();
                    });
                  },
                ),
                const SizedBox(width: 5),
                ChoiceChip(
                  label: const Text("Photos"),
                  selected: _selectedCategory == 'Photos',
                  onSelected: (v) {
                    setState(() {
                      _selectedCategory = 'Photos';
                      _applyFilters();
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filteredFiles.length,
                    itemBuilder: (context, index) {
                      File file = _filteredFiles[index] as File;
                      return ListTile(
                        leading: const Icon(
                          Icons.insert_drive_file,
                          color: Colors.deepPurple,
                        ),
                        title: Text(file.path.split('/').last),
                        onTap: () =>
                            _openReader(file.path, file.path.split('/').last),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
