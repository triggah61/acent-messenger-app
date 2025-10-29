import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config_service.dart';
import 'google_stt_service.dart';
import 'stt_provider.dart';

class AssemblyAiSttService implements SttProvider {
  String? _apiKey;
  bool _isInitialized = false;

  /// Convert Google STT language codes to AssemblyAI format
  /// AssemblyAI uses ISO 639-1 codes (en, bn, es, etc.)
  /// Google uses extended codes (en-US, bn-IN, etc.)
  String _convertToAssemblyAiLanguageCode(String googleLangCode) {
    // Extract base language code (e.g., "en" from "en-US", "bn" from "bn-IN")
    final parts = googleLangCode.split('-');
    final baseCode = parts[0].toLowerCase();

    // AssemblyAI supported languages mapping
    final Map<String, String> mapping = {
      'en': 'en',
      'bn': 'bn',
      'hi': 'hi', // Hindi
      'si': 'si', // Sinhala
      'es': 'es',
      'fr': 'fr',
      'de': 'de',
      'it': 'it',
      'pt': 'pt',
      'ru': 'ru',
      'zh': 'zh',
      'ja': 'ja',
      'ko': 'ko',
      'ar': 'ar',
      'ms': 'ms',
      // Add more as needed
    };

    final convertedCode = mapping[baseCode] ?? baseCode;
    debugPrint(
        'AssemblyAiSttService: Converting language code: $googleLangCode -> $convertedCode');
    return convertedCode;
  }

  @override
  Future<bool> initialize() async {
    try {
      final config = await ConfigService.instance.getConfig();
      _apiKey = config['assemblyaiApiKey'] as String?;
      if (_apiKey == null || _apiKey!.isEmpty) {
        debugPrint('AssemblyAiSttService: No API key found in config');
        _isInitialized = false;
        return false;
      }
      _isInitialized = true;
      debugPrint(
          'AssemblyAiSttService: Initialized with API key: ${_apiKey!.substring(0, 8)}...');
      return true;
    } catch (e) {
      debugPrint('AssemblyAiSttService: Failed to initialize: $e');
      _isInitialized = false;
      return false;
    }
  }

  @override
  Future<DiarizationResult?> transcribeWithDiarization({
    required Uint8List audioBytes,
    required String languageCode,
    List<String>? alternativeLanguages,
    int minSpeakers = 2,
    int maxSpeakers = 6,
  }) async {
    if (!_isInitialized || _apiKey == null) {
      debugPrint('AssemblyAiSttService: Not initialized');
      return null;
    }
    try {
      // Validate audio data
      if (audioBytes.isEmpty) {
        debugPrint('AssemblyAiSttService: Audio bytes are empty');
        return null;
      }

      // 1) Upload audio
      debugPrint(
          'AssemblyAiSttService: Starting upload of ${audioBytes.length} bytes');
      final uploadUrl = Uri.parse('https://api.assemblyai.com/v2/upload');
      final uploadResp = await http.post(
        uploadUrl,
        headers: {
          'Authorization': _apiKey!,
          'Content-Type': 'application/octet-stream',
        },
        body: audioBytes,
      );
      debugPrint(
          'AssemblyAiSttService: Upload status ${uploadResp.statusCode}');
      debugPrint('AssemblyAiSttService: Upload response: ${uploadResp.body}');
      if (uploadResp.statusCode != 200) {
        debugPrint('AssemblyAiSttService: Upload failed: ${uploadResp.body}');
        return null;
      }
      final uploadData = jsonDecode(uploadResp.body);
      final audioUrl = uploadData['upload_url'] as String?;
      if (audioUrl == null) {
        debugPrint('AssemblyAiSttService: Missing upload_url in response');
        return null;
      }

      // 2) Request transcript with speaker labels and automatic language detection
      final transcriptUrl =
          Uri.parse('https://api.assemblyai.com/v2/transcript');

      // Build expected languages list from languageCode and alternativeLanguages
      final List<String> expectedLanguages = [];
      if (languageCode.isNotEmpty) {
        expectedLanguages.add(_convertToAssemblyAiLanguageCode(languageCode));
      }
      if (alternativeLanguages != null) {
        for (final altLang in alternativeLanguages) {
          final convertedLang = _convertToAssemblyAiLanguageCode(altLang);
          if (!expectedLanguages.contains(convertedLang)) {
            expectedLanguages.add(convertedLang);
          }
        }
      }

      debugPrint(
          'AssemblyAiSttService: Expected languages: $expectedLanguages');

      final requestBody = <String, dynamic>{
        'audio_url': audioUrl,
        'speaker_labels': true,
        'language_detection': true,
        if (expectedLanguages.isNotEmpty)
          'language_detection_options': {
            'expected_languages': expectedLanguages,
            // Prefer the primary language for this call when AAI is unsure
            'fallback_language': _convertToAssemblyAiLanguageCode(languageCode),
          },
      };

      debugPrint(
          'AssemblyAiSttService: Request body: ${jsonEncode(requestBody)}');

      // Submit transcript
      final createResp = await http.post(
        transcriptUrl,
        headers: {
          'Authorization': _apiKey!,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );
      debugPrint(
          'AssemblyAiSttService: Create transcript status ${createResp.statusCode}');
      if (createResp.statusCode != 200) {
        debugPrint(
            'AssemblyAiSttService: Create transcript failed: ${createResp.body}');
        return null;
      }
      final createData = jsonDecode(createResp.body);
      final String? transcriptId = createData['id'];
      if (transcriptId == null) {
        debugPrint('AssemblyAiSttService: Missing transcript id');
        return null;
      }

      // 3) Poll transcript status
      final pollUrl =
          Uri.parse('https://api.assemblyai.com/v2/transcript/$transcriptId');
      Map<String, dynamic>? finalData;
      for (int i = 0; i < 60; i++) {
        final pollResp = await http.get(
          pollUrl,
          headers: {'Authorization': _apiKey!},
        );
        if (pollResp.statusCode != 200) {
          debugPrint('AssemblyAiSttService: Poll failed: ${pollResp.body}');
          return null;
        }
        final data = jsonDecode(pollResp.body) as Map<String, dynamic>;
        final status = data['status'] as String?;
        debugPrint('AssemblyAiSttService: Poll status: $status');
        if (status == 'completed') {
          finalData = data;
          break;
        } else if (status == 'error') {
          debugPrint(
              'AssemblyAiSttService: Transcription error: ${data['error']}');
          return null;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
      if (finalData == null) {
        debugPrint('AssemblyAiSttService: Poll timed out');
        return null;
      }
      debugPrint(
          'AssemblyAiSttService: Final response: ${jsonEncode(finalData)}');

      // 4) Parse into DiarizationResult
      final diarizedSegments = <DiarizedSegment>[];
      final words = (finalData['words'] as List?) ?? [];
      // AssemblyAI returns words with speaker labels if enabled
      for (final w in words) {
        final wm = w as Map<String, dynamic>;
        final text = wm['text'] as String? ?? '';
        final startMs = (wm['start'] as num?)?.toDouble() ?? 0.0; // ms
        final endMs = (wm['end'] as num?)?.toDouble() ?? 0.0; // ms
        final speaker = wm['speaker'] as String?; // e.g. 'A', 'B'
        final speakerTag = _mapSpeakerToTag(speaker);
        // Aggregate words into segments by speaker; for simplicity, we create one segment per speaker block
        diarizedSegments.add(DiarizedSegment(
          text: text,
          speakerTag: speakerTag,
          startTime: startMs / 1000.0,
          endTime: endMs / 1000.0,
          confidence: 0.0,
        ));
      }

      // Merge contiguous words by speaker into segments
      final merged = <DiarizedSegment>[];
      for (final seg in diarizedSegments) {
        if (merged.isEmpty || merged.last.speakerTag != seg.speakerTag) {
          merged.add(seg);
        } else {
          final last = merged.removeLast();
          merged.add(DiarizedSegment(
            text: last.text.isEmpty ? seg.text : '${last.text} ${seg.text}',
            speakerTag: last.speakerTag,
            startTime: last.startTime,
            endTime: seg.endTime,
            confidence: 0.0,
          ));
        }
      }

      final fullTranscript = merged.map((e) => e.text).join(' ').trim();
      final speakerCount = merged.map((e) => e.speakerTag).toSet().length;
      return DiarizationResult(
        segments: merged,
        speakerCount: speakerCount,
        fullTranscript: fullTranscript,
      );
    } catch (e) {
      debugPrint('AssemblyAiSttService: Exception: $e');
      return null;
    }
  }

  int _mapSpeakerToTag(String? label) {
    // Map 'A'->0, 'B'->1, else 0
    if (label == null) return 0;
    final l = label.toUpperCase();
    if (l == 'A') return 0;
    if (l == 'B') return 1;
    // Try parse numeric
    final n = int.tryParse(l);
    if (n != null) return n;
    return 0;
  }
}
