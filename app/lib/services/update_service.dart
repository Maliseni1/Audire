import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // --- CONFIGURATION ---
  // CORRECTED: Centralized configuration
  static const String _owner = "maliseni1"; 
  static const String _repo = "audire";
  
  static Future<Map<String, dynamic>> checkForUpdate() async {
    try {
      // 1. Get Current App Version (Safely)
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      // Handle potential nulls from the plugin
      String currentVersion = packageInfo.version.isNotEmpty ? packageInfo.version : "1.0.0";
      
      print("Current App Version: $currentVersion");

      // 2. Get Latest Release from GitHub API
      // Uses the variables defined above
      final Uri url = Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');
      print("Checking URL: $url");
      
      final response = await http.get(url);
      print("Response Code: ${response.statusCode}");

      if (response.statusCode == 200) {
        // Parse JSON
        final Map<String, dynamic> releaseData = json.decode(response.body);
        
        // 3. Extract Tag Name (Safely)
        String? latestTag = releaseData['tag_name']?.toString();
        
        if (latestTag == null) {
          return {'error': "GitHub returned valid connection but no tag name found."};
        }

        print("Latest GitHub Tag: $latestTag");

        // Clean versions (remove 'v' prefix)
        String cleanLatest = latestTag.replaceAll('v', '').trim();
        String cleanCurrent = currentVersion.replaceAll('v', '').trim();

        // 4. Compare
        if (cleanLatest != cleanCurrent) {
          return {
            'updateAvailable': true,
            'latestVersion': latestTag,
            'currentVersion': currentVersion,
            'downloadUrl': releaseData['html_url'] ?? "https://github.com/$_owner/$_repo/releases",
            'body': releaseData['body']?.toString() ?? 'New features available.'
          };
        } else {
          return {
            'updateAvailable': false,
            'currentVersion': currentVersion,
          };
        }
      } else if (response.statusCode == 404) {
        // This is the most common error for new repos
        return {
          'error': "Repository not found (404).\n\n1. Check if '$_owner/$_repo' is correct.\n2. Ensure the Repository is PUBLIC (Private repos block this API)."
        };
      } else {
        return {
          'error': "GitHub Error: ${response.statusCode}\n${response.reasonPhrase}"
        };
      }
    } catch (e) {
      // Catch any other crash (like the Type Error you saw)
      return {
        'error': "Crash: $e",
      };
    }
  }

  static Future<void> launchUpdateUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }
}