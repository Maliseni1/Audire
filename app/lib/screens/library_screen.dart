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

  void _openReader(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(filePath: path, fileName: name),
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
          fontWeight: FontWeight.bold,
        ),
        backgroundColor: Colors.deepPurple.shade50,
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : Colors.deepPurple.withValues(alpha: 0.2),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Your Library",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
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
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          // 2. Categories
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildCategoryChip('All'),
                _buildCategoryChip('Documents'),
                _buildCategoryChip('Photos'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),

          // 3. List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredFiles.isEmpty
                ? const Center(child: Text("No files found."))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20, top: 10),
                    itemCount: _filteredFiles.length,
                    itemBuilder: (context, index) {
                      File file = _filteredFiles[index] as File;
                      String name = file.path.split('/').last;

                      IconData icon = Icons.insert_drive_file;
                      Color color = Colors.grey;
                      if (name.toLowerCase().endsWith('.pdf')) {
                        icon = Icons.picture_as_pdf;
                        color = Colors.red;
                      } else if (name.toLowerCase().endsWith('.docx')) {
                        icon = Icons.description;
                        color = Colors.blue;
                      } else if (name.toLowerCase().endsWith('.jpg')) {
                        icon = Icons.image;
                        color = Colors.purple;
                      } else if (name.toLowerCase().endsWith('.png')) {
                        icon = Icons.image;
                        color = Colors.purple;
                      }

                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: color),
                        ),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openReader(file.path, name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
