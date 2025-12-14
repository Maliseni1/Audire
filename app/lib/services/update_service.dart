import 'dart:convert';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // CORRECTED CONFIGURATION
  static const String _owner = "maliseni1";
  static const String _repo = "audire";

  static Future<Map<String, dynamic>> checkForUpdate() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version.isNotEmpty
          ? packageInfo.version
          : "1.0.0";

      debugPrint("Current App Version: $currentVersion");

      // Use the variables here
      final Uri url = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );
      debugPrint("Checking URL: $url");

      final response = await http.get(url);
      debugPrint("Response Code: ${response.statusCode}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> releaseData = json.decode(response.body);

        String? latestTag = releaseData['tag_name']?.toString();

        if (latestTag == null) {
          return {
            'error': "GitHub returned valid connection but no tag name found.",
          };
        }

        debugPrint("Latest GitHub Tag: $latestTag");

        String cleanLatest = latestTag.replaceAll('v', '').trim();
        String cleanCurrent = currentVersion.replaceAll('v', '').trim();

        if (cleanLatest != cleanCurrent) {
          return {
            'updateAvailable': true,
            'latestVersion': latestTag,
            'currentVersion': currentVersion,
            'downloadUrl':
                releaseData['html_url'] ??
                "https://github.com/$_owner/$_repo/releases",
            'body':
                releaseData['body']?.toString() ?? 'New features available.',
          };
        } else {
          return {'updateAvailable': false, 'currentVersion': currentVersion};
        }
      } else if (response.statusCode == 404) {
        return {
          'error':
              "Repository not found (404).\n\n1. Check if '$_owner/$_repo' is correct.\n2. Ensure the Repository is PUBLIC.",
        };
      } else {
        return {
          'error':
              "GitHub Error: ${response.statusCode}\n${response.reasonPhrase}",
        };
      }
    } catch (e) {
      return {'error': "Crash: $e"};
    }
  }

  static Future<void> launchUpdateUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }
}
