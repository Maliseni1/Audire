import 'dart:convert';
import 'package:flutter/services.dart';

class DailyWordService {
  static List<dynamic> _words = [];

  // Load the file
  static Future<void> _loadWords() async {
    if (_words.isNotEmpty) return;
    try {
      final String response = await rootBundle.loadString(
        'assets/words_daily.json',
      );
      _words = json.decode(response);
    } catch (e) {
      print("Error loading daily words: $e");
      // Fallback
      _words = [
        {
          "word": "Mwabuka",
          "language": "Bemba",
          "meaning": "Good morning",
          "example": "Mwabuka shani?",
        },
      ];
    }
  }

  // Get the word for today
  static Future<Map<String, dynamic>> getTodaysWord() async {
    await _loadWords();

    if (_words.isEmpty) return {};

    // Use current day as seed to pick a word
    final DateTime now = DateTime.now();
    // Calculate day of year (1-365 approx)
    final int dayOfYear = int.parse(
      "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}",
    );

    // Use Modulo to cycle through the list
    final int index = dayOfYear % _words.length;

    return _words[index];
  }
}
