import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/config.dart';
import 'auth_service.dart';

/// Service for managing translation sessions
/// Handles session lifecycle: start, stop, add translations, fetch history
class TranslationSessionService {
  static final TranslationSessionService _instance =
      TranslationSessionService._internal();
  factory TranslationSessionService() => _instance;
  TranslationSessionService._internal();

  static TranslationSessionService get instance => _instance;

  final AuthService _authService = AuthService();

  /// Start a new translation session
  /// Returns Map with sessionId and fee rates if successful, null otherwise
  Future<Map<String, dynamic>?> startSession({
    required String speaker1Language,
    required String speaker2Language,
    String speaker1Earpiece = 'left',
    String speaker2Earpiece = 'right',
    String speaker1Gender = 'male',
    String speaker2Gender = 'female',
    String mode = 'realtime',
    bool twsConnected = false,
    String? twsDeviceName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('TranslationSessionService: 🚀 START SESSION API CALL');
      debugPrint('═══════════════════════════════════════════════════');

      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('TranslationSessionService: ❌ No auth token found');
        debugPrint('TranslationSessionService: User may not be logged in');
        return null;
      }
      debugPrint('TranslationSessionService: ✅ Auth token found: ${token.substring(0, 20)}...');

      final url = '${Config.baseApiUrl}/user/translation-session/start';
      debugPrint('TranslationSessionService: 📡 URL: $url');

      final requestBody = {
        'speaker1Language': speaker1Language,
        'speaker2Language': speaker2Language,
        'speaker1Earpiece': speaker1Earpiece,
        'speaker2Earpiece': speaker2Earpiece,
        'speaker1Gender': speaker1Gender,
        'speaker2Gender': speaker2Gender,
        'mode': mode,
        'twsConnected': twsConnected,
        'twsDeviceName': twsDeviceName,
        'metadata': metadata ?? {},
      };
      debugPrint('TranslationSessionService: 📦 Request body: ${jsonEncode(requestBody)}');

      debugPrint('TranslationSessionService: ⏳ Sending POST request...');
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      debugPrint('TranslationSessionService: 📨 Response status: ${response.statusCode}');
      debugPrint('TranslationSessionService: 📨 Response body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final sessionData = data['data'];
        final sessionId = sessionData['sessionId'];
        final appliedFeeRates = sessionData['appliedFeeRates'] ?? {};
        final balanceBeforeSession = (sessionData['balanceBeforeSession'] as num?)?.toDouble() ?? 0.0;
        
        debugPrint('TranslationSessionService: ✅✅✅ SESSION STARTED: $sessionId');
        debugPrint('TranslationSessionService: Fee rates: $appliedFeeRates');
        debugPrint('TranslationSessionService: Balance before: $balanceBeforeSession');
        debugPrint('═══════════════════════════════════════════════════');
        
        return {
          'sessionId': sessionId,
          'appliedFeeRates': appliedFeeRates,
          'balanceBeforeSession': balanceBeforeSession,
        };
      } else {
        debugPrint('TranslationSessionService: ❌ Failed to start session: ${response.statusCode}');
        debugPrint('TranslationSessionService: ❌ Error: ${response.body}');
        debugPrint('═══════════════════════════════════════════════════');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('TranslationSessionService: ❌❌❌ EXCEPTION starting session: $e');
      debugPrint('TranslationSessionService: Stack trace: $stackTrace');
      debugPrint('═══════════════════════════════════════════════════');
      return null;
    }
  }

  /// Stop a translation session and calculate final cost
  Future<Map<String, dynamic>?> stopSession({
    required String sessionId,
    required double totalAudioDurationSec,
    int totalInputTokens = 0,
    int totalTranscriptionCharacters = 0,
    int totalTranslationCharacters = 0,
    int totalOutputTokens = 0,
    int speaker1TranscriptionCharacters = 0,
    int speaker1TranslationCharacters = 0,
    int speaker2TranscriptionCharacters = 0,
    int speaker2TranslationCharacters = 0,
    int totalTranslations = 0,
    double averageLatencyMs = 0,
    String? errorMessage,
  }) async {
    try {
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('TranslationSessionService: 🛑 STOP SESSION API CALL');
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('Session ID: $sessionId');
      debugPrint('Audio duration: ${totalAudioDurationSec}s');
      debugPrint('Total translations: $totalTranslations');
      debugPrint('Transcription chars: $totalTranscriptionCharacters');
      debugPrint('Translation chars: $totalTranslationCharacters');

      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('TranslationSessionService: ❌ No auth token');
        debugPrint('TranslationSessionService: User may not be logged in');
        return null;
      }

      final url = '${Config.baseApiUrl}/user/translation-session/stop/$sessionId';
      debugPrint('TranslationSessionService: 📡 URL: $url');

      final requestBody = {
        'totalAudioDurationSec': totalAudioDurationSec,
        'totalInputTokens': totalInputTokens,
        'totalTranscriptionCharacters': totalTranscriptionCharacters,
        'totalTranslationCharacters': totalTranslationCharacters,
        'totalOutputTokens': totalOutputTokens,
        'speaker1TranscriptionCharacters': speaker1TranscriptionCharacters,
        'speaker1TranslationCharacters': speaker1TranslationCharacters,
        'speaker2TranscriptionCharacters': speaker2TranscriptionCharacters,
        'speaker2TranslationCharacters': speaker2TranslationCharacters,
        'totalTranslations': totalTranslations,
        'averageLatencyMs': averageLatencyMs,
        'errorMessage': errorMessage,
      };
      debugPrint('TranslationSessionService: 📦 Request: ${jsonEncode(requestBody)}');

      debugPrint('TranslationSessionService: ⏳ Sending POST request...');
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      debugPrint('TranslationSessionService: 📨 Response status: ${response.statusCode}');
      debugPrint('TranslationSessionService: 📨 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('TranslationSessionService: ✅✅✅ SESSION STOPPED');
        debugPrint('Total cost: ${data['data']['totalCost']} credits');
        debugPrint('═══════════════════════════════════════════════════');
        return data['data'];
      } else {
        debugPrint('TranslationSessionService: ❌ Failed: ${response.statusCode}');
        debugPrint('TranslationSessionService: ❌ Error: ${response.body}');
        debugPrint('═══════════════════════════════════════════════════');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('TranslationSessionService: ❌❌❌ EXCEPTION: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('═══════════════════════════════════════════════════');
      return null;
    }
  }

  /// Add a translation record to the session
  Future<bool> addTranslation({
    required String sessionId,
    required int speakerIndex,
    required String transcriptionText,
    required String translationText,
    required String sourceLanguage,
    required String targetLanguage,
    String? speakerName,
    double latencyMs = 0,
    String translationService = 'soniox',
    Map<String, dynamic>? tts,
    int sequenceNumber = 0,
    bool isFinal = true,
    double? confidence,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      debugPrint('─────────────────────────────────────────────────');
      debugPrint('TranslationSessionService: 💾 ADD TRANSLATION #$sequenceNumber');
      debugPrint('Session ID: $sessionId');
      debugPrint('Speaker: $speakerIndex, Text length: ${transcriptionText.length}');

      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('TranslationSessionService: ❌ No auth token');
        debugPrint('TranslationSessionService: User may not be logged in');
        return false;
      }

      final url = '${Config.baseApiUrl}/user/translation-session/$sessionId/add-translation';
      debugPrint('TranslationSessionService: 📡 URL: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'speakerIndex': speakerIndex,
          'speakerName': speakerName ?? 'Speaker ${speakerIndex + 1}',
          'transcriptionText': transcriptionText,
          'translationText': translationText,
          'sourceLanguage': sourceLanguage,
          'targetLanguage': targetLanguage,
          'latencyMs': latencyMs,
          'translationService': translationService,
          'tts': tts ?? {},
          'sequenceNumber': sequenceNumber,
          'isFinal': isFinal,
          'confidence': confidence,
          'metadata': metadata ?? {},
        }),
      );

      debugPrint('TranslationSessionService: 📨 Status: ${response.statusCode}');

      if (response.statusCode == 201) {
        debugPrint('TranslationSessionService: ✅ Translation saved');
        debugPrint('─────────────────────────────────────────────────');
        return true;
      } else {
        debugPrint('TranslationSessionService: ❌ Failed: ${response.statusCode}');
        debugPrint('TranslationSessionService: Body: ${response.body}');
        debugPrint('─────────────────────────────────────────────────');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('TranslationSessionService: ❌ Exception: $e');
      debugPrint('Stack: $stackTrace');
      debugPrint('─────────────────────────────────────────────────');
      return false;
    }
  }

  /// Get user's translation sessions
  Future<Map<String, dynamic>?> getMySessions({
    int page = 1,
    int limit = 10,
    String? status,
  }) async {
    try {
      debugPrint('TranslationSessionService: Fetching user sessions...');

      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('TranslationSessionService: No auth token found');
        debugPrint('TranslationSessionService: User may not be logged in');
        return null;
      }

      String url =
          '${Config.baseApiUrl}/user/translation-session/my-sessions?page=$page&limit=$limit';
      if (status != null) {
        url += '&status=$status';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('TranslationSessionService: ✅ Sessions fetched successfully');
        return data['data'];
      } else {
        debugPrint(
            'TranslationSessionService: ❌ Failed to fetch sessions: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('TranslationSessionService: ❌ Error fetching sessions: $e');
      return null;
    }
  }

  /// Get session history (all translations in a session)
  Future<Map<String, dynamic>?> getSessionHistory({
    required String sessionId,
    int page = 1,
    int limit = 50,
    int? speakerIndex,
  }) async {
    try {
      debugPrint('TranslationSessionService: Fetching session history...');

      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('TranslationSessionService: No auth token found');
        debugPrint('TranslationSessionService: User may not be logged in');
        return null;
      }

      String url =
          '${Config.baseApiUrl}/user/translation-session/$sessionId/history?page=$page&limit=$limit';
      if (speakerIndex != null) {
        url += '&speakerIndex=$speakerIndex';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('TranslationSessionService: ✅ History fetched successfully');
        return data['data'];
      } else {
        debugPrint(
            'TranslationSessionService: ❌ Failed to fetch history: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('TranslationSessionService: ❌ Error fetching history: $e');
      return null;
    }
  }

  /// Get session details
  Future<Map<String, dynamic>?> getSessionDetails({
    required String sessionId,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return null;
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/translation-session/$sessionId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'];
      } else {
        return null;
      }
    } catch (e) {
      debugPrint('TranslationSessionService: Error fetching session details: $e');
      return null;
    }
  }

  /// Get session summary
  Future<Map<String, dynamic>?> getSessionSummary({
    required String sessionId,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return null;
      }

      final response = await http.get(
        Uri.parse(
            '${Config.baseApiUrl}/user/translation-session/$sessionId/summary'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'];
      } else {
        return null;
      }
    } catch (e) {
      debugPrint('TranslationSessionService: Error fetching session summary: $e');
      return null;
    }
  }

  /// Cancel/abort a translation session
  Future<bool> cancelSession({
    required String sessionId,
    String reason = 'User cancelled',
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return false;
      }

      final response = await http.post(
        Uri.parse(
            '${Config.baseApiUrl}/user/translation-session/$sessionId/cancel'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'reason': reason,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('TranslationSessionService: ✅ Session cancelled');
        return true;
      } else {
        return false;
      }
    } catch (e) {
      debugPrint('TranslationSessionService: Error cancelling session: $e');
      return false;
    }
  }

  /// Update session metrics (for real-time updates during session)
  Future<bool> updateSessionMetrics({
    required String sessionId,
    double? totalAudioDurationSec,
    int? totalInputTokens,
    double? averageLatencyMs,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        return false;
      }

      final body = <String, dynamic>{};
      if (totalAudioDurationSec != null) {
        body['totalAudioDurationSec'] = totalAudioDurationSec;
      }
      if (totalInputTokens != null) {
        body['totalInputTokens'] = totalInputTokens;
      }
      if (averageLatencyMs != null) {
        body['averageLatencyMs'] = averageLatencyMs;
      }

      final response = await http.patch(
        Uri.parse(
            '${Config.baseApiUrl}/user/translation-session/$sessionId/metrics'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('TranslationSessionService: Error updating metrics: $e');
      return false;
    }
  }
}

