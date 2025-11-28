import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class DictionaryService {
  static Map<String, dynamic>? _database;
  static bool _isLoading = false;

  static Future<void> loadDatabase() async {
    if (_database != null) return; 
    if (_isLoading) return; 

    _isLoading = true;
    
    try {
      // 1. Load the compressed GZIP file as bytes
      final ByteData data = await rootBundle.load('assets/dictionary.json.gz');
      List<int> bytes = data.buffer.asUint8List();

      // 2. Decompress (Gunzip)
      // GZipCodec is built into dart:io
      List<int> decompressed = gzip.decode(bytes);
      
      // 3. Decode JSON
      String jsonString = utf8.decode(decompressed);
      _database = json.decode(jsonString);
      
      print("Dictionary loaded: ${_database?.length} words.");
    } catch (e) {
      print("Error loading dictionary: $e");
      // Fallback: Check if user forgot to compress and try loading raw json
      try {
         final String jsonString = await rootBundle.loadString('assets/dictionary.json');
         _database = json.decode(jsonString);
      } catch (e2) {
         _database = {};
      }
    } finally {
      _isLoading = false;
    }
  }

  static Future<String?> getDefinition(String word) async {
    if (_database == null) await loadDatabase();

    String lookup = word.trim();
    
    // Check various casing/forms
    if (_database!.containsKey(lookup)) return _formatDef(_database![lookup]);
    if (_database!.containsKey(lookup.toLowerCase())) return _formatDef(_database![lookup.toLowerCase()]);
    if (_database!.containsKey(lookup.toUpperCase())) return _formatDef(_database![lookup.toUpperCase()]);
    
    // Simple lemmatization (removing 's', 'ing')
    if (lookup.endsWith('s')) {
      String root = lookup.substring(0, lookup.length - 1);
      if (_database!.containsKey(root.toLowerCase())) return _formatDef(_database![root.toLowerCase()]);
    }
    if (lookup.endsWith('ing')) {
      String root = lookup.substring(0, lookup.length - 3);
      if (_database!.containsKey(root.toLowerCase())) return _formatDef(_database![root.toLowerCase()]);
    }

    return null; 
  }

  static String _formatDef(dynamic raw) => raw.toString();
}