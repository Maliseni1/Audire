import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Variable to store the name of the selected file (for testing)
  String _statusMessage = "No file selected";

  // FUNCTION: Pick a file
  Future<void> _pickFile() async {
    // 1. Check permissions (Crucial for Android 13+)
    var status = await Permission.storage.request();
    
    // Note: For Android 13+ (SDK 33), storage permission behavior changed.
    // We will handle specific audio/media permissions later. 
    // For now, let's try to pick a file directly.

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
    );

    if (result != null) {
      // User picked a file
      String fileName = result.files.single.name;
      setState(() {
        _statusMessage = "Selected: $fileName\nReady to read!";
      });
      // TODO: Send this file to the Reader/Player screen
    } else {
      // User canceled the picker
      setState(() {
        _statusMessage = "File selection canceled";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AUDIRE"),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            const Icon(
              Icons.audio_file_outlined,
              size: 100,
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 20),
            
            // Status Text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 40),

            // Pick Button
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.add),
              label: const Text("Open File"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}