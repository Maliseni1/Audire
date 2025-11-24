class DictionaryService {
  // A "Starter Pack" of definitions for the offline demo.
  // In the future, we will replace this map with a proper SQLite database query.
  static final Map<String, String> _offlineDatabase = {
    "audire": "Latin verb meaning 'to hear'. The name of this application.",
    "audio": "Sound, especially when recorded, transmitted, or reproduced.",
    "algorithm": "A process or set of rules to be followed in calculations or other problem-solving operations.",
    "book": "A written or printed work consisting of pages glued or sewn together along one side and bound in covers.",
    "code": "A system of words, letters, figures, or other symbols substituted for other words, letters, etc., especially for secrecy.",
    "computer": "An electronic device for storing and processing data.",
    "flutter": "An open-source UI software development kit created by Google.",
    "internet": "A global computer network providing a variety of information and communication facilities.",
    "mobile": "Able to move or be moved freely or easily.",
    "offline": "Not connected to a computer or computer network.",
    "pdf": "Portable Document Format, a file format that provides an electronic image of text or text and graphics.",
    "read": "Look at and comprehend the meaning of (written or printed matter) by mentally interpreting the characters or symbols of which it is composed.",
    "zambia": "A landlocked country in southern Africa.",
    "technology": "The application of scientific knowledge for practical purposes.",
    "voice": "The sound produced in a person's larynx and uttered through the mouth, as speech or song.",
  };

  /// Looks up a word in the local database.
  /// Returns the definition or null if not found.
  static Future<String?> getDefinition(String word) async {
    // Simulate a database delay for realism (optional)
    await Future.delayed(const Duration(milliseconds: 100));

    String lookup = word.toLowerCase().trim();
    
    // Check exact match
    if (_offlineDatabase.containsKey(lookup)) {
      return _offlineDatabase[lookup];
    }
    
    return null; 
  }
}