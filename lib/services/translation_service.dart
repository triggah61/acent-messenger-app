import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/config.dart';
import 'auth_service.dart';

class TranslationResult {
  final String translatedText;
  final String message;

  TranslationResult({
    required this.translatedText,
    required this.message,
  });

  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    return TranslationResult(
      translatedText: json['data'] ?? '',
      message: json['message'] ?? '',
    );
  }
}

class TranslationService {
  static final AuthService _authService = AuthService();

  /// Translate text from source language to target language
  static Future<TranslationResult?> translateText({
    required String sourceLanguage,
    required String targetLanguage,
    required String content,
  }) async {
    try {
      // Get the authentication token
      String? token = await _authService.getToken();
      if (token == null) {
        print('TranslationService: No authentication token found');
        return null;
      }

      // Prepare the request body
      Map<String, dynamic> body = {
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'content': content,
      };

      print('TranslationService: Sending translation request');
      print('Source: $sourceLanguage, Target: $targetLanguage');
      print('Content: $content');

      // Make the HTTP request
      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/translation/translate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      print('TranslationService: Response status: ${response.statusCode}');
      print('TranslationService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);

        TranslationResult result = TranslationResult.fromJson(responseData);
        print(
            'TranslationService: Translation successful: ${result.translatedText}');

        return result;
      } else {
        print(
            'TranslationService: Translation failed with status: ${response.statusCode}');
        print('TranslationService: Error response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('TranslationService: Exception during translation: $e');
      return null;
    }
  }

  /// Validate if translation is needed (different languages)
  static bool isTranslationNeeded(
      String sourceLanguage, String targetLanguage) {
    return sourceLanguage.toLowerCase() != targetLanguage.toLowerCase();
  }

  /// Get language display name from code
  static String getLanguageDisplayName(String languageCode) {
    const Map<String, String> languageNames = {
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'bn': 'Bengali',
      'ur': 'Urdu',
      'ms': 'Malay',
    };

    return languageNames[languageCode.toLowerCase()] ??
        languageCode.toUpperCase();
  }
}
