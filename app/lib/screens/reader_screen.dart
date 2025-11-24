import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Required for 'compute'
import 'package:flutter_tts/flutter_tts.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'dart:io';
import '../services/translation_service.dart';
import '../services/history_service.dart';

// --- TOP LEVEL FUNCTION (Must be outside class for 'compute') ---
// This runs on a background thread to prevent the app from freezing
String _backgroundCleanText(String text) {
  // Replace multiple newlines/spaces with a single space and trim
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final FlutterTts _flutterTts = FlutterTts();

  // Content
  String _originalContent = "";
  String _displayedContent = ""; // Empty initially

  // State
  bool _isLoading = true; // New loading state
  String _loadingMessage = "Initializing..."; // New loading status
  bool _isPlaying = false;
  double _speechRate = 0.5;
  String _currentLang = 'en';

  // Voices
  List<Map<String, String>> _voices = [];
  Map<String, String>? _currentVoice;

  // Highlighting & Chunking
  int _currentWordStart = 0;
  int _currentWordEnd = 0;
  int _globalPlayPosition = 0; 
  static const int _chunkSize = 1000; 

  @override
  void initState() {
    super.initState();
    _initTts();
    _initVoices();
    _extractText(); // Starts the optimized loading process
  }

  @override
  void dispose() {
    _flutterTts.stop();
    HistoryService.saveProgress(
      widget.filePath,
      widget.fileName,
      _globalPlayPosition,
    );
    super.dispose();
  }

  Future<void> _initTts() async {
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setProgressHandler((String text, int start, int end, String word) {
      if (!mounted) return;
      setState(() {
        _currentWordStart = _globalPlayPosition + start;
        _currentWordEnd = _globalPlayPosition + end;
      });
    });

    _flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      _playNextChunk();
    });
  }

  // --- LOGIC: CONTINUOUS PLAYBACK ---
  Future<void> _playNextChunk() async {
    int nextPosition = _globalPlayPosition + _chunkSize;
    if (nextPosition < _displayedContent.length) {
      setState(() {
        _globalPlayPosition = nextPosition;
      });
      _speakChunk();
    } else {
      setState(() {
        _isPlaying = false;
        _globalPlayPosition = 0;
        _currentWordStart = 0;
        _currentWordEnd = 0;
      });
    }
  }

  Future<void> _speakChunk() async {
    int endIndex = _globalPlayPosition + _chunkSize;
    if (endIndex > _displayedContent.length) {
      endIndex = _displayedContent.length;
    }

    String chunk = _displayedContent.substring(_globalPlayPosition, endIndex);
    
    // Smart cut: find last space to avoid splitting words
    int lastSpace = chunk.lastIndexOf(" ");
    if (lastSpace != -1 && endIndex < _displayedContent.length) {
       chunk = chunk.substring(0, lastSpace);
    }

    if (chunk.trim().isNotEmpty) {
      await _flutterTts.speak(chunk);
    } else {
      _playNextChunk(); 
    }
  }
  
  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _flutterTts.stop();
      setState(() => _isPlaying = false);
    } else {
      if (_displayedContent.isNotEmpty) {
        setState(() => _isPlaying = true);
        _speakChunk();
      }
    }
  }

  // --- LOGIC: VOICES ---
  Future<void> _initVoices() async {
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final voices = await _flutterTts.getVoices;
      if (voices == null) return;

      List<Map<String, String>> cleanVoices = [];
      for (var voice in voices) {
        Map<Object?, Object?> rawMap = voice as Map<Object?, Object?>;
        if (rawMap.containsKey("name") && rawMap.containsKey("locale")) {
          cleanVoices.add({
            "name": rawMap["name"].toString(),
            "locale": rawMap["locale"].toString(),
          });
        }
      }

      if (mounted) {
        setState(() {
          _voices = cleanVoices;
        });
      }
    } catch (e) {
      print("Error fetching voices: $e");
    }
  }

  Future<void> _setVoice(Map<String, String> voice) async {
    try {
      await _flutterTts.stop();
      await _flutterTts.setLanguage(voice["locale"]!);
      await _flutterTts.setVoice({
        "name": voice["name"]!,
        "locale": voice["locale"]!
      });

      setState(() {
        _currentVoice = voice;
        _isPlaying = false;
      });
    } catch (e) {
      print("Error setting voice: $e");
    }
  }

  void _showVoicePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select a Voice", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              const SizedBox(height: 10),
              Expanded(
                child: _voices.isEmpty
                    ? Center(child: TextButton(onPressed: () { Navigator.pop(context); _initVoices(); }, child: const Text("No voices found. Tap to retry.")))
                    : ListView.builder(
                        itemCount: _voices.length,
                        itemBuilder: (context, index) {
                          var voice = _voices[index];
                          bool isSelected = _currentVoice == voice;
                          return ListTile(
                            leading: const Icon(Icons.record_voice_over, color: Colors.grey),
                            title: Text(voice["name"]!),
                            subtitle: Text(voice["locale"]!),
                            trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.deepPurple) : null,
                            onTap: () {
                              _setVoice(voice);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- LOGIC: OPTIMIZED TEXT EXTRACTION ---
  Future<void> _extractText() async {
    try {
      // 1. Check file size to give user feedback
      File file = File(widget.filePath);
      int sizeBytes = await file.length();
      double sizeMb = sizeBytes / (1024 * 1024);
      
      setState(() {
        _isLoading = true;
        _loadingMessage = sizeMb > 2.0 
            ? "Reading large file (${sizeMb.toStringAsFixed(1)} MB)...\nThis may take a moment." 
            : "Opening file...";
      });

      // 2. Extract Raw Text (This is the slow native part)
      String rawText = "";
      if (widget.filePath.endsWith('.pdf')) {
        rawText = await ReadPdfText.getPDFtext(widget.filePath);
      } else if (widget.filePath.endsWith('.txt')) {
        rawText = await file.readAsString();
      } else {
        rawText = "File type not supported.";
      }

      // 3. Process Text in Background (Prevents UI Freeze)
      setState(() {
        _loadingMessage = "Optimizing text for playback...";
      });
      
      // 'compute' runs the function in a separate isolate (thread)
      String cleanText = await compute(_backgroundCleanText, rawText);

      // 4. Load Saved History
      int savedIndex = await HistoryService.getLastPosition(widget.filePath);

      if (mounted) {
        setState(() {
          _originalContent = cleanText;
          _displayedContent = cleanText;
          _isLoading = false; // Done loading
          
          if (savedIndex < cleanText.length) {
            _globalPlayPosition = savedIndex;
            _currentWordStart = savedIndex;
          } else {
            _globalPlayPosition = 0;
          }
        });
        
        if (_globalPlayPosition > 0) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text("Resumed from last position"), duration: Duration(seconds: 1)),
           );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _displayedContent = "Error reading file: $e";
        });
      }
    }
  }

  Future<void> _changeLanguage(String langCode) async {
    if (langCode == _currentLang) return;
    
    setState(() { 
      _isLoading = true;
      _loadingMessage = "Translating..."; 
    });
    
    // Simulate background delay for translation so UI updates
    await Future.delayed(const Duration(milliseconds: 100));

    String translated = await TranslationService.translate(_originalContent, langCode);
    
    if (mounted) {
      setState(() {
        _currentLang = langCode;
        _displayedContent = translated;
        _globalPlayPosition = 0;
        _currentWordStart = 0;
        _currentWordEnd = 0;
        _isLoading = false;
      });
    }
  }

  Future<void> _changeSpeed() async {
    double newRate = _speechRate == 0.5 ? 0.75 : (_speechRate == 0.75 ? 1.0 : 0.5);
    setState(() => _speechRate = newRate);
    await _flutterTts.setSpeechRate(newRate);
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(icon: const Icon(Icons.record_voice_over), onPressed: _showVoicePicker),
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate),
            onSelected: _changeLanguage,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'en', child: Text('English')),
              const PopupMenuItem(value: 'bem', child: Text('Bemba')),
              const PopupMenuItem(value: 'nya', child: Text('Nyanja')),
            ],
          ),
          IconButton(icon: const Icon(Icons.speed), onPressed: _changeSpeed),
        ],
      ),
      body: _isLoading 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  _loadingMessage, 
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 16)
                ),
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: _buildHighlightedText(), 
            ),
          ),
      floatingActionButton: _isLoading 
          ? null 
          : FloatingActionButton.extended(
              onPressed: _togglePlay,
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(_isPlaying ? "Pause" : "Resume"),
            ),
    );
  }

  Widget _buildHighlightedText() {
    if (_displayedContent.isEmpty) return const Text("No text found in this file.");

    int start = _currentWordStart;
    int end = _currentWordEnd;
    
    if (start < 0) start = 0;
    if (end > _displayedContent.length) end = _displayedContent.length;
    if (start > end) start = end;

    return RichText(
      textAlign: TextAlign.justify,
      text: TextSpan(
        style: TextStyle(
          fontSize: 18, 
          height: 1.6, 
          color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87
        ),
        children: [
          TextSpan(text: _displayedContent.substring(0, start)),
          TextSpan(
            text: _displayedContent.substring(start, end),
            style: const TextStyle(
              backgroundColor: Colors.yellow, 
              color: Colors.black, 
              fontWeight: FontWeight.bold
            ),
          ),
          TextSpan(text: _displayedContent.substring(end)),
        ],
      ),
    );
  }
}