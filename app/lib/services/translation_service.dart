import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart'; // Used to generate unique filenames
import 'package:google_mlkit_translation/google_mlkit_translation.dart'; 

class TranslationService {
  // TODO: Get a key from console.cloud.google.com/apis/credentials
  // Enable "Cloud Translation API"
  static const String _googleApiKey = "YOUR_GOOGLE_CLOUD_API_KEY_HERE";
  
  static Map<String, dynamic>? _phrasebook;
  static final _modelManager = OnDeviceTranslatorModelManager();
  
  // --- CACHE MANAGEMENT ---
  static Future<String> _getCachePath(String text, String langCode) async {
    final directory = await getApplicationCacheDirectory();
    // Create a unique hash for this text block to use as a filename
    var bytes = utf8.encode(text);
    var digest = sha256.convert(bytes);
    // Filename structure: hash_langCode.txt
    return '${directory.path}/trans_${digest.toString().substring(0, 20)}_$langCode.txt';
  }

  static Future<String?> _checkCache(String text, String langCode) async {
    try {
      final path = await _getCachePath(text, langCode);
      final file = File(path);
      if (await file.exists()) {
        print("Loaded translation from cache: $path");
        return await file.readAsString();
      }
    } catch (e) {
      print("Cache read error: $e");
    }
    return null;
  }

  static Future<void> _saveToCache(String text, String langCode, String translatedText) async {
    try {
      final path = await _getCachePath(text, langCode);
      final file = File(path);
      await file.writeAsString(translatedText);
      print("Saved translation to cache: $path");
    } catch (e) {
      print("Cache write error: $e");
    }
  }

  // --- MAIN TRANSLATE FUNCTION ---
  static Future<String> translate(String text, String langCode) async {
    if (langCode == 'en' || text.trim().isEmpty) return text; 

    // 1. CHECK OFFLINE CACHE FIRST
    String? cached = await _checkCache(text, langCode);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    // 2. ROUTING LOGIC
    String translatedText = text;

    // Zambian Languages -> Try Google Cloud first, Fallback to Phrasebook
    if (['bem', 'nya'].contains(langCode)) {
      try {
        translatedText = await _translateGoogleCloud(text, langCode);
      } catch (e) {
        print("Online translation failed ($e). Using offline fallback.");
        translatedText = await _translatePhrasebook(text, langCode);
      }
    }
    // Major Languages -> Use ML Kit (On-Device)
    else {
      TranslateLanguage? targetLang;
      if (langCode == 'fr') targetLang = TranslateLanguage.french;
      if (langCode == 'es') targetLang = TranslateLanguage.spanish;

      if (targetLang != null) {
        translatedText = await _translateWithMLKit(text, targetLang);
      }
    }

    // 3. SAVE TO CACHE (If translation changed)
    if (translatedText != text) {
      await _saveToCache(text, langCode, translatedText);
    }

    return translatedText;
  }

  // --- ENGINE 1: GOOGLE CLOUD (Online) ---
  static Future<String> _translateGoogleCloud(String text, String targetLang) async {
    if (_googleApiKey == "YOUR_GOOGLE_CLOUD_API_KEY_HERE") {
      throw Exception("API Key not set");
    }

    // Map internal codes to Google API codes if needed
    // 'ny' is Nyanja/Chichewa. 'bem' is Bemba.
    String apiLang = targetLang; 
    
    final Uri url = Uri.parse('https://translation.googleapis.com/language/translate/v2');
    
    final response = await http.post(
      url,
      body: {
        'q': text,
        'target': apiLang,
        'key': _googleApiKey,
        'format': 'text', // prevents html tags in response
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      // Google returns: { "data": { "translations": [ { "translatedText": "..." } ] } }
      return data['data']['translations'][0]['translatedText'];
    } else {
      throw Exception('Google API Error: ${response.body}');
    }
  }

  // --- ENGINE 2: ROBUST PHRASEBOOK (Offline Fallback) ---
  static Future<void> loadPhrasebook() async {
    if (_phrasebook != null) return;
    try {
      String jsonString = await rootBundle.loadString('assets/phrasebook.json');
      _phrasebook = json.decode(jsonString);
    } catch (e) {
      _phrasebook = {};
    }
  }

  static Future<String> _translatePhrasebook(String text, String langCode) async {
    if (_phrasebook == null) await loadPhrasebook();
    
    Map<String, dynamic> dictionary = _phrasebook?[langCode] ?? {};
    if (dictionary.isEmpty) return text;

    // Use RegEx to find words while keeping punctuation separate
    RegExp exp = RegExp(r"(\w+|[^\w\s]+|\s+)");
    List<String> tokens = exp.allMatches(text).map((m) => m.group(0)!).toList();
    
    List<String> translatedResult = [];
    int i = 0;

    while (i < tokens.length) {
      if (RegExp(r"^\s+$").hasMatch(tokens[i]) || RegExp(r"^[^\w\s]+$").hasMatch(tokens[i])) {
        translatedResult.add(tokens[i]);
        i++;
        continue;
      }

      bool matchFound = false;

      // Look-ahead for PHRASES
      for (int length = 3; length >= 1; length--) {
        int tokenSpan = (length * 2) - 1; 
        
        if (i + tokenSpan <= tokens.length) { 
          List<String> phraseTokens = [];
          for (int j = 0; j < length; j++) {
             int tokenIndex = i + (j * 2);
             if (tokenIndex < tokens.length) {
                phraseTokens.add(tokens[tokenIndex].toLowerCase());
             }
          }
          String candidate = phraseTokens.join(' ');
          
          if (dictionary.containsKey(candidate)) {
            String translation = dictionary[candidate];
            if (tokens[i].isNotEmpty && tokens[i][0] == tokens[i][0].toUpperCase()) {
              translation = translation[0].toUpperCase() + translation.substring(1);
            }
            translatedResult.add(translation);
            i += tokenSpan; 
            matchFound = true;
            break; 
          }
        }
      }

      if (!matchFound) {
        translatedResult.add(tokens[i]);
        i++;
      }
    }

    return translatedResult.join('');
  }

  // --- ENGINE 3: ML KIT (French/Spanish - Completely Offline) ---
  static Future<String> _translateWithMLKit(String text, TranslateLanguage target) async {
    try {
      final bool isDownloaded = await _modelManager.isModelDownloaded(target.bcpCode);
      if (!isDownloaded) {
        await _modelManager.downloadModel(target.bcpCode);
      }
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english, 
        targetLanguage: target
      );
      final String response = await translator.translateText(text);
      await translator.close();
      return response;
    } catch (e) {
      return "Translation Error: $e";
    }
  }
}