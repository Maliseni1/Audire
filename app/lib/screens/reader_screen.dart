import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'package:docx_to_text/docx_to_text.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart'; // NEW: For Settings
import 'dart:io';
import 'dart:async';
import '../services/translation_service.dart';
import '../services/history_service.dart';
import '../services/dictionary_service.dart';
import '../services/audio_manager.dart';
import '../services/bookmark_service.dart';
import '../services/stats_service.dart';

// --- BACKGROUND WORKERS ---
String _backgroundCleanText(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

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
  final int? initialIndex;

  const ReaderScreen({
    super.key,
    required this.filePath,
    required this.fileName,
    this.initialIndex,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();

  TtsAudioHandler? _audioHandler;
  StreamSubscription? _playbackSubscription;
  StreamSubscription? _eventSubscription;

  String _fullOriginalText = "";
  List<String> _pages = [];
  int _currentPageIndex = 0;
  String _currentPageContent = "";

  bool _isLoading = true;
  String _loadingMessage = "Initializing...";
  bool _isPlaying = false;

  // Settings with Defaults (Will be overwritten by _loadPreferences)
  double _speechRate = 0.5;
  double _pitch = 1.0;
  bool _keepScreenOn = false;

  String _currentLang = 'en';
  List<Map<String, String>> _voices = [];
  Map<String, String>? _currentVoice;

  int _currentWordStart = 0;
  int _currentWordEnd = 0;
  int _currentSpeechOffset = 0;
  Set<int> _pageBookmarkIndices = {};

  Timer? _debounce;
  Timer? _sleepTimer;

  // Immersive Mode
  bool _controlsVisible = true;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    _loadPreferences(); // NEW: Load user settings
    _setupAudioSystem();
    _loadOrExtractText();
    _resetControlsTimer();
  }

  @override
  void dispose() {
    _stopPlayback();
    _playbackSubscription?.cancel();
    _eventSubscription?.cancel();
    _debounce?.cancel();
    _sleepTimer?.cancel();
    _controlsTimer?.cancel();
    _scrollController.dispose();
    HistoryService.saveProgress(
      widget.filePath,
      widget.fileName,
      _currentPageIndex * 3000,
    );
    super.dispose();
  }

  // --- NEW: LOAD USER PREFERENCES ---
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _speechRate = prefs.getDouble('default_speed') ?? 0.5;
        _pitch = prefs.getDouble('default_pitch') ?? 1.0;
        _keepScreenOn = prefs.getBool('keep_screen_on') ?? false;
      });
      // Apply initial settings to engine
      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setPitch(_pitch);
      // Note: Actual screen wake lock would require 'wakelock_plus' plugin
      // For now we just store the preference.
    }
  }

  // --- IMMERSIVE MODE LOGIC ---
  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (!_controlsVisible) {
      if (mounted) setState(() => _controlsVisible = true);
    }
    if (_isPlaying) {
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _isPlaying) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _resetControlsTimer();
  }

  // --- AUDIO & CONTROLS SETUP ---
  Future<void> _setupAudioSystem() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _audioHandler = await TtsAudioHandler.init();

    _audioHandler?.setMediaItem(
      widget.fileName,
      "Initializing...",
      Duration.zero,
    );
    _audioHandler?.setPlaybackState(isPlaying: false);

    _playbackSubscription = _audioHandler?.playbackState.listen((state) {
      if (state.playing && !_isPlaying) {
        _playCurrentPage();
      } else if (!state.playing && _isPlaying) {
        _pausePlayback();
      }

      if (state.processingState == AudioProcessingState.idle && _isPlaying) {
        _stopPlayback();
      }
    });

    _eventSubscription = _audioHandler?.customEvent.listen((event) {
      if (event == 'fastForward') _skipForward();
      if (event == 'rewind') _skipBackward();
    });

    await _flutterTts.awaitSpeakCompletion(true);
    // These calls are redundant with _loadPreferences but safe to keep
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setPitch(_pitch);

    await _flutterTts
        .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ]);

    _flutterTts.setProgressHandler((
      String text,
      int start,
      int end,
      String word,
    ) {
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
        _stopPlayback();
      }
    });

    _initVoices();
  }

  Future<void> _initVoices() async {
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final voices = await _flutterTts.getVoices;
      if (voices == null) return;
      const allowedCodes = ['en', 'fr', 'es'];
      List<Map<String, String>> cleanVoices = [];
      for (var voice in voices) {
        Map<Object?, Object?> rawMap = voice as Map<Object?, Object?>;
        if (rawMap.containsKey("name") && rawMap.containsKey("locale")) {
          String locale = rawMap["locale"].toString().toLowerCase();
          if (allowedCodes.any((code) => locale.startsWith(code))) {
            cleanVoices.add({
              "name": rawMap["name"].toString(),
              "locale": rawMap["locale"].toString(),
            });
          }
        }
      }
      if (mounted)
        setState(() {
          _voices = cleanVoices;
        });
    } catch (e) {
      debugPrint("Error fetching voices: $e");
    }
  }

  String _formatVoiceName(String rawName, String locale) {
    Map<String, String> langs = {
      'en': 'English',
      'fr': 'French',
      'es': 'Spanish',
    };
    String langCode = locale.split('-')[0].toLowerCase();
    String displayLang = langs[langCode] ?? langCode.toUpperCase();
    if (locale.contains('-')) {
      String country = locale.split('-')[1].toUpperCase();
      return "$displayLang ($country)";
    }
    return displayLang;
  }

  Map<String, dynamic> _getVoiceDisplayInfo(String rawName, String locale) {
    String lowerName = rawName.toLowerCase();
    String label = "";
    IconData icon = Icons.record_voice_over;
    if (lowerName.contains("female") ||
        lowerName.contains("-f-") ||
        lowerName.contains("woman")) {
      label = "Woman's Voice";
      icon = Icons.face_3;
    } else if (lowerName.contains("male") ||
        lowerName.contains("-m-") ||
        lowerName.contains("man")) {
      label = "Man's Voice";
      icon = Icons.face;
    }
    String prettyName = _formatVoiceName(rawName, locale);
    String title = label.isNotEmpty ? "$label - $prettyName" : prettyName;
    return {"title": title, "subtitle": locale, "icon": icon};
  }

  // --- FILE LOGIC & STATS ---

  Future<void> _loadOrExtractText() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = "Checking cache...";
    });
    String? cachedText = await _checkCache();
    if (cachedText != null && cachedText.isNotEmpty) {
      await _processFullText(cachedText);
      return;
    }
    await _extractTextAndCache();
  }

  Future<void> _processFullText(String fullText) async {
    setState(() {
      _loadingMessage = "Paginating document...";
    });
    List<String> pages = await compute(_backgroundPagination, fullText);

    int savedGlobalIndex =
        widget.initialIndex ??
        await HistoryService.getLastPosition(widget.filePath);
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

      // STATS: Record book open
      StatsService.recordBookOpen(widget.filePath);

      _audioHandler?.setMediaItem(
        widget.fileName,
        "Page ${savedPage + 1} of ${pages.length}",
        Duration.zero,
      );

      if (widget.initialIndex != null) {
        int pageOffset = savedGlobalIndex % 3000;
        if (pageOffset < _pages[savedPage].length) {
          _currentWordStart = pageOffset;
          _currentSpeechOffset = pageOffset;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Jumped to bookmark")));
      } else if (savedPage > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Resumed at page ${savedPage + 1}")),
        );
      }
    }
  }

  Future<void> _loadPageContent(int index) async {
    if (index < 0 || index >= _pages.length) return;
    String content = _pages[index];
    if (_currentLang != 'en') {
      setState(() {
        _loadingMessage = "Translating...";
        _isLoading = true;
      });
      await Future.delayed(const Duration(milliseconds: 50));
      content = await TranslationService.translate(content, _currentLang);
      setState(() {
        _isLoading = false;
      });
    }
    setState(() {
      _currentPageContent = content;
      _currentWordStart = 0;
      _currentWordEnd = 0;
      _currentSpeechOffset = 0;
    });
    _refreshBookmarks();
    _audioHandler?.setMediaItem(
      widget.fileName,
      "Page ${index + 1} of ${_pages.length}",
      Duration.zero,
    );
  }

  Future<void> _changePage(int newIndex, {bool autoPlay = false}) async {
    if (newIndex < 0 || newIndex >= _pages.length) return;
    await _flutterTts.stop();

    // STATS: Record page turn
    if (newIndex > _currentPageIndex) {
      StatsService.incrementPageCount();
    }

    setState(() {
      _currentPageIndex = newIndex;
    });
    await _loadPageContent(newIndex);
    if (autoPlay) {
      _playCurrentPage();
    } else {
      setState(() => _isPlaying = false);
      _audioHandler?.setPlaybackState(isPlaying: false);
    }
  }

  Future<void> _playCurrentPage() async {
    setState(() => _isPlaying = true);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setPitch(_pitch);
    String textToSpeak = _currentPageContent;
    if (_currentWordStart > 0 &&
        _currentWordStart < _currentPageContent.length) {
      textToSpeak = _currentPageContent.substring(_currentWordStart);
      _currentSpeechOffset = _currentWordStart;
    } else {
      _currentSpeechOffset = 0;
    }
    await _flutterTts.speak(textToSpeak);
    _audioHandler?.setPlaybackState(isPlaying: true);
    _resetControlsTimer();
  }

  Future<void> _pausePlayback() async {
    await _flutterTts.stop();
    if (mounted) setState(() => _isPlaying = false);
    _audioHandler?.setPlaybackState(isPlaying: false);
    setState(() => _controlsVisible = true);
  }

  Future<void> _stopPlayback() async {
    await _flutterTts.stop();
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _currentWordStart = 0;
        _currentWordEnd = 0;
        _currentSpeechOffset = 0;
        _controlsVisible = true;
      });
    }
    _audioHandler?.stop();
  }

  void _skipForward() {
    int newPos = _currentWordStart + 150;
    if (newPos >= _currentPageContent.length)
      newPos = _currentPageContent.length - 1;
    _playFromIndex(newPos);
  }

  void _skipBackward() {
    int newPos = _currentWordStart - 150;
    if (newPos < 0) newPos = 0;
    _playFromIndex(newPos);
  }

  void _playFromIndex(int index) async {
    setState(() {
      _currentWordStart = index;
      _currentSpeechOffset = index;
      _isPlaying = true;
    });

    await _flutterTts.stop();
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setPitch(_pitch);
    _audioHandler?.setPlaybackState(isPlaying: true);

    if (index < _currentPageContent.length) {
      await _flutterTts.speak(_currentPageContent.substring(index));
    }
    _resetControlsTimer();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _pausePlayback();
    } else {
      await _playCurrentPage();
    }
  }

  Future<void> _addBookmark([int? targetIndex]) async {
    int localIndex = targetIndex ?? _currentWordStart;
    int globalIndex = (_currentPageIndex * 3000) + localIndex;
    int endSnippet = localIndex + 50;
    if (endSnippet > _currentPageContent.length)
      endSnippet = _currentPageContent.length;
    String snippet =
        _currentPageContent
            .substring(localIndex, endSnippet)
            .replaceAll("\n", " ") +
        "...";
    await BookmarkService.addBookmark(
      filePath: widget.filePath,
      fileName: widget.fileName,
      index: globalIndex,
      snippet: snippet,
    );
    _refreshBookmarks();
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Bookmark Saved!")));
  }

  Future<void> _removeBookmark(int localIndex) async {
    int globalIndex = (_currentPageIndex * 3000) + localIndex;
    await BookmarkService.deleteBookmarkByPosition(
      widget.filePath,
      globalIndex,
    );
    _refreshBookmarks();
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Bookmark Removed")));
  }

  void _showBookmarkInfo(String snippet, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Bookmark"),
        content: Text(snippet),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeBookmark(index);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshBookmarks() async {
    List<Map<String, dynamic>> fileBookmarks =
        await BookmarkService.getBookmarksForFile(widget.filePath);
    Set<int> indices = {};
    int pageStart = _currentPageIndex * 3000;
    int pageEnd = pageStart + _currentPageContent.length;
    for (var b in fileBookmarks) {
      int idx = b['index'] as int;
      if (idx >= pageStart && idx < pageEnd) {
        indices.add(idx - pageStart);
      }
    }
    if (mounted) setState(() => _pageBookmarkIndices = indices);
  }

  Future<void> _extractTextAndCache() async {
    try {
      File file = File(widget.filePath);
      String rawText = "";
      String ext = widget.filePath.toLowerCase();
      setState(() {
        _loadingMessage = "Processing file...";
      });

      if (ext.endsWith('.pdf')) {
        rawText = await ReadPdfText.getPDFtext(widget.filePath);
      } else if (ext.endsWith('.txt')) {
        rawText = await file.readAsString();
      } else if (ext.endsWith('.docx')) {
        final bytes = await file.readAsBytes();
        rawText = docxToText(bytes);
      } else if (ext.endsWith('.jpg') ||
          ext.endsWith('.png') ||
          ext.endsWith('.jpeg')) {
        final inputImage = InputImage.fromFile(file);
        final textRecognizer = TextRecognizer(
          script: TextRecognitionScript.latin,
        );
        try {
          final RecognizedText recognizedText = await textRecognizer
              .processImage(inputImage);
          rawText = recognizedText.text;
        } finally {
          textRecognizer.close();
        }
        if (rawText.isEmpty) rawText = "No text found.";
      } else {
        rawText = "Unsupported file type.";
      }

      setState(() {
        _loadingMessage = "Optimizing...";
      });
      String cleanText = await compute(_backgroundCleanText, rawText);
      await _saveToCache(cleanText);
      await _processFullText(cleanText);
    } catch (e) {
      if (mounted)
        setState(() {
          _isLoading = false;
          _currentPageContent = "Error reading file: $e";
        });
    }
  }

  Future<String?> _checkCache() async {
    try {
      final directory = await getApplicationCacheDirectory();
      final String cacheKey = widget.filePath.hashCode.toString();
      final File cacheFile = File('${directory.path}/$cacheKey.txt');
      if (await cacheFile.exists()) return await cacheFile.readAsString();
    } catch (e) {
      debugPrint("Cache error: $e");
    }
    return null;
  }

  Future<void> _saveToCache(String text) async {
    try {
      final directory = await getApplicationCacheDirectory();
      final String cacheKey = widget.filePath.hashCode.toString();
      final File cacheFile = File('${directory.path}/$cacheKey.txt');
      await cacheFile.writeAsString(text);
    } catch (e) {
      debugPrint("Save cache error: $e");
    }
  }

  Future<void> _setVoice(Map<String, String> voice) async {
    try {
      await _flutterTts.stop();
      await _flutterTts.setLanguage(voice["locale"]!);
      await _flutterTts.setVoice({
        "name": voice["name"]!,
        "locale": voice["locale"]!,
      });
      setState(() {
        _currentVoice = voice;
        _isPlaying = false;
      });
      _audioHandler?.setPlaybackState(isPlaying: false);
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _changeLanguage(String langCode) async {
    if (langCode == _currentLang) return;
    setState(() {
      _currentLang = langCode;
    });
    await _loadPageContent(_currentPageIndex);
  }

  Future<void> _saveToAudioFile() async {
    if (_fullOriginalText.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Wait for file to load first.")),
        );
      return;
    }
    setState(() {
      _isLoading = true;
      _loadingMessage = "Creating Audio File...";
    });
    try {
      String fileName = widget.fileName.replaceAll(RegExp(r'[^\w\s]+'), '');
      if (fileName.length > 20) fileName = fileName.substring(0, 20);
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      if (!await dir.exists()) dir = await getExternalStorageDirectory();
      String filePath = "${dir!.path}/AUDIRE_$fileName.wav";
      String textToSave = _currentPageContent;
      await _flutterTts.synthesizeToFile(textToSave, "AUDIRE_$fileName.wav");
      setState(() {
        _isLoading = false;
      });
      if (mounted)
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Audio Saved!"),
            content: Text(
              "File saved as AUDIRE_$fileName.wav\n\nCheck your Music or Internal Storage.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("OK"),
              ),
            ],
          ),
        );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error saving audio: $e")));
    }
  }

  void _showVoicePicker() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        // Filter voices based on current content language
        String targetPrefix = 'en';
        if (_currentLang == 'fr') targetPrefix = 'fr';
        if (_currentLang == 'es') targetPrefix = 'es';
        // 'bem' and 'nya' default to 'en'

        List<Map<String, String>> filteredVoices = _voices.where((v) {
          return v['locale']!.toLowerCase().startsWith(targetPrefix);
        }).toList();

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                "Select Voice",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filteredVoices.isEmpty
                    ? const Center(
                        child: Text("No voices found for this language."),
                      )
                    : ListView.builder(
                        itemCount: filteredVoices.length,
                        itemBuilder: (c, i) {
                          var voice = filteredVoices[i];
                          var displayInfo = _getVoiceDisplayInfo(
                            voice["name"]!,
                            voice["locale"]!,
                          );

                          bool isSelected =
                              _currentVoice != null &&
                              _currentVoice!['name'] == voice['name'] &&
                              _currentVoice!['locale'] == voice['locale'];

                          return ListTile(
                            leading: Icon(
                              displayInfo['icon'],
                              color: Colors.grey,
                            ),
                            title: Text(displayInfo['title']),
                            subtitle: Text(displayInfo['subtitle']),
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.deepPurple,
                                  )
                                : null,
                            onTap: () {
                              _setVoice(voice);
                              Navigator.pop(ctx);
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

  void _showLanguagePicker() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Translate To",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              ListTile(
                title: const Text('English (Original)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeLanguage('en');
                },
              ),
              ListTile(
                title: const Text('Bemba (Zambia)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeLanguage('bem');
                },
              ),
              ListTile(
                title: const Text('Nyanja (Zambia)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeLanguage('nya');
                },
              ),
              ListTile(
                title: const Text('French'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeLanguage('fr');
                },
              ),
              ListTile(
                title: const Text('Spanish'),
                onTap: () {
                  Navigator.pop(ctx);
                  _changeLanguage('es');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAudioSettings() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (c, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Audio Settings",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Text("Speed: ${_speechRate.toStringAsFixed(1)}x"),
                  Slider(
                    value: _speechRate,
                    min: 0.1,
                    max: 2.0,
                    onChangeEnd: (v) {
                      if (_isPlaying) {
                        _pausePlayback();
                        Future.delayed(
                          const Duration(milliseconds: 200),
                          _playCurrentPage,
                        );
                      }
                    },
                    onChanged: (v) {
                      setState(() => _speechRate = v);
                      setModalState(() {});
                    },
                  ),
                  Text("Pitch: ${_pitch.toStringAsFixed(1)}"),
                  Slider(
                    value: _pitch,
                    min: 0.5,
                    max: 2.0,
                    onChangeEnd: (v) {
                      if (_isPlaying) {
                        _pausePlayback();
                        Future.delayed(
                          const Duration(milliseconds: 200),
                          _playCurrentPage,
                        );
                      }
                    },
                    onChanged: (v) {
                      setState(() => _pitch = v);
                      setModalState(() {});
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPageJumper() {
    if (!mounted) return;
    TextEditingController pageController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Jump to Page"),
        content: TextField(
          controller: pageController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: "Enter page number"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              int? page = int.tryParse(pageController.text);
              if (page != null && page > 0 && page <= _pages.length) {
                Navigator.pop(ctx);
                _changePage(page - 1);
              }
            },
            child: const Text("Go"),
          ),
        ],
      ),
    );
  }

  void _handleWordTap(String word, int startIndex) {
    if (!mounted) return;
    if (_isPlaying) _pausePlayback();
    bool isBookmarked = _pageBookmarkIndices.contains(startIndex);

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(
                  Icons.play_circle_fill,
                  color: Colors.deepPurple,
                ),
                title: const Text("Read from here"),
                onTap: () {
                  Navigator.pop(ctx);
                  _playFromIndex(startIndex);
                },
              ),
              ListTile(
                leading: Icon(
                  isBookmarked ? Icons.bookmark_remove : Icons.bookmark_add,
                  color: Colors.orange,
                ),
                title: Text(isBookmarked ? "Remove Bookmark" : "Bookmark this"),
                onTap: () async {
                  if (isBookmarked) {
                    _removeBookmark(startIndex);
                    Navigator.pop(ctx);
                  } else {
                    Navigator.pop(ctx);
                    _addBookmark(startIndex);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book, color: Colors.blue),
                title: const Text("Look up definition"),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDefinition(word);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDefinition(String word) async {
    String cleanWord = word.replaceAll(RegExp(r'[^\w\s]'), '');
    String? def = await DictionaryService.getDefinition(cleanWord);
    StatsService.incrementWordLookup();
    if (mounted)
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(cleanWord),
          content: Text(def ?? "Definition not found."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Close"),
            ),
          ],
        ),
      );
  }

  // --- SLEEP TIMER ---
  void _showSleepTimerDialog() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Sleep Timer",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  if (_sleepTimer != null && _sleepTimer!.isActive)
                    TextButton(
                      onPressed: () {
                        _sleepTimer?.cancel();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Timer Cancelled")),
                        );
                      },
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.timer_10),
                title: const Text("10 Minutes"),
                onTap: () => _setTimer(10, ctx),
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text("20 Minutes"),
                onTap: () => _setTimer(20, ctx),
              ),
              ListTile(
                leading: const Icon(Icons.timelapse),
                title: const Text("30 Minutes"),
                onTap: () => _setTimer(30, ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  void _setTimer(int minutes, BuildContext ctx) {
    _sleepTimer?.cancel();
    Navigator.pop(ctx);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Audio will stop in $minutes minutes")),
    );
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      if (mounted) {
        _pausePlayback();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Sleep Timer ended.")));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 20),
                              Text(
                                _loadingMessage,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 60.0,
                                bottom: 80.0,
                              ), // Padding to avoid overlap
                              child: _buildInteractiveText(),
                            ),
                          ),
                        ),
                ),
                if (!_isLoading && _pages.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey.shade900
                        : Colors.grey.shade100,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios),
                          onPressed: _currentPageIndex > 0
                              ? () => _changePage(_currentPageIndex - 1)
                              : null,
                        ),
                        InkWell(
                          onTap: _showPageJumper,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              "Page ${_currentPageIndex + 1} of ${_pages.length}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios),
                          onPressed: _currentPageIndex < _pages.length - 1
                              ? () => _changePage(_currentPageIndex + 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // --- TOP APP BAR (Auto-Hiding) ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              top: _controlsVisible ? 0 : -100,
              left: 0,
              right: 0,
              child: AppBar(
                title: Text(
                  widget.fileName,
                  style: const TextStyle(fontSize: 14),
                ),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[900]
                    : Colors.deepPurple,
                foregroundColor: Colors.white,
                elevation: 4,
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      _resetControlsTimer();
                      switch (value) {
                        case 'bookmark':
                          _addBookmark();
                          break;
                        case 'save':
                          _saveToAudioFile();
                          break;
                        case 'voice':
                          _showVoicePicker();
                          break;
                        case 'translate':
                          _showLanguagePicker();
                          break;
                        case 'settings':
                          _showAudioSettings();
                          break;
                        case 'timer':
                          _showSleepTimerDialog();
                          break;
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      const PopupMenuItem(
                        value: 'bookmark',
                        child: Row(
                          children: [
                            Icon(Icons.bookmark_add, color: Colors.grey),
                            SizedBox(width: 10),
                            Text('Bookmark Page'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'save',
                        child: Row(
                          children: [
                            Icon(Icons.save_alt, color: Colors.grey),
                            SizedBox(width: 10),
                            Text('Save Audio'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'timer',
                        child: Row(
                          children: [
                            Icon(Icons.timer, color: Colors.grey),
                            SizedBox(width: 10),
                            Text('Sleep Timer'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'voice',
                        child: Row(
                          children: [
                            Icon(Icons.record_voice_over, color: Colors.grey),
                            SizedBox(width: 10),
                            Text('Select Voice'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'translate',
                        child: Row(
                          children: [
                            Icon(Icons.translate, color: Colors.grey),
                            SizedBox(width: 10),
                            Text('Translate'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(Icons.tune, color: Colors.grey),
                            SizedBox(width: 10),
                            Text('Audio Settings'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- BOTTOM CONTROLS (Auto-Hiding) ---
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              bottom: _controlsVisible ? 80 : -100, // Hide below screen
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.stop, color: Colors.red),
                        onPressed: _stopPlayback,
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.replay_10),
                        onPressed: _skipBackward,
                      ),
                      const SizedBox(width: 10),
                      FloatingActionButton(
                        heroTag: "play",
                        onPressed: _togglePlay,
                        mini: false,
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.forward_10),
                        onPressed: _skipForward,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveText() {
    if (_currentPageContent.isEmpty) return const Text("No text.");
    List<InlineSpan> spans = [];
    int currentIndex = 0;
    List<String> rawWords = _currentPageContent.split(' ');
    for (String word in rawWords) {
      final int wordStart = currentIndex;
      final int wordEnd = currentIndex + word.length;
      bool isHighlighted =
          _currentWordStart >= wordStart && _currentWordStart < wordEnd;
      bool isBookmarked = _pageBookmarkIndices.contains(wordStart);

      if (isBookmarked) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () {
                String snippet = _currentPageContent.substring(
                  wordStart,
                  (wordStart + 50 < _currentPageContent.length)
                      ? wordStart + 50
                      : _currentPageContent.length,
                );
                _showBookmarkInfo(snippet + "...", wordStart);
              },
              onDoubleTap: () {
                _removeBookmark(wordStart);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2.0),
                child: Text("🔖", style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        );
      }

      spans.add(
        TextSpan(
          text: "$word ",
          style: TextStyle(
            fontSize: 18,
            height: 1.6,
            decoration: isBookmarked ? TextDecoration.underline : null,
            decorationColor: Colors.orange,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
            backgroundColor: isHighlighted ? Colors.yellow : null,
            fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _handleWordTap(word.trim(), wordStart),
        ),
      );
      currentIndex += word.length + 1;
    }
    return RichText(
      textAlign: TextAlign.justify,
      text: TextSpan(children: spans),
    );
  }
}
