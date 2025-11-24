import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class FileScanner {
  // Target folders to scan
  static final List<String> _targetFolders = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Books',
    // You can add more paths here if needed
  ];

  static final List<String> _allowedExtensions = ['.pdf', '.txt', '.docx'];

  /// Scans the device for compatible files
  static Future<List<FileSystemEntity>> scanDeviceForFiles() async {
    List<FileSystemEntity> foundFiles = [];

    // 1. CHECK PERMISSIONS RIGOROUSLY
    // Android 11+ (SDK 30+) requires MANAGE_EXTERNAL_STORAGE
    if (await Permission.manageExternalStorage.request().isGranted) {
      // Permission granted for Android 11+
    } 
    // Older Android versions use standard storage permission
    else if (await Permission.storage.request().isGranted) {
      // Permission granted for older Android
    } else {
      // Permission denied
      return [];
    }

    // 2. SCAN FOLDERS
    for (String path in _targetFolders) {
      final dir = Directory(path);
      
      if (await dir.exists()) {
        try {
          // Recursive scan: checks folders inside folders
          await for (var entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              if (_isAllowed(entity.path)) {
                foundFiles.add(entity);
              }
            }
          }
        } catch (e) {
          // Some system folders might be locked, we skip them silently
          print("Skipping access to $path: $e");
        }
      }
    }
    
    return foundFiles;
  }

  // Helper to check file extensions
  static bool _isAllowed(String path) {
    String lowerPath = path.toLowerCase();
    for (var ext in _allowedExtensions) {
      if (lowerPath.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }
}