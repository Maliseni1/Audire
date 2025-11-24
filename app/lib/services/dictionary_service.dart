import 'dart:convert';
import 'package:flutter/services.dart';

class DictionaryService {
  static Map<String, dynamic>? _database;
  static bool _isLoading = false;

  /// Loads the full dictionary JSON from assets into memory.
  static Future<void> loadDatabase() async {
    if (_database != null) return; 
    if (_isLoading) return; 

    _isLoading = true;
    
    try {
      // 1. Load the huge string from the file
      final String jsonString = await rootBundle.loadString('assets/dictionary.json');
      
      // 2. Parse the JSON string into a Map
      _database = json.decode(jsonString);
    } catch (e) {
      print("Error loading dictionary: $e");
      _database = {};
    } finally {
      _isLoading = false;
    }
  }

  /// Looks up a word in the loaded database.
  static Future<String?> getDefinition(String word) async {
    if (_database == null) {
      await loadDatabase();
    }

    // The 'adambom' dictionary uses UPPERCASE keys (e.g., "ZEBRA")
    String lookup = word.toUpperCase().trim();
    
    if (_database != null && _database!.containsKey(lookup)) {
      return _database![lookup].toString();
    }
    
    return null; 
  }
}