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
      // Load the huge string from the file
      final String jsonString = await rootBundle.loadString('assets/dictionary.json');
      
      // Parse the JSON string into a Map
      _database = json.decode(jsonString);
      print("Dictionary loaded with ${_database?.length} words.");
    } catch (e) {
      print("Error loading dictionary: $e");
      _database = {};
    } finally {
      _isLoading = false;
    }
  }

  /// Looks up a word in the loaded database.
  /// Handles case insensitivity and common suffixes.
  static Future<String?> getDefinition(String word) async {
    if (_database == null) {
      await loadDatabase();
    }

    String lookup = word.trim();
    
    // 1. Try Exact Match (Case Insensitive)
    // The keys in the JSON might be Upper or Lower, so we might need to check both if the map isn't normalized.
    // However, usually these JSONs are keyed one way. Let's try direct first.
    if (_database!.containsKey(lookup)) return _formatDefinition(_database![lookup]);
    if (_database!.containsKey(lookup.toLowerCase())) return _formatDefinition(_database![lookup.toLowerCase()]);
    if (_database!.containsKey(lookup.toUpperCase())) return _formatDefinition(_database![lookup.toUpperCase()]);
    
    // 2. Try removing 's' (Plural -> Singular)
    if (lookup.endsWith('s')) {
      String singular = lookup.substring(0, lookup.length - 1);
      if (_database!.containsKey(singular.toUpperCase())) return _formatDefinition(_database![singular.toUpperCase()]);
    }

    // 3. Try removing 'ing' (Running -> Run)
    if (lookup.endsWith('ing')) {
      String root = lookup.substring(0, lookup.length - 3);
      if (_database!.containsKey(root.toUpperCase())) return _formatDefinition(_database![root.toUpperCase()]);
    }

    return null; 
  }

  static String _formatDefinition(dynamic rawDef) {
    if (rawDef is String) return rawDef;
    return rawDef.toString();
  }
}