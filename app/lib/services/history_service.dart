import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryService {
  static const String _key = 'reading_history';

  /// Save the current progress for a specific file
  static Future<void> saveProgress(String filePath, String fileName, int wordIndex) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Get existing history
    List<String> rawHistory = prefs.getStringList(_key) ?? [];
    List<Map<String, dynamic>> history = [];
    
    // 2. Parse existing
    for (String item in rawHistory) {
      try {
        history.add(json.decode(item));
      } catch (e) {
        // Ignore corrupt data
      }
    }

    // 3. Remove existing entry for this file (to avoid duplicates)
    history.removeWhere((item) => item['path'] == filePath);

    // 4. Add new entry at the top (most recent)
    history.insert(0, {
      'path': filePath,
      'name': fileName,
      'index': wordIndex, // The exact word position
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // 5. Save back to storage (Limit to last 50 items to save space)
    if (history.length > 50) history = history.sublist(0, 50);
    
    List<String> saveList = history.map((item) => json.encode(item)).toList();
    await prefs.setStringList(_key, saveList);
  }

  /// Get the last saved position for a specific file
  static Future<int> getLastPosition(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawHistory = prefs.getStringList(_key) ?? [];
    
    for (String item in rawHistory) {
      try {
        Map<String, dynamic> data = json.decode(item);
        if (data['path'] == filePath) {
          return data['index'] ?? 0;
        }
      } catch (e) {
        continue;
      }
    }
    return 0; // Start at beginning if not found
  }

  /// Get the full list of history for the History Screen
  static Future<List<Map<String, dynamic>>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> rawHistory = prefs.getStringList(_key) ?? [];
    List<Map<String, dynamic>> history = [];

    for (String item in rawHistory) {
      try {
        history.add(json.decode(item));
      } catch (e) {
        // Skip bad data
      }
    }
    return history;
  }
  
  /// Clear history
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}