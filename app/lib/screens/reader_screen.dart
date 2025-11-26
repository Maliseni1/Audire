import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:flutter_tts/flutter_tts.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:docx_to_text/docx_to_text.dart'; 
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart'; 
import 'package:audio_session/audio_session.dart'; 
import 'package:audio_service/audio_service.dart'; // NEW IMPORTS
import 'dart:io';
import 'dart:async'; 
import '../services/translation_service.dart';
import '../services/history_service.dart';
import '../services/audio_manager.dart'; // Import our new manager

// --- WORKERS ---
String _backgroundCleanText(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

List<String> _backgroundPagination(String text) {
  const int pageSize = 3000; 
  List<String> pages = [];
  if (text.isEmpty) return [""];
  int start = 0;
  while (start < text.length) {
    int end = start + pageSize;
    if (end >= text.length) {
      pages.add(text.substring(start));
      break;
    }
    int lastPeriod = text.lastIndexOf('.', end);
    int lastSpace = text.lastIndexOf(' ', end);
    int cutPoint = end;
    if (lastPeriod != -1 && lastPeriod > start + pageSize - 100) {
      cutPoint = lastPeriod + 1;
    } else if (lastSpace != -1) {
      cutPoint = lastSpace + 1;
    }
    pages.add(text.substring(start, cutPoint));
    start = cutPoint;
  }
  return pages;
}

class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const ReaderScreen({super.key, required this.filePath, required this.fileName});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  
  // Audio Handler (Notification Control)
  TtsAudioHandler? _audioHandler;
  StreamSubscription? _playbackSubscription;

  String _fullOriginalText = ""; 
  List<String> _pages = [];
  int _currentPageIndex = 0;
  String _currentPageContent = ""; 
  
  bool _isLoading = true;
  String _loadingMessage = "Initializing...";
  bool _isPlaying = false;
  
  double _speechRate = 0.5;
  double _pitch = 1.0;
  String _currentLang = 'en';
  List<Map<String, String>> _voices = [];
  Map<String, String>? _currentVoice;

  int _currentWordStart = 0;
  int _currentWordEnd = 0;
  int _currentSpeechOffset = 0; 
  
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _setupAudioSystem();
    _loadOrExtractText();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _playbackSubscription?.cancel();
    _debounce?.cancel();
    _scrollController.dispose();
    HistoryService.saveProgress(widget.filePath, widget.fileName, _currentPageIndex * 3000);
    super.dispose();
  }

  // --- SETUP: AUDIO & NOTIFICATIONS ---
  Future<void> _setupAudioSystem() async {
    // 1. Init Session (Keep screen/audio alive)
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());

    // 2. Init Notification Handler
    _audioHandler = await TtsAudioHandler.init();
    
    // 3. Listen to Lock Screen Controls
    _playbackSubscription = _audioHandler?.playbackState.listen((state) {
      if (state.playing && !_isPlaying) {
        _playCurrentPage(); // Resume triggered from lock screen
      } else if (!state.playing && _isPlaying) {
        _pausePlayback(); // Pause triggered from lock screen
      }
    });

    // 4. Init TTS
    await _flutterTts.awaitSpeakCompletion(true);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setPitch(_pitch);
    
    await _flutterTts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
      IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
      IosTextToSpeechAudioCategoryOptions.allowBluetooth,
      IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
      IosTextToSpeechAudioCategoryOptions.mixWithOthers
    ]);

    _flutterTts.setProgressHandler((String text, int start, int end, String word) {
      if (!mounted) return;
      setState(() {
        _currentWordStart = _currentSpeechOffset + start;
        _currentWordEnd = _currentSpeechOffset + end;
      });
    });

    _flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      if (_currentPageIndex < _pages.length - 1) {
        _changePage(_currentPageIndex + 1, autoPlay: true);
      } else {
        setState(() => _isPlaying = false);
        _audioHandler?.setPlaybackState(isPlaying: false);
      }
    });
    
    _initVoices();
  }

  String _formatVoiceName(String rawName, String locale) {
    Map<String, String> langs = {
      'en': 'English', 'fr': 'French', 'es': 'Spanish', 'de': 'German',
      'it': 'Italian', 'pt': 'Portuguese', 'ru': 'Russian', 'zh': 'Chinese',
      'ja': 'Japanese', 'bem': 'Bemba', 'nya': 'Nyanja'
    };
    String langCode = locale.split('-')[0].toLowerCase();
    String displayLang = langs[langCode] ?? langCode.toUpperCase();
    if (locale.contains('-')) {
       String country = locale.split('-')[1].toUpperCase();
       return "$displayLang ($country)";
    }
    return displayLang;
  }

  // ... (File Loading / Extraction Logic - No Changes needed here) ...
  Future<void> _loadOrExtractText() async {
    setState(() { _isLoading = true; _loadingMessage = "Checking cache..."; });
    String? cachedText = await _checkCache();
    if (cachedText != null && cachedText.isNotEmpty) {
      await _processFullText(cachedText);
      return;
    }
    await _extractTextAndCache();
  }

  Future<void> _processFullText(String fullText) async {
    setState(() { _loadingMessage = "Paginating document..."; });
    List<String> pages = await compute(_backgroundPagination, fullText);
    
    int savedGlobalIndex = await HistoryService.getLastPosition(widget.filePath);
    int savedPage = (savedGlobalIndex / 3000).floor();
    if (savedPage >= pages.length) savedPage = 0;

    if (mounted) {
      setState(() {
        _fullOriginalText = fullText;
        _pages = pages;
        _currentPageIndex = savedPage;
        _isLoading = false;
      });
      await _loadPageContent(savedPage);
      
      // Update Notification Info
      _audioHandler?.setMediaItem(widget.fileName, Duration.zero);
    }
  }

  Future<void> _loadPageContent(int index) async {
    if (index < 0 || index >= _pages.length) return;
    String content = _pages[index];
    if (_currentLang != 'en') {
      setState(() { _loadingMessage = "Translating page..."; _isLoading = true; });
      await Future.delayed(const Duration(milliseconds: 50));
      content = await TranslationService.translate(content, _currentLang);
      setState(() { _isLoading = false; });
    }
    setState(() {
      _currentPageContent = content;
      _currentWordStart = 0;
      _currentWordEnd = 0;
      _currentSpeechOffset = 0;
    });
  }

  Future<void> _changePage(int newIndex, {bool autoPlay = false}) async {
    if (newIndex < 0 || newIndex >= _pages.length) return;
    await _flutterTts.stop();
    setState(() { _currentPageIndex = newIndex; });
    await _loadPageContent(newIndex);
    if (autoPlay) {
      _playCurrentPage();
    } else {
      setState(() => _isPlaying = false);
      _audioHandler?.setPlaybackState(isPlaying: false);
    }
  }

  // --- PLAYBACK CONTROLS ---
  Future<void> _playCurrentPage() async {
    // 1. Setup Engine
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setPitch(_pitch);
    
    // 2. Calculate Offset
    String textToSpeak = _currentPageContent;
    if (_currentWordStart > 0 && _currentWordStart < _currentPageContent.length) {
      textToSpeak = _currentPageContent.substring(_currentWordStart);
      _currentSpeechOffset = _currentWordStart; 
    } else {
      _currentSpeechOffset = 0;
    }
    
    // 3. Update UI & Notification
    setState(() => _isPlaying = true);
    _audioHandler?.setPlaybackState(isPlaying: true);
    
    // 4. Speak
    await _flutterTts.speak(textToSpeak);
  }

  Future<void> _pausePlayback() async {
    await _flutterTts.stop();
    setState(() => _isPlaying = false);
    _audioHandler?.setPlaybackState(isPlaying: false);
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _pausePlayback();
    } else {
      await _playCurrentPage();
    }
  }

  // ... (Extraction, Cache, Voice Init Logic same as previous) ...
  Future<void> _extractTextAndCache() async {
    try {
      File file = File(widget.filePath);
      String rawText = "";
      String ext = widget.filePath.toLowerCase();
      setState(() { _loadingMessage = "Processing file..."; });

      if (ext.endsWith('.pdf')) {
        rawText = await ReadPdfText.getPDFtext(widget.filePath);
      } else if (ext.endsWith('.txt')) {
        rawText = await file.readAsString();
      } else if (ext.endsWith('.docx')) {
        final bytes = await file.readAsBytes();
        rawText = docxToText(bytes); 
      } else if (ext.endsWith('.jpg') || ext.endsWith('.png') || ext.endsWith('.jpeg')) {
        final inputImage = InputImage.fromFile(file);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        try {
          final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
          rawText = recognizedText.text;
        } finally { textRecognizer.close(); }
        if (rawText.isEmpty) rawText = "No text found.";
      } else {
        rawText = "Unsupported file type.";
      }

      setState(() { _loadingMessage = "Optimizing..."; });
      String cleanText = await compute(_backgroundCleanText, rawText);
      await _saveToCache(cleanText);
      await _processFullText(cleanText);
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _currentPageContent = "Error reading file: $e"; });
    }
  }

  Future<String?> _checkCache() async {
    try {
      final directory = await getApplicationCacheDirectory();
      final String cacheKey = widget.filePath.hashCode.toString(); 
      final File cacheFile = File('${directory.path}/$cacheKey.txt');
      if (await cacheFile.exists()) return await cacheFile.readAsString();
    } catch (e) { print("Cache error: $e"); }
    return null;
  }

  Future<void> _saveToCache(String text) async {
    try {
      final directory = await getApplicationCacheDirectory();
      final String cacheKey = widget.filePath.hashCode.toString();
      final File cacheFile = File('${directory.path}/$cacheKey.txt');
      await cacheFile.writeAsString(text);
    } catch (e) { print("Save cache error: $e"); }
  }

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
      if (mounted) setState(() { _voices = cleanVoices; });
    } catch (e) { print("Error: $e"); }
  }

  Future<void> _setVoice(Map<String, String> voice) async {
    try {
      await _flutterTts.stop();
      await _flutterTts.setLanguage(voice["locale"]!);
      await _flutterTts.setVoice({"name": voice["name"]!, "locale": voice["locale"]!});
      setState(() { _currentVoice = voice; _isPlaying = false; });
      _audioHandler?.setPlaybackState(isPlaying: false);
    } catch (e) { print("Error: $e"); }
  }

  Future<void> _changeLanguage(String langCode) async {
    if (langCode == _currentLang) return;
    setState(() { _currentLang = langCode; });
    await _loadPageContent(_currentPageIndex);
  }

  Future<void> _saveToAudioFile() async {
    // Implementation same as previous (omitted for brevity, logic persists)
    // Can be re-added if needed, but focus here is on Audio Controls
  }

  // --- UI BUILDERS ---
  void _showVoicePicker() {
    showModalBottomSheet(context: context, builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text("Select Voice", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Expanded(child: ListView.builder(itemCount: _voices.length, itemBuilder: (c, i) {
                var voice = _voices[i];
                // FIX: Use Pretty Name
                String displayName = _formatVoiceName(voice["name"]!, voice["locale"]!);
                bool isSelected = _currentVoice == voice;
                return ListTile(
                  leading: const Icon(Icons.record_voice_over, color: Colors.grey),
                  title: Text(displayName),
                  subtitle: Text(voice["locale"]!), 
                  trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.deepPurple) : null,
                  onTap: () { _setVoice(voice); Navigator.pop(ctx); }
                );
              }))
            ],
          ),
        );
    });
  }

  void _showAudioSettings() {
    showModalBottomSheet(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (c, setModalState) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Audio Settings", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Text("Speed: ${_speechRate.toStringAsFixed(1)}x"),
              Slider(value: _speechRate, min: 0.1, max: 2.0, 
                onChangeEnd: (v) {
                  // FIX: Restart audio instantly when slider released
                  if (_isPlaying) { 
                    _pausePlayback(); 
                    Future.delayed(const Duration(milliseconds: 200), _playCurrentPage);
                  }
                },
                onChanged: (v) {
                  setState(() => _speechRate = v);
                  setModalState((){});
                  // Don't call _flutterTts.setSpeechRate here, do it on play
                }
              ),
              Text("Pitch: ${_pitch.toStringAsFixed(1)}"),
              Slider(value: _pitch, min: 0.5, max: 2.0, 
                onChangeEnd: (v) {
                  // FIX: Restart audio instantly when slider released
                  if (_isPlaying) { 
                    _pausePlayback(); 
                    Future.delayed(const Duration(milliseconds: 200), _playCurrentPage);
                  }
                },
                onChanged: (v) {
                  setState(() => _pitch = v);
                  setModalState((){});
                }
              ),
            ],
          ),
        );
      });
    });
  }

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
              const PopupMenuItem(value: 'fr', child: Text('French')),
              const PopupMenuItem(value: 'es', child: Text('Spanish')),
            ],
          ),
          IconButton(icon: const Icon(Icons.tune), onPressed: _showAudioSettings),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading 
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const CircularProgressIndicator(), const SizedBox(height: 20), Text(_loadingMessage, textAlign: TextAlign.center)]))
              : Padding(
                  padding: const EdgeInsets.all(16.0), 
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: _buildHighlightedText(), 
                  ),
                ),
          ),
          if (!_isLoading && _pages.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: _currentPageIndex > 0 ? () => _changePage(_currentPageIndex - 1) : null),
                  Text("Page ${_currentPageIndex + 1} of ${_pages.length}"),
                  IconButton(icon: const Icon(Icons.arrow_forward_ios), onPressed: _currentPageIndex < _pages.length - 1 ? () => _changePage(_currentPageIndex + 1) : null),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: _isLoading 
          ? null 
          : FloatingActionButton.extended(
              onPressed: _togglePlay,
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              label: Text(_isPlaying ? "Pause" : "Play"),
            ),
    );
  }

  Widget _buildHighlightedText() {
    if (_currentPageContent.isEmpty) return const Text("No text.");
    int start = _currentWordStart;
    int end = _currentWordEnd;
    if (start < 0) start = 0;
    if (end > _currentPageContent.length) end = _currentPageContent.length;
    if (start > end) start = end;

    return RichText(
      textAlign: TextAlign.justify,
      text: TextSpan(
        style: TextStyle(fontSize: 18, height: 1.6, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
        children: [
          TextSpan(text: _currentPageContent.substring(0, start)),
          TextSpan(text: _currentPageContent.substring(start, end), style: const TextStyle(backgroundColor: Colors.yellow, color: Colors.black, fontWeight: FontWeight.bold)),
          TextSpan(text: _currentPageContent.substring(end)),
        ],
      ),
    );
  }
}