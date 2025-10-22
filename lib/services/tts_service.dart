import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';

/// Text-to-Speech service for generating audio from translated text
class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  FlutterTts? _flutterTts;
  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentAudioPath;

  /// Initialize the TTS service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();
      _audioPlayer = AudioPlayer();

      // Set up TTS parameters
      await _flutterTts!.setLanguage("en-US");
      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.setVolume(1.0);
      await _flutterTts!.setPitch(1.0);

      // Set up completion handler
      _flutterTts!.setCompletionHandler(() {
        _isPlaying = false;
        debugPrint('TtsService: TTS playback completed');
      });

      // Set up error handler
      _flutterTts!.setErrorHandler((message) {
        _isPlaying = false;
        debugPrint('TtsService: TTS error: $message');
      });

      // Set up audio player completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint('TtsService: Audio file playback completed');
      });

      _isInitialized = true;
      debugPrint('TtsService: Initialized successfully');
    } catch (e) {
      debugPrint('TtsService: Initialization error: $e');
      rethrow;
    }
  }

  /// Generate audio file from text and return the file path
  Future<String?> generateAudioFile(String text, String languageCode) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (text.isEmpty) {
      debugPrint('TtsService: Empty text provided');
      return null;
    }

    try {
      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint('TtsService: Generating audio for language: $ttsLanguage');
      debugPrint('TtsService: Text: "$text"');

      // Set language for TTS
      await _flutterTts!.setLanguage(ttsLanguage);

      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'tts_${languageCode}_$timestamp.wav';

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final audioPath = '${directory.path}/$fileName';

      // Generate audio file
      final result = await _flutterTts!.synthesizeToFile(text, audioPath);

      if (result == 1) {
        debugPrint('TtsService: Audio file generated successfully: $audioPath');
        return audioPath;
      } else {
        debugPrint('TtsService: Failed to generate audio file');
        return null;
      }
    } catch (e) {
      debugPrint('TtsService: Error generating audio file: $e');
      return null;
    }
  }

  /// Play audio file
  Future<void> playAudioFile(String audioPath) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      // Check if file exists
      final file = File(audioPath);
      if (!await file.exists()) {
        debugPrint('TtsService: Audio file does not exist: $audioPath');
        return;
      }

      _currentAudioPath = audioPath;
      _isPlaying = true;

      debugPrint('TtsService: Playing audio file: $audioPath');

      // Use AudioPlayer to play the audio file
      await _audioPlayer!.play(DeviceFileSource(audioPath));
    } catch (e) {
      _isPlaying = false;
      debugPrint('TtsService: Error playing audio file: $e');
    }
  }

  /// Play text directly (without saving to file)
  Future<void> speak(String text, String languageCode) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (text.isEmpty) {
      debugPrint('TtsService: Empty text provided');
      return;
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint('TtsService: Speaking text in language: $ttsLanguage');
      debugPrint('TtsService: Text: "$text"');

      // Set language for TTS
      await _flutterTts!.setLanguage(ttsLanguage);

      _isPlaying = true;
      await _flutterTts!.speak(text);
    } catch (e) {
      _isPlaying = false;
      debugPrint('TtsService: Error speaking text: $e');
    }
  }

  /// Stop current TTS playback
  Future<void> stop() async {
    if (!_isInitialized) return;

    try {
      // Stop both TTS and audio player
      await _flutterTts!.stop();
      await _audioPlayer!.stop();
      _isPlaying = false;
      _currentAudioPath = null;
      debugPrint('TtsService: TTS playback stopped');
    } catch (e) {
      debugPrint('TtsService: Error stopping TTS: $e');
    }
  }

  /// Check if TTS is currently playing
  bool get isPlaying => _isPlaying;

  /// Get current audio path
  String? get currentAudioPath => _currentAudioPath;

  /// Map language code to TTS language code
  String _mapLanguageToTtsCode(String languageCode) {
    final Map<String, String> languageMap = {
      'en': 'en-US',
      'es': 'es-ES',
      'fr': 'fr-FR',
      'de': 'de-DE',
      'it': 'it-IT',
      'pt': 'pt-PT',
      'ru': 'ru-RU',
      'ja': 'ja-JP',
      'ko': 'ko-KR',
      'zh': 'zh-CN',
      'ar': 'ar-SA',
      'hi': 'hi-IN',
      'bn': 'bn-IN', // Bengali
      'ur': 'ur-PK', // Urdu
      'ms': 'ms-MY', // Malay
    };

    return languageMap[languageCode.toLowerCase()] ?? 'en-US';
  }

  /// Get available TTS languages
  Future<List<String>> getAvailableLanguages() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final languages = await _flutterTts!.getLanguages;
      debugPrint('TtsService: Available languages: $languages');
      return languages.cast<String>();
    } catch (e) {
      debugPrint('TtsService: Error getting available languages: $e');
      return ['en-US']; // Default fallback
    }
  }

  /// Dispose resources
  void dispose() {
    _flutterTts?.stop();
    _audioPlayer?.stop();
    _flutterTts = null;
    _audioPlayer = null;
    _isInitialized = false;
    _isPlaying = false;
    _currentAudioPath = null;
    debugPrint('TtsService: Disposed');
  }
}
