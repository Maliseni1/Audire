import 'package:flutter/material.dart';
import '../services/history_service.dart';
import 'reader_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    var data = await HistoryService.getHistory();
    if (mounted) {
      setState(() {
        _history = data;
        _isLoading = false;
      });
    }
  }

  void _openReader(String path, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(filePath: path, fileName: name),
      ),
    ).then((_) => _loadHistory()); // Refresh list when coming back
  }

  Future<void> _clearHistory() async {
    await HistoryService.clearHistory();
    _loadHistory();
  }

  // Simple date formatter helper
  String _formatDate(int timestamp) {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    // Format: DD/MM HH:MM (e.g., 26/11 14:30)
    return "${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("History"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearHistory,
            tooltip: "Clear History",
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 80, color: Colors.grey),
                      SizedBox(height: 10),
                      Text("No recent files.", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    var item = _history[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          child: Icon(Icons.bookmark, color: Colors.white, size: 20),
                        ),
                        title: Text(
                          item['name'] ?? "Unknown File", 
                          maxLines: 1, 
                          overflow: TextOverflow.ellipsis
                        ),
                        subtitle: Text(
                          "Last read: ${_formatDate(item['timestamp'] ?? 0)}",
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                        onTap: () => _openReader(item['path'], item['name']),
                      ),
                    );
                  },
                ),
    );
  }
}