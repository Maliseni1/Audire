import 'package:flutter/material.dart';
import '../services/bookmark_service.dart';
import 'reader_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  List<Map<String, dynamic>> _bookmarks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    var data = await BookmarkService.getBookmarks();
    if (mounted) {
      setState(() {
        _bookmarks = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteBookmark(int index) async {
    await BookmarkService.deleteBookmark(index);
    _loadBookmarks(); // Refresh list
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Bookmark removed"))
      );
    }
  }

  void _openBookmark(Map<String, dynamic> item) {
    // Navigate to Reader with specific start position
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(
          filePath: item['path'], 
          fileName: item['name'],
          initialIndex: item['index'], // Pass the saved position
        ),
      ),
    );
  }

  String _formatDate(int timestamp) {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bookmarks")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bookmark_border, size: 80, color: Colors.grey),
                      SizedBox(height: 10),
                      Text("No bookmarks yet.", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _bookmarks.length,
                  itemBuilder: (context, index) {
                    var item = _bookmarks[index];
                    return Dismissible(
                      key: Key(item['timestamp'].toString()),
                      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
                      direction: DismissDirection.endToStart,
                      onDismissed: (direction) => _deleteBookmark(index),
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.orange,
                            child: Icon(Icons.bookmark, color: Colors.white, size: 20),
                          ),
                          title: Text(
                            "\"${item['snippet']}\"", 
                            maxLines: 2, 
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5.0),
                            child: Text(
                              "${item['name']} • ${_formatDate(item['timestamp'])}",
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteBookmark(index),
                          ),
                          onTap: () => _openBookmark(item),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}