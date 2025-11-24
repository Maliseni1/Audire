import 'dart:convert';
import 'package:flutter/services.dart';

class TranslationService {
  static Map<String, dynamic>? _phrasebook;
  
  /// Loads the phrasebook JSON from assets
  static Future<void> loadPhrasebook() async {
    if (_phrasebook != null) return;
    try {
      String jsonString = await rootBundle.loadString('assets/phrasebook.json');
      _phrasebook = json.decode(jsonString);
    } catch (e) {
      print("Error loading phrasebook: $e");
      _phrasebook = {};
    }
  }

  /// Translates text word-by-word (Hybrid Approach)
  static Future<String> translate(String text, String langCode) async {
    // 1. Initialize
    if (_phrasebook == null) await loadPhrasebook();
    
    // 2. If English is selected, return original
    if (langCode == 'en') return text; 

    // 3. Get the dictionary for the target language (bem or nya)
    Map<String, dynamic> dictionary = _phrasebook?[langCode] ?? {};
    if (dictionary.isEmpty) return text;

    // 4. Word-Swap Logic
    // Split text into words, preserving spaces is tricky, 
    // so we'll do a simple split by space for this MVP.
    List<String> words = text.split(' ');
    List<String> translatedWords = [];

    for (String word in words) {
      // Clean punctuation (e.g., "Hello," -> "hello") to find match
      String cleanWord = word.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase();
      
      if (dictionary.containsKey(cleanWord)) {
        // Match found! Use the translated word
        translatedWords.add(dictionary[cleanWord]);
      } else {
        // No match found, keep the original English word
        translatedWords.add(word);
      }
    }

    return translatedWords.join(' ');
  }
}