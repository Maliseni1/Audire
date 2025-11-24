import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:read_pdf_text/read_pdf_text.dart';
import 'dart:io';

class ReaderScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const ReaderScreen({
    super.key, 
    required this.filePath, 
    required this.fileName
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  
  String _fileContent = "Loading text...";
  bool _isPlaying = false;
  double _speechRate = 0.5; // Normal speed (range is usually 0.0 to 1.0)
  
  // To track which word is being spoken (for highlighting - basic version)
  int _currentWordStart = 0;
  int _currentWordEnd = 0;

  @override
  void initState() {
    super.initState();
    _initTts();
    _extractText();
  }

  // 1. Initialize Text-to-Speech
  Future<void> _initTts() async {
    // Set up highlight handler
    _flutterTts.setProgressHandler((String text, int start, int end, String word) {
      setState(() {
        _currentWordStart = start;
        _currentWordEnd = end;
      });
    });

    // Handle when speaking finishes
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isPlaying = false;
        _currentWordStart = 0;
        _currentWordEnd = 0;
      });
    });
  }

  // 2. Extract Text based on file type
  Future<void> _extractText() async {
    try {
      String text = "";
      if (widget.filePath.endsWith('.pdf')) {
        text = await ReadPdfText.getPDFtext(widget.filePath);
      } else if (widget.filePath.endsWith('.txt')) {
        final file = File(widget.filePath);
        text = await file.readAsString();
      } else {
        text = "Sorry, this file type is not supported yet.\n(Only PDF and TXT for now)";
      }

      // Clean up text (remove excessive newlines)
      text = text.replaceAll('\n\n', '\n');

      setState(() {
        _fileContent = text;
      });
    } catch (e) {
      setState(() {
        _fileContent = "Error reading file: $e";
      });
    }
  }

  // 3. Audio Controls
  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _flutterTts.stop();
      setState(() => _isPlaying = false);
    } else {
      if (_fileContent.isNotEmpty) {
        setState(() => _isPlaying = true);
        await _flutterTts.setSpeechRate(_speechRate);
        await _flutterTts.speak(_fileContent);
      }
    }
  }

  Future<void> _changeSpeed() async {
    double newRate = _speechRate == 0.5 ? 0.75 : (_speechRate == 0.75 ? 1.0 : 0.5);
    setState(() => _speechRate = newRate);
    
    // If playing, update speed immediately
    if (_isPlaying) {
      await _flutterTts.stop();
      await _flutterTts.setSpeechRate(newRate);
      await _flutterTts.speak(_fileContent.substring(_currentWordStart)); // Resume near location
    }
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_speechRate == 0.5 ? Icons.speed : Icons.shutter_speed),
            onPressed: _changeSpeed,
            tooltip: "Speed: ${_speechRate}x",
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Text(
            _fileContent,
            style: const TextStyle(fontSize: 18, height: 1.5),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _togglePlay,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
        label: Text(_isPlaying ? "Pause" : "Read Aloud"),
      ),
    );
  }
}