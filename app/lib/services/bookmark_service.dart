import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class BookmarkService {
  static const String _key = 'audire_bookmarks';

  static Future<void> addBookmark({
    required String filePath,
    required String fileName,
    required int index,
    required String snippet,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> saved = prefs.getStringList(_key) ?? [];

    Map<String, dynamic> newBookmark = {
      'path': filePath,
      'name': fileName,
      'index': index,
      'snippet': snippet,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    saved.insert(0, json.encode(newBookmark));
    await prefs.setStringList(_key, saved);
  }

  static Future<List<Map<String, dynamic>>> getBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> saved = prefs.getStringList(_key) ?? [];
    return saved.map((item) => json.decode(item) as Map<String, dynamic>).toList();
  }

  // --- NEW: Helper to find bookmarks for a specific file ---
  static Future<List<Map<String, dynamic>>> getBookmarksForFile(String filePath) async {
    final all = await getBookmarks();
    return all.where((b) => b['path'] == filePath).toList();
  }

  // --- NEW: Delete by precise location ---
  static Future<void> deleteBookmarkByPosition(String filePath, int index) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> saved = prefs.getStringList(_key) ?? [];
    
    saved.removeWhere((item) {
      Map<String, dynamic> data = json.decode(item);
      return data['path'] == filePath && data['index'] == index;
    });
    
    await prefs.setStringList(_key, saved);
  }

  static Future<void> deleteBookmark(int listIndex) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> saved = prefs.getStringList(_key) ?? [];
    if (listIndex < saved.length) {
      saved.removeAt(listIndex);
      await prefs.setStringList(_key, saved);
    }
  }
}