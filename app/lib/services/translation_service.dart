import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart'; // ML Kit

class TranslationService {
  static Map<String, dynamic>? _phrasebook;
  static final _modelManager = OnDeviceTranslatorModelManager();
  
  /// Loads the phrasebook JSON from assets (For Zambian Languages)
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

  /// Main Translation Function - The "Smart Switch"
  static Future<String> translate(String text, String langCode) async {
    // 1. English (No translation needed)
    if (langCode == 'en') return text; 

    // 2. Zambian Languages (Use Phrasebook)
    if (['bem', 'nya'].contains(langCode)) {
      return _translatePhrasebook(text, langCode);
    }

    // 3. Major Languages (Use ML Kit)
    TranslateLanguage? targetLang;
    if (langCode == 'fr') targetLang = TranslateLanguage.french;
    if (langCode == 'es') targetLang = TranslateLanguage.spanish;

    if (targetLang != null) {
      return _translateWithMLKit(text, targetLang);
    }

    return text; // Fallback to original if language not supported
  }

  // --- ENGINE 1: PHRASEBOOK (Zambian) ---
  static Future<String> _translatePhrasebook(String text, String langCode) async {
    if (_phrasebook == null) await loadPhrasebook();
    
    Map<String, dynamic> dictionary = _phrasebook?[langCode] ?? {};
    if (dictionary.isEmpty) return text;

    // Simple word replacement logic
    List<String> words = text.split(' ');
    List<String> translatedWords = [];

    for (String word in words) {
      // Normalize word to match dictionary keys (remove punctuation, lowercase)
      String cleanWord = word.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase();
      
      if (dictionary.containsKey(cleanWord)) {
        translatedWords.add(dictionary[cleanWord]);
      } else {
        translatedWords.add(word);
      }
    }
    return translatedWords.join(' ');
  }

  // --- ENGINE 2: ML KIT (French/Spanish) ---
  static Future<String> _translateWithMLKit(String text, TranslateLanguage target) async {
    try {
      // 1. Check if model is downloaded
      final bool isDownloaded = await _modelManager.isModelDownloaded(target.bcpCode);
      
      if (!isDownloaded) {
        // Download it (requires internet first time)
        print("Downloading model for ${target.bcpCode}...");
        await _modelManager.downloadModel(target.bcpCode);
      }

      // 2. Translate
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english, 
        targetLanguage: target
      );
      
      final String response = await translator.translateText(text);
      await translator.close();
      
      return response;
    } catch (e) {
      return "Translation Error: $e (Check internet for first-time download)";
    }
  }
}