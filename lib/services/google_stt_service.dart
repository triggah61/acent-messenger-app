import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'config_service.dart';

/// Model for a diarized speech segment
class DiarizedSegment {
  final String text;
  final int speakerTag;
  final double startTime;
  final double endTime;
  final double confidence;

  DiarizedSegment({
    required this.text,
    required this.speakerTag,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });

  factory DiarizedSegment.fromJson(Map<String, dynamic> json) {
    return DiarizedSegment(
      text: json['text'] ?? '',
      speakerTag: json['speakerTag'] ?? 0,
      startTime: (json['startTime'] ?? 0).toDouble(),
      endTime: (json['endTime'] ?? 0).toDouble(),
      confidence: (json['confidence'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'speakerTag': speakerTag,
      'startTime': startTime,
      'endTime': endTime,
      'confidence': confidence,
    };
  }
}

/// Model for speaker diarization result
class DiarizationResult {
  final List<DiarizedSegment> segments;
  final int speakerCount;
  final String fullTranscript;

  DiarizationResult({
    required this.segments,
    required this.speakerCount,
    required this.fullTranscript,
  });

  factory DiarizationResult.fromJson(Map<String, dynamic> json) {
    final segments = (json['segments'] as List?)
            ?.map((s) => DiarizedSegment.fromJson(s))
            .toList() ??
        [];

    return DiarizationResult(
      segments: segments,
      speakerCount: json['speakerCount'] ?? 0,
      fullTranscript: json['fullTranscript'] ?? '',
    );
  }
}

/// Google Speech-to-Text service with speaker diarization
class GoogleSttService {
  static final GoogleSttService _instance = GoogleSttService._internal();
  factory GoogleSttService() => _instance;
  GoogleSttService._internal();

  static GoogleSttService get instance => _instance;

  String? _apiKey;
  bool _isInitialized = false;

  /// Initialize the service with API key from config
  Future<bool> initialize() async {
    try {
      debugPrint('GoogleSttService: Initializing...');

      final config = await ConfigService.instance.getConfig();
      _apiKey = config['googleSttApiKey'] as String?;

      if (_apiKey == null || _apiKey!.isEmpty) {
        debugPrint('GoogleSttService: No API key found');
        _isInitialized = false;
        return false;
      }

      _isInitialized = true;
      debugPrint('GoogleSttService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('GoogleSttService: Initialization failed: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Transcribe audio with speaker diarization and multi-language support
  ///
  /// [audioBytes] - The audio file bytes (WAV, FLAC, or OGG format recommended)
  /// [languageCode] - The primary language code (e.g., 'en-US', 'es-ES')
  /// [alternativeLanguages] - Additional language codes to detect (optional)
  /// [minSpeakers] - Minimum number of speakers to detect
  /// [maxSpeakers] - Maximum number of speakers to detect
  Future<DiarizationResult?> transcribeWithDiarization({
    required Uint8List audioBytes,
    required String languageCode,
    List<String>? alternativeLanguages,
    int minSpeakers = 2,
    int maxSpeakers = 6,
  }) async {
    if (!_isInitialized || _apiKey == null) {
      debugPrint('GoogleSttService: Not initialized');
      return null;
    }

    try {
      debugPrint('GoogleSttService: Starting transcription with diarization');
      debugPrint(
          'Language: $languageCode, Min Speakers: $minSpeakers, Max Speakers: $maxSpeakers');

      // Convert audio bytes to base64
      final String audioContent = base64Encode(audioBytes);

      // Prepare the request body for Google Speech-to-Text API
      final Map<String, dynamic> config = {
        'encoding': 'LINEAR16', // Adjust based on your audio format
        'sampleRateHertz': 16000, // Adjust based on your audio
        'languageCode': languageCode,
        'enableAutomaticPunctuation': true,
        'enableWordTimeOffsets': false,
        // 'diarizationConfig': {
        //   'enableSpeakerDiarization': true,
        //   'minSpeakerCount': minSpeakers,
        //   'maxSpeakerCount': maxSpeakers,
        // },
        'model': _getSupportedModel(
            languageCode), // Use appropriate model for language
      };

      // Add alternative languages if provided (for multi-language conversations)
      alternativeLanguages = ["en-US", "bn-IN"];

      if (alternativeLanguages != null && alternativeLanguages.isNotEmpty) {
        config['alternativeLanguageCodes'] = alternativeLanguages;
        debugPrint('GoogleSttService: Using multi-language detection');
        debugPrint(
            'Primary: $languageCode, Alternatives: $alternativeLanguages');
      }

      final Map<String, dynamic> requestBody = {
        'config': config,
        'audio': {
          'content': audioContent,
        },
      };

      print(
          "Calling Transcription with diarization: ${jsonEncode(requestBody)}");

      // Make the API request
      final response = await http.post(
        Uri.parse(
            'https://speech.googleapis.com/v1p1beta1/speech:recognize?key=$_apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      debugPrint('GoogleSttService: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print(data);
        debugPrint('GoogleSttService: Transcription successful');

        return _parseDiarizationResponse(data);
      } else {
        debugPrint('GoogleSttService: API error: ${response.statusCode}');
        debugPrint('GoogleSttService: Error body: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('GoogleSttService: Error during transcription: $e');
      return null;
    }
  }

  /// Get the appropriate model for the given language code
  String _getSupportedModel(String languageCode) {
    // For languages that support latest_long model
    final supportedLanguages = [
      'en-US',
      'en-GB',
      'en-AU',
      'en-CA',
      'en-IN',
      'es-ES',
      'es-MX',
      'es-AR',
      'es-CO',
      'es-PE',
      'fr-FR',
      'fr-CA',
      'de-DE',
      'it-IT',
      'pt-BR',
      'pt-PT',
      'ru-RU',
      'ja-JP',
      'ko-KR',
      'zh-CN',
      'zh-TW',
      'nl-NL',
      'sv-SE',
      'da-DK',
      'no-NO',
      'fi-FI',
      'pl-PL',
      'tr-TR',
      'ar-SA',
      'hi-IN'
    ];

    if (supportedLanguages.contains(languageCode)) {
      debugPrint('GoogleSttService: Using latest_long model for $languageCode');
      return 'latest_long';
    } else {
      debugPrint(
          'GoogleSttService: Using default model for $languageCode (latest_long not supported)');
      return 'default';
    }
  }

  /// Parse the Google STT API response to extract diarization information
  DiarizationResult _parseDiarizationResponse(Map<String, dynamic> response) {
    final List<DiarizedSegment> segments = [];
    String fullTranscript = '';

    try {
      final results = response['results'] as List?;
      if (results == null || results.isEmpty) {
        return DiarizationResult(
          segments: [],
          speakerCount: 0,
          fullTranscript: '',
        );
      }

      // Get the last result which contains the final transcript
      final lastResult = results.last as Map<String, dynamic>;
      final alternatives = lastResult['alternatives'] as List?;

      if (alternatives == null || alternatives.isEmpty) {
        return DiarizationResult(
          segments: [],
          speakerCount: 0,
          fullTranscript: '',
        );
      }

      final alternative = alternatives.first as Map<String, dynamic>;
      fullTranscript = alternative['transcript'] ?? '';

      // Extract words with speaker tags
      final words = alternative['words'] as List?;
      if (words != null && words.isNotEmpty) {
        // Group words by speaker
        int currentSpeaker = -1;
        String currentText = '';
        double currentStart = 0.0;
        double currentEnd = 0.0;
        double totalConfidence = 0.0;
        int wordCount = 0;

        debugPrint('GoogleSttService: Processing ${words.length} words');

        for (final word in words) {
          final wordMap = word as Map<String, dynamic>;
          // Google STT uses 1-based speaker tags, convert to 0-based (1 → 0, 2 → 1, etc.)
          final googleSpeakerTag = wordMap['speakerTag'] ?? 1;
          final speakerTag =
              googleSpeakerTag - 1; // Convert to 0-based indexing
          final wordText = wordMap['word'] ?? '';
          final startTime = _parseTime(wordMap['startTime']);
          final endTime = _parseTime(wordMap['endTime']);

          // Debug log first few words to see speaker assignment
          if (words.indexOf(word) < 5) {
            debugPrint(
                'GoogleSttService: Word "${wordText}" - Google tag: $googleSpeakerTag, Our tag: $speakerTag');
          }

          if (speakerTag != currentSpeaker && currentText.isNotEmpty) {
            // Save the current segment
            segments.add(DiarizedSegment(
              text: currentText.trim(),
              speakerTag: currentSpeaker,
              startTime: currentStart,
              endTime: currentEnd,
              confidence: wordCount > 0 ? totalConfidence / wordCount : 0.0,
            ));

            // Reset for new segment
            currentText = '';
            totalConfidence = 0.0;
            wordCount = 0;
          }

          // Update current segment
          if (currentText.isEmpty) {
            currentStart = startTime;
          }
          currentSpeaker = speakerTag;
          currentText += (currentText.isEmpty ? '' : ' ') + wordText;
          currentEnd = endTime;
          totalConfidence += (wordMap['confidence'] ?? 0.0).toDouble();
          wordCount++;
        }

        // Add the last segment
        if (currentText.isNotEmpty) {
          segments.add(DiarizedSegment(
            text: currentText.trim(),
            speakerTag: currentSpeaker,
            startTime: currentStart,
            endTime: currentEnd,
            confidence: wordCount > 0 ? totalConfidence / wordCount : 0.0,
          ));
        }
      }

      // Count unique speakers
      final uniqueSpeakers = segments.map((s) => s.speakerTag).toSet().length;

      debugPrint(
          'GoogleSttService: Parsed ${segments.length} segments from $uniqueSpeakers speakers');

      // Debug log each segment
      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        debugPrint(
            'GoogleSttService: Segment $i - Speaker ${seg.speakerTag}: "${seg.text.substring(0, seg.text.length > 50 ? 50 : seg.text.length)}..."');
      }

      return DiarizationResult(
        segments: segments,
        speakerCount: uniqueSpeakers,
        fullTranscript: fullTranscript,
      );
    } catch (e) {
      debugPrint('GoogleSttService: Error parsing response: $e');
      return DiarizationResult(
        segments: [],
        speakerCount: 0,
        fullTranscript: fullTranscript,
      );
    }
  }

  /// Parse time string to seconds
  double _parseTime(dynamic time) {
    if (time == null) return 0.0;
    if (time is num) return time.toDouble();

    // Parse time string like "1.234s"
    if (time is String) {
      final cleaned = time.replaceAll('s', '');
      return double.tryParse(cleaned) ?? 0.0;
    }

    return 0.0;
  }

  /// Check if the service is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Dispose the service
  void dispose() {
    _isInitialized = false;
    _apiKey = null;
    debugPrint('GoogleSttService: Disposed');
  }
}
