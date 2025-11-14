import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:http/http.dart' as http;
import '../constants/config.dart';
import 'auth_service.dart';

/// Soniox token with translation metadata
class SonioxToken {
  final String text;
  final String translationStatus; // "none", "original", "translation"
  final String language;
  final String? sourceLanguage;
  final int? speaker; // Speaker ID from diarization
  final int? startMs;
  final int? endMs;
  final bool isFinal;

  SonioxToken({
    required this.text,
    required this.translationStatus,
    required this.language,
    this.sourceLanguage,
    this.speaker,
    this.startMs,
    this.endMs,
    this.isFinal = false,
  });

  factory SonioxToken.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse int from dynamic (handles both int and string)
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    return SonioxToken(
      text: json['text'] ?? '',
      translationStatus: json['translation_status'] ?? 'none',
      language: json['language'] ?? '',
      sourceLanguage: json['source_language'],
      speaker: parseInt(json['speaker']),
      startMs: parseInt(json['start_ms']),
      endMs: parseInt(json['end_ms']),
      isFinal: json['is_final'] ?? false,
    );
  }

  bool get isOriginal => translationStatus == 'original';
  bool get isTranslation => translationStatus == 'translation';
  bool get isNone => translationStatus == 'none';
}

/// Soniox real-time translation result
class SonioxResult {
  final List<SonioxToken> tokens;
  final bool isFinal;
  final int? speakerId;

  SonioxResult({
    required this.tokens,
    required this.isFinal,
    this.speakerId,
  });

  /// Get full text from tokens
  String getFullText() {
    return tokens.map((t) => t.text).join('');
  }

  /// Get original transcription
  String getOriginalText() {
    return tokens.where((t) => t.isOriginal).map((t) => t.text).join('');
  }

  /// Get translated text
  String getTranslatedText() {
    return tokens.where((t) => t.isTranslation).map((t) => t.text).join('');
  }
}

/// Service for Soniox real-time translation with WebSocket
/// Integrates speaker diarization, transcription, and translation in real-time
/// Documentation: https://soniox.com/docs/stt/rt/real-time-translation
class SonioxRealtimeService {
  static final SonioxRealtimeService _instance =
      SonioxRealtimeService._internal();
  factory SonioxRealtimeService() => _instance;
  SonioxRealtimeService._internal();

  final AuthService _authService = AuthService();

  WebSocketChannel? _channel;
  StreamController<SonioxResult>? _resultController;
  bool _isConnected = false;
  bool _isInitialized = false;

  // Configuration
  String? _apiKey;
  String? _languageA; // Speaker 1 language
  String? _languageB; // Speaker 2 language

  // Callbacks
  void Function(String error)? onError;
  void Function()? onConnected;
  void Function()? onDisconnected;

  /// Initialize service and fetch API key from backend
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('SonioxRealtimeService: Already initialized');
      return;
    }

    try {
      debugPrint('SonioxRealtimeService: ═══ Initializing Service ═══');

      // Fetch API key from backend
      _apiKey = await _fetchApiKey();

      if (_apiKey == null || _apiKey!.isEmpty) {
        throw Exception('Failed to fetch Soniox API key from backend');
      }

      _isInitialized = true;
      debugPrint('SonioxRealtimeService: ✅ Initialized successfully');
      debugPrint('SonioxRealtimeService: API key obtained from backend');
    } catch (e) {
      debugPrint('SonioxRealtimeService: ❌ Initialization error: $e');
      rethrow;
    }
  }

  /// Fetch Soniox API key from backend
  Future<String?> _fetchApiKey() async {
    try {
      debugPrint('SonioxRealtimeService: Fetching API key from backend...');

      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('SonioxRealtimeService: No auth token found');
        return null;
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/translation/soniox-config'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint(
          'SonioxRealtimeService: Backend response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final apiKey = data['data']?['apiKey'];

        if (apiKey != null && apiKey.isNotEmpty) {
          debugPrint('SonioxRealtimeService: ✅ API key fetched successfully');
          return apiKey as String;
        } else {
          debugPrint('SonioxRealtimeService: ❌ API key not found in response');
          return null;
        }
      } else {
        debugPrint(
            'SonioxRealtimeService: ❌ Failed to fetch API key: ${response.statusCode}');
        debugPrint('SonioxRealtimeService: Response body: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('SonioxRealtimeService: ❌ Error fetching API key: $e');
      return null;
    }
  }

  /// Connect to Soniox WebSocket for real-time translation
  Future<void> connect({
    required String languageA,
    required String languageB,
    bool enableSpeakerDiarization = true,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isConnected) {
      debugPrint('SonioxRealtimeService: Already connected');
      return;
    }

    try {
      debugPrint('SonioxRealtimeService: ═══ Connecting to WebSocket ═══');
      debugPrint('SonioxRealtimeService: Language A (Speaker 1): $languageA');
      debugPrint('SonioxRealtimeService: Language B (Speaker 2): $languageB');
      debugPrint(
          'SonioxRealtimeService: Speaker diarization: $enableSpeakerDiarization');

      _languageA = languageA;
      _languageB = languageB;

      // Create result stream controller
      _resultController = StreamController<SonioxResult>.broadcast();

      // CORRECT WebSocket URL (from Soniox documentation)
      final wsUrl = 'wss://stt-rt.soniox.com/transcribe-websocket';
      debugPrint('SonioxRealtimeService: Connecting to: $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Set up connection callback
      _channel!.ready.then((_) {
        debugPrint('SonioxRealtimeService: ✅ WebSocket connected');
        _isConnected = true;

        // Send configuration message immediately after connection
        _sendConfiguration(enableSpeakerDiarization);

        onConnected?.call();
        debugPrint(
            'SonioxRealtimeService: ✅ Connection ready for audio stream');
      }).catchError((error) {
        debugPrint('SonioxRealtimeService: ❌ Connection failed: $error');
        _isConnected = false;
        onError?.call('Connection failed: $error');
      });

      // Listen to WebSocket messages
      _channel!.stream.listen(
        _handleWebSocketMessage,
        onError: _handleWebSocketError,
        onDone: _handleWebSocketClosed,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('SonioxRealtimeService: ❌ Connection error: $e');
      _isConnected = false;
      onError?.call('Connection failed: $e');
      rethrow;
    }
  }

  /// Send configuration to Soniox
  Future<void> _sendConfiguration(bool enableSpeakerDiarization) async {
    try {
      debugPrint('SonioxRealtimeService: Sending configuration...');

      // Configuration for transcription + diarization only (NO TRANSLATION)
      // Translation will be handled by Azure API separately
      final config = {
        'api_key': _apiKey, // API key in first message
        'model': 'stt-rt-v3', // Real-time model
        'audio_format': 'pcm_s16le',
        'sample_rate': 16000,
        'num_channels': 1,
        'enable_endpoint_detection': true,
        'enable_speaker_diarization': enableSpeakerDiarization,
        'enable_language_identification': true,
        'language_hints': [_languageA, _languageB],
        // NO TRANSLATION - We'll use Azure API for translation

        'context': {
          'general': [
            {'key': "domain", 'value': "Healthcare"},
            {'key': "topic", 'value': "Diabetes management consultation"},
            {'key': "doctor", 'value': "Dr. Martha Smith"},
            {'key': "patient", 'value': "Mr. David Miller"},
            {'key': "organization", 'value': "St John's Hospital"},
          ],
          'text':
              "Mr. David Miller visited his healthcare provider last month for a routine follow-up related to diabetes care. The clinician reviewed his recent test results, noted improved glucose levels, and adjusted his medication schedule accordingly. They also discussed meal planning strategies and scheduled the next check-up for early spring.",
          'terms': [
            "Celebrex",
            "Zyrtec",
            "Xanax",
            "Prilosec",
            "Amoxicillin Clavulanate Potassium",
          ],
          'translation_terms': [
            {'source': "Mr. Smith", 'target': "Sr. Smith"},
            {'source': "St John's", 'target': "St John's"},
            {'source': "stroke", 'target': "ictus"},
          ],
        }
      };

      debugPrint('SonioxRealtimeService: Configuration: $config');

      debugPrint('SonioxRealtimeService: Configuration:');
      debugPrint('  Model: ${config['model']}');
      debugPrint('  Sample rate: ${config['sample_rate']} Hz');
      debugPrint('  Channels: ${config['num_channels']}');
      debugPrint('  Speaker diarization: $enableSpeakerDiarization');
      debugPrint('  Language hints: ${config['language_hints']}');
      debugPrint('  Translation: DISABLED (using Azure API instead)');

      // Send config as JSON string (first message)
      _channel!.sink.add(jsonEncode(config));
      debugPrint('SonioxRealtimeService: ✅ Configuration sent');
    } catch (e) {
      debugPrint('SonioxRealtimeService: ❌ Configuration error: $e');
      rethrow;
    }
  }

  /// Send audio data to Soniox
  /// According to Node.js sample, audio is sent as raw binary data (not base64 or JSON)
  Future<void> sendAudio(Uint8List audioBytes) async {
    if (!_isConnected || _channel == null) {
      debugPrint('SonioxRealtimeService: ⚠️ Cannot send audio - not connected');
      return;
    }

    try {
      // Send audio as raw bytes (matching Node.js sample: ws.send(chunk))
      _channel!.sink.add(audioBytes);

      debugPrint(
          'SonioxRealtimeService: 📤 Sent ${audioBytes.length} bytes of audio');
    } catch (e) {
      debugPrint('SonioxRealtimeService: ❌ Error sending audio: $e');
    }
  }

  /// Send audio finalization signal
  /// According to Node.js sample, send empty string to signal end-of-audio
  Future<void> finalizeAudio() async {
    if (!_isConnected || _channel == null) {
      debugPrint('SonioxRealtimeService: ⚠️ Cannot finalize - not connected');
      return;
    }

    try {
      debugPrint('SonioxRealtimeService: Sending finalization signal...');
      // Send empty string to signal end-of-audio (matching Node.js: ws.send(""))
      _channel!.sink.add('');
      debugPrint('SonioxRealtimeService: ✅ Finalization signal sent');
    } catch (e) {
      debugPrint('SonioxRealtimeService: ❌ Error finalizing: $e');
    }
  }

  /// Handle incoming WebSocket messages
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      debugPrint(
          'SonioxRealtimeService: 📥 Received message type: ${data.keys}');
      debugPrint('SonioxRealtimeService: 🔍 RAW RESPONSE: $message');

      // Handle error messages (from Node.js sample format)
      if (data.containsKey('error_code')) {
        final errorCode = data['error_code'];
        final errorMessage = data['error_message'] ?? 'Unknown error';
        debugPrint(
            'SonioxRealtimeService: ❌ Server error: $errorCode - $errorMessage');
        onError?.call('Server error: $errorCode - $errorMessage');
        return;
      }

      // Handle tokens (from Node.js sample format)
      if (data.containsKey('tokens')) {
        _handleResult(data);
      }

      // Handle session finished
      if (data.containsKey('finished') && data['finished'] == true) {
        debugPrint('SonioxRealtimeService: ✅ Session finished');
      }
    } catch (e) {
      debugPrint('SonioxRealtimeService: ❌ Error handling message: $e');
      debugPrint('SonioxRealtimeService: Stack trace: ${StackTrace.current}');
    }
  }

  /// Handle transcription/translation result
  void _handleResult(Map<String, dynamic> resultData) {
    try {
      final isFinal = resultData['is_final'] ?? false;

      // Safely parse speaker ID (might be int or string)
      int? speakerId;
      if (resultData['speaker'] != null) {
        if (resultData['speaker'] is int) {
          speakerId = resultData['speaker'];
        } else if (resultData['speaker'] is String) {
          speakerId = int.tryParse(resultData['speaker']);
        }
      }

      debugPrint('SonioxRealtimeService: ═══ Result Received ═══');
      debugPrint('SonioxRealtimeService: Final: $isFinal');
      debugPrint('SonioxRealtimeService: Speaker ID: $speakerId');

      // Parse tokens
      final tokensList = resultData['tokens'] as List?;
      if (tokensList == null || tokensList.isEmpty) {
        debugPrint('SonioxRealtimeService: No tokens in result');
        return;
      }

      debugPrint('SonioxRealtimeService: 🔍 Raw tokens data: $tokensList');

      final tokens = tokensList
          .map((t) => SonioxToken.fromJson(t as Map<String, dynamic>))
          .toList();

      debugPrint('SonioxRealtimeService: Received ${tokens.length} tokens');

      // Log token details
      for (var token in tokens) {
        debugPrint(
            'SonioxRealtimeService:   Token: "${token.text}" | Status: ${token.translationStatus} | Lang: ${token.language} | Speaker: ${token.speaker} | Final: ${token.isFinal}');
      }

      // Create result object
      final result = SonioxResult(
        tokens: tokens,
        isFinal: isFinal,
        speakerId: speakerId,
      );

      // Get text summaries
      final originalText = result.getOriginalText();
      final translatedText = result.getTranslatedText();

      if (originalText.isNotEmpty) {
        debugPrint(
            'SonioxRealtimeService: 🎤 Original: "$originalText" (${tokens.first.language})');
      }
      if (translatedText.isNotEmpty) {
        final translationLang =
            tokens.firstWhere((t) => t.isTranslation).language;
        debugPrint(
            'SonioxRealtimeService: 🌐 Translation: "$translatedText" ($translationLang)');
      }

      if (isFinal) {
        debugPrint(
            'SonioxRealtimeService: ✅ FINAL result - ready for TTS generation');
      }

      // Emit result to stream
      _resultController?.add(result);
    } catch (e) {
      debugPrint('SonioxRealtimeService: ❌ Error handling result: $e');
      debugPrint('SonioxRealtimeService: Stack trace: ${StackTrace.current}');
    }
  }

  /// Handle WebSocket errors
  void _handleWebSocketError(dynamic error) {
    debugPrint('SonioxRealtimeService: ❌ WebSocket error: $error');
    _isConnected = false;
    onError?.call('WebSocket error: $error');
  }

  /// Handle WebSocket closed
  void _handleWebSocketClosed() {
    debugPrint('SonioxRealtimeService: ⚠️ WebSocket connection closed');
    _isConnected = false;
    onDisconnected?.call();
  }

  /// Get stream of results
  Stream<SonioxResult>? get resultStream => _resultController?.stream;

  /// Check if service is connected
  bool get isConnected => _isConnected;

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    if (!_isConnected) {
      debugPrint('SonioxRealtimeService: Already disconnected');
      return;
    }

    try {
      debugPrint('SonioxRealtimeService: Disconnecting...');

      await _channel?.sink.close(status.goingAway);
      await _resultController?.close();

      _channel = null;
      _resultController = null;
      _isConnected = false;

      debugPrint('SonioxRealtimeService: ✅ Disconnected successfully');
    } catch (e) {
      debugPrint('SonioxRealtimeService: ❌ Disconnect error: $e');
    }
  }

  /// Dispose service resources
  Future<void> dispose() async {
    debugPrint('SonioxRealtimeService: Disposing...');
    await disconnect();
    _isInitialized = false;
    _apiKey = null;
    _languageA = null;
    _languageB = null;
    debugPrint('SonioxRealtimeService: ✅ Disposed');
  }
}
