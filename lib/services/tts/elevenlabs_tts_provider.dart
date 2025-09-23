import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import '../audio_cache_service.dart';
import 'tts_provider.dart';

/// ElevenLabs Text-to-Speech provider implementation
class ElevenLabsTTSProvider implements TTSProvider {
  final String _apiKey;
  final String _baseUrl;
  late AudioPlayer _audioPlayer;
  bool _isInitialized = false;
  final AudioCacheService _cacheService = AudioCacheService.instance;

  // Default voice mappings for different languages
  static const Map<String, String> _defaultVoices = {
    'en': 'EXAVITQu4vr4xnSDxMaL', // Bella - English
    'es': 'MF3mGyEYCl7XYWbV9V6O', // Elli - Spanish
    'fr': 'TxGEqnHWrfWFTfGW9XjX', // Josh - French
    'de': 'ErXwobaYiN019PkySvjV', // Antoni - German
    'it': 'AZnzlk1XvdvUeBnXmlld', // Domi - Italian
    'pt': 'yoZ06aMxZJJ28mfd3POQ', // Sam - Portuguese
    'ru': 'bVMeCyTHy58xNoL34h3p', // Rachel - Russian
    'zh': 'onwK4e9ZLuTAKqWW03F9', // Grace - Chinese
    'ja': 'jsCqWAovK2LkecY7zXl4', // Daniel - Japanese
    'ko': 'jBpfuIE2acCO8z3wKNLl', // Lily - Korean
    'ar': 'flq6f7yk4E4fJM5XTYuZ', // Michael - Arabic
    'hi': 'piTKgcLEGmPE4e6mEKli', // Nicole - Hindi
    'ms': 'EXAVITQu4vr4xnSDxMaL', // Default to English voice
  };

  ElevenLabsTTSProvider({
    required String apiKey,
    required String baseUrl,
  })  : _apiKey = apiKey,
        _baseUrl = baseUrl;

  @override
  String get providerName => 'ElevenLabs';

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioPlayer = AudioPlayer();
      await _cacheService.initialize();
      _isInitialized = true;
      print('ElevenLabsTTSProvider: Initialized successfully');
    } catch (e) {
      print('ElevenLabsTTSProvider: Initialization failed: $e');
      throw Exception('Failed to initialize ElevenLabs TTS: $e');
    }
  }

  @override
  Future<String?> speak({
    required String text,
    required String languageCode,
    String? voiceId,
    double? speed,
    double? pitch,
  }) async {
    if (!_isInitialized) {
      throw Exception('TTS provider not initialized');
    }

    if (text.trim().isEmpty) {
      print('ElevenLabsTTSProvider: Empty text provided');
      return null;
    }

    try {
      // Use provided voice or default for language
      final selectedVoiceId =
          voiceId ?? _defaultVoices[languageCode] ?? _defaultVoices['en']!;

      print('ElevenLabsTTSProvider: Converting text to speech');
      print('Voice ID: $selectedVoiceId, Language: $languageCode');
      print(
          'Text: ${text.substring(0, text.length > 100 ? 100 : text.length)}...');

      // Stop any current playback
      await stop();

      // Check if audio is already cached
      final isCached = await _cacheService.isCached(text, languageCode,
          voiceId: selectedVoiceId);

      if (isCached) {
        // Use cached audio
        final cachedPath = await _cacheService
            .getCachedAudioPath(text, languageCode, voiceId: selectedVoiceId);
        if (cachedPath != null) {
          print('ElevenLabsTTSProvider: Using cached audio: $cachedPath');
          await _audioPlayer.play(DeviceFileSource(cachedPath));
          print('ElevenLabsTTSProvider: Cached audio playback started');
          return null;
        }
      }

      // Generate new speech audio if not cached
      print('ElevenLabsTTSProvider: Generating new audio (not cached)');
      final audioData = await _generateSpeech(
        text: text,
        voiceId: selectedVoiceId,
        speed: speed,
        pitch: pitch,
      );

      if (audioData != null) {
        // Cache the audio for future use
        await _cacheService.cacheAudio(text, languageCode, audioData,
            voiceId: selectedVoiceId);

        // Play audio directly
        await _audioPlayer.play(BytesSource(audioData));
        print('ElevenLabsTTSProvider: New audio playback started');
        return null; // Return null for direct playback
      } else {
        print('ElevenLabsTTSProvider: Failed to generate audio');
        return null;
      }
    } catch (e) {
      print('ElevenLabsTTSProvider: Error in speak: $e');
      throw Exception('TTS failed: $e');
    }
  }

  Future<Uint8List?> _generateSpeech({
    required String text,
    required String voiceId,
    double? speed,
    double? pitch,
  }) async {
    try {
      final url = '$_baseUrl/text-to-speech/$voiceId';

      final body = {
        'text': text,
        'model_id': 'eleven_multilingual_v2',
        'voice_settings': {
          'stability': 0.5,
          'similarity_boost': 0.75,
          'style': 0.0,
          'use_speaker_boost': true,
          if (speed != null) 'speed': speed.clamp(0.25, 4.0),
        }
      };

      print('ElevenLabsTTSProvider: Making API request to $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Accept': 'audio/mpeg',
          'Content-Type': 'application/json',
          'xi-api-key': _apiKey,
        },
        body: jsonEncode(body),
      );

      print(
          'ElevenLabsTTSProvider: API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        print(
            'ElevenLabsTTSProvider: Audio generated successfully (${response.bodyBytes.length} bytes)');
        return response.bodyBytes;
      } else {
        print('ElevenLabsTTSProvider: API error: ${response.statusCode}');
        print('Response body: ${response.body}');
        throw Exception(
            'ElevenLabs API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('ElevenLabsTTSProvider: Exception in _generateSpeech: $e');
      throw Exception('Failed to generate speech: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      print('ElevenLabsTTSProvider: Audio playback stopped');
    } catch (e) {
      print('ElevenLabsTTSProvider: Error stopping playback: $e');
    }
  }

  @override
  Future<List<TTSVoice>> getVoicesForLanguage(String languageCode) async {
    // Return default voices - can be extended to fetch from API
    final defaultVoiceId =
        _defaultVoices[languageCode] ?? _defaultVoices['en']!;

    return [
      TTSVoice(
        id: defaultVoiceId,
        name: _getVoiceNameForLanguage(languageCode),
        languageCode: languageCode,
        isDefault: true,
        description: 'Default voice for $languageCode',
      ),
    ];
  }

  String _getVoiceNameForLanguage(String languageCode) {
    const voiceNames = {
      'en': 'Bella',
      'es': 'Elli',
      'fr': 'Josh',
      'de': 'Antoni',
      'it': 'Domi',
      'pt': 'Sam',
      'ru': 'Rachel',
      'zh': 'Grace',
      'ja': 'Daniel',
      'ko': 'Lily',
      'ar': 'Michael',
      'hi': 'Nicole',
      'ms': 'Bella',
    };
    return voiceNames[languageCode] ?? 'Default Voice';
  }

  @override
  Future<bool> isAvailable() async {
    try {
      // Simple health check - try to get voices endpoint
      final response = await http.get(
        Uri.parse('$_baseUrl/voices'),
        headers: {
          'xi-api-key': _apiKey,
        },
      );

      final available = response.statusCode == 200;
      print('ElevenLabsTTSProvider: Availability check - $available');
      return available;
    } catch (e) {
      print('ElevenLabsTTSProvider: Availability check failed: $e');
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await stop();
      await _audioPlayer.dispose();
      await _cacheService.dispose();
      _isInitialized = false;
      print('ElevenLabsTTSProvider: Disposed successfully');
    } catch (e) {
      print('ElevenLabsTTSProvider: Error during disposal: $e');
    }
  }
}
