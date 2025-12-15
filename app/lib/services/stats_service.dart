import 'package:shared_preferences/shared_preferences.dart';

class StatsService {
  // Keys for storage
  static const String _keyBooks = 'stats_books_opened';
  static const String _keyPages = 'stats_pages_turned';
  static const String _keyWords = 'stats_words_lookup';

  static Future<Map<String, int>> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> books = prefs.getStringList(_keyBooks) ?? [];
    int pages = prefs.getInt(_keyPages) ?? 0;
    int words = prefs.getInt(_keyWords) ?? 0;

    return {'books': books.length, 'pages': pages, 'words': words};
  }

  // Track a new book opening (Unique check)
  static Future<void> recordBookOpen(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> books = prefs.getStringList(_keyBooks) ?? [];

    if (!books.contains(filePath)) {
      books.add(filePath);
      await prefs.setStringList(_keyBooks, books);
    }
  }

  // Track a page turn
  static Future<void> incrementPageCount() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt(_keyPages) ?? 0;
    await prefs.setInt(_keyPages, current + 1);
  }

  // Track a dictionary lookup
  static Future<void> incrementWordLookup() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt(_keyWords) ?? 0;
    await prefs.setInt(_keyWords, current + 1);
  }
}
