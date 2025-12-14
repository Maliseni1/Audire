import 'dart:io';
import 'package:flutter/foundation.dart'; // Required for debugPrint
import 'package:permission_handler/permission_handler.dart';

class FileScanner {
  static final List<String> _targetFolders = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Documents',
    '/storage/emulated/0/Books',
    '/storage/emulated/0/DCIM/Camera',
    '/storage/emulated/0/Pictures',
  ];

  static final List<String> _allowedExtensions = [
    '.pdf',
    '.txt',
    '.docx',
    '.jpg',
    '.jpeg',
    '.png',
  ];

  static Future<List<FileSystemEntity>> scanDeviceForFiles() async {
    List<FileSystemEntity> foundFiles = [];

    if (await Permission.manageExternalStorage.request().isGranted) {
      // Android 11+
    } else if (await Permission.storage.request().isGranted) {
      // Older Android
    } else {
      return [];
    }

    for (String path in _targetFolders) {
      final dir = Directory(path);

      if (await dir.exists()) {
        try {
          await for (var entity in dir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File) {
              if (_isAllowed(entity.path)) {
                foundFiles.add(entity);
              }
            }
          }
        } catch (e) {
          debugPrint("Skipping access to $path: $e");
        }
      }
    }

    try {
      foundFiles.sort((a, b) {
        return b.statSync().modified.compareTo(a.statSync().modified);
      });
    } catch (e) {
      // Ignore sort errors
    }

    return foundFiles;
  }

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
