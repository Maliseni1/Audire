import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:translator/translator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationService {
  static Map<String, dynamic>? _phrasebook;
  static final _modelManager = OnDeviceTranslatorModelManager();
  static final _googleTranslator = GoogleTranslator();

  static Future<String> _getCachePath(String text, String langCode) async {
    final directory = await getApplicationCacheDirectory();
    var bytes = utf8.encode(text);
    var digest = sha256.convert(bytes);
    return '${directory.path}/trans_${digest.toString().substring(0, 20)}_$langCode.txt';
  }

  static Future<String?> _checkCache(String text, String langCode) async {
    try {
      final path = await _getCachePath(text, langCode);
      final file = File(path);
      if (await file.exists()) {
        debugPrint("Loaded translation from cache: $path");
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint("Cache read error: $e");
    }
    return null;
  }

  static Future<void> _saveToCache(
    String text,
    String langCode,
    String translatedText,
  ) async {
    try {
      final path = await _getCachePath(text, langCode);
      final file = File(path);
      await file.writeAsString(translatedText);
      debugPrint("Saved translation to cache: $path");
    } catch (e) {
      debugPrint("Cache write error: $e");
    }
  }

  static Future<String> translate(String text, String langCode) async {
    if (langCode == 'en' || text.trim().isEmpty) return text;

    String? cached = await _checkCache(text, langCode);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    String translatedText = text;

    if (['bem', 'nya'].contains(langCode)) {
      try {
        translatedText = await _translateFreeOnline(text, langCode);
      } catch (e) {
        debugPrint(
          "Online translation failed ($e). Using offline phrasebook fallback.",
        );
        translatedText = await _translatePhrasebook(text, langCode);
      }
    } else {
      TranslateLanguage? targetLang;
      if (langCode == 'fr') targetLang = TranslateLanguage.french;
      if (langCode == 'es') targetLang = TranslateLanguage.spanish;

      if (targetLang != null) {
        translatedText = await _translateWithMLKit(text, targetLang);
      }
    }

    if (translatedText != text &&
        !translatedText.startsWith("Translation Error")) {
      await _saveToCache(text, langCode, translatedText);
    }

    return translatedText;
  }

  static Future<String> _translateFreeOnline(
    String text,
    String targetLang,
  ) async {
    String apiLang = targetLang == 'nya' ? 'ny' : targetLang;
    try {
      var translation = await _googleTranslator.translate(text, to: apiLang);
      return translation.text;
    } catch (e) {
      throw Exception("Free Translation Failed: $e");
    }
  }

  static Future<void> loadPhrasebook() async {
    if (_phrasebook != null) return;
    try {
      String jsonString = await rootBundle.loadString('assets/phrasebook.json');
      _phrasebook = json.decode(jsonString);
    } catch (e) {
      debugPrint("Error loading phrasebook: $e");
      _phrasebook = {};
    }
  }

  static Future<String> _translatePhrasebook(
    String text,
    String langCode,
  ) async {
    if (_phrasebook == null) await loadPhrasebook();

    Map<String, dynamic> dictionary = _phrasebook?[langCode] ?? {};
    if (dictionary.isEmpty) return text;

    RegExp exp = RegExp(r"(\w+|[^\w\s]+|\s+)");
    List<String> tokens = exp.allMatches(text).map((m) => m.group(0)!).toList();

    List<String> translatedResult = [];
    int i = 0;

    while (i < tokens.length) {
      if (RegExp(r"^\s+$").hasMatch(tokens[i]) ||
          RegExp(r"^[^\w\s]+$").hasMatch(tokens[i])) {
        translatedResult.add(tokens[i]);
        i++;
        continue;
      }

      bool matchFound = false;

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
            if (tokens[i].isNotEmpty &&
                tokens[i][0] == tokens[i][0].toUpperCase()) {
              translation =
                  translation[0].toUpperCase() + translation.substring(1);
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

  static Future<String> _translateWithMLKit(
    String text,
    TranslateLanguage target,
  ) async {
    try {
      final bool isDownloaded = await _modelManager.isModelDownloaded(
        target.bcpCode,
      );
      if (!isDownloaded) {
        debugPrint("Downloading model for ${target.bcpCode}...");
        await _modelManager.downloadModel(target.bcpCode);
      }
      final translator = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: target,
      );
      final String response = await translator.translateText(text);
      await translator.close();
      return response;
    } catch (e) {
      return "Translation Error: $e";
    }
  }
}
