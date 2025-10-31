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
  bool _isTtsEngineReady = false;
  bool _isPlaying = false;
  String? _currentAudioPath;

  // Callbacks for UI state synchronization
  VoidCallback? _onPlaybackCompleted;
  VoidCallback? _onPlaybackError;

  /// Initialize the TTS service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('TtsService: Initializing TTS engine...');
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
        _onPlaybackCompleted?.call();
      });

      // Set up error handler
      _flutterTts!.setErrorHandler((message) {
        _isPlaying = false;
        debugPrint('TtsService: TTS error: $message');
        _onPlaybackError?.call();
      });

      // Set up audio player completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint('TtsService: Audio file playback completed');
        _onPlaybackCompleted?.call();
      });

      // CRITICAL: Wait for TTS engine to be ready
      // This is essential for Android - the engine needs time to initialize
      debugPrint('TtsService: Waiting for TTS engine to be ready...');
      await _waitForTtsEngine();

      _isInitialized = true;
      debugPrint('TtsService: ✅ Initialized successfully and engine is ready');
    } catch (e) {
      debugPrint('TtsService: ❌ Initialization error: $e');
      rethrow;
    }
  }

  /// Wait for TTS engine to be fully initialized
  Future<void> _waitForTtsEngine() async {
    int attempts = 0;
    const maxAttempts = 50; // 5 seconds timeout
    const checkInterval = Duration(milliseconds: 100);

    while (attempts < maxAttempts) {
      try {
        // Try to get voices - this will fail if engine not ready
        final voices = await _flutterTts!.getVoices;
        if (voices != null && voices.isNotEmpty) {
          _isTtsEngineReady = true;
          debugPrint('TtsService: ✅ TTS engine is ready (found ${voices.length} voices)');
          return;
        }
      } catch (e) {
        // Engine not ready yet, continue waiting
      }

      await Future.delayed(checkInterval);
      attempts++;

      if (attempts % 10 == 0) {
        debugPrint('TtsService: Still waiting for TTS engine... (attempt $attempts/$maxAttempts)');
      }
    }

    debugPrint('TtsService: ⚠️ TTS engine initialization timeout, but continuing anyway');
    _isTtsEngineReady = true; // Continue anyway
  }

  /// Set callback for playback completion
  void setPlaybackCompletedCallback(VoidCallback? callback) {
    _onPlaybackCompleted = callback;
  }

  /// Set callback for playback error
  void setPlaybackErrorCallback(VoidCallback? callback) {
    _onPlaybackError = callback;
  }

  /// Generate audio file from text and return the file path
  Future<String?> generateAudioFile(String text, String languageCode,
      {String? gender}) async {
    if (!_isInitialized) {
      debugPrint('TtsService: Not initialized, initializing now...');
      await initialize();
    }

    if (!_isTtsEngineReady) {
      debugPrint('TtsService: TTS engine not ready, waiting...');
      await _waitForTtsEngine();
    }

    if (text.isEmpty) {
      debugPrint('TtsService: Empty text provided');
      return null;
    }

    try {
      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint('TtsService: ═══ Generating TTS Audio ═══');
      debugPrint('TtsService: Language: $ttsLanguage');
      debugPrint('TtsService: Text: "$text"');
      debugPrint('TtsService: Gender: ${gender ?? 'default'}');
      debugPrint('TtsService: Engine ready: $_isTtsEngineReady');

      // Set language for TTS
      await _flutterTts!.setLanguage(ttsLanguage);
      debugPrint('TtsService: ✅ Language set to $ttsLanguage');

      // Set voice based on gender if specified
      if (gender != null) {
        await _setVoiceByGender(gender, ttsLanguage);
      }

      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'tts_${languageCode}_$timestamp.wav';

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final audioPath = '${directory.path}/$fileName';

      // Generate audio file
      final result = await _flutterTts!.synthesizeToFile(text, audioPath);

      if (result == 1) {
        debugPrint('TtsService: Audio file generation started: $audioPath');

        // Wait for the file to be completely written
        bool fileReady = false;
        int attempts = 0;
        const maxAttempts = 30; // 30 seconds timeout
        const checkInterval = Duration(milliseconds: 1000);

        while (!fileReady && attempts < maxAttempts) {
          await Future.delayed(checkInterval);
          attempts++;

          final file = File(audioPath);
          if (await file.exists()) {
            final fileSize = await file.length();
            debugPrint(
                'TtsService: File check attempt $attempts - Size: $fileSize bytes');

            if (fileSize > 0) {
              fileReady = true;
              debugPrint(
                  'TtsService: Audio file generated successfully: $audioPath (Size: $fileSize bytes)');
            }
          } else {
            debugPrint(
                'TtsService: File check attempt $attempts - File does not exist yet');
          }
        }

        if (fileReady) {
          return audioPath;
        } else {
          debugPrint(
              'TtsService: Audio file generation timeout after $maxAttempts attempts');
          return null;
        }
      } else {
        debugPrint('TtsService: Failed to start audio file generation');
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

  /// Set voice based on gender preference
  Future<void> _setVoiceByGender(String gender, String ttsLanguage) async {
    try {
      // Get available voices for the language
      final voices = await _flutterTts!.getVoices;

      if (voices != null && voices.isNotEmpty) {
        // Filter voices by language
        final languageVoices = voices
            .where((voice) =>
                voice['locale'] != null &&
                voice['locale']
                    .toString()
                    .startsWith(ttsLanguage.split('-')[0]))
            .toList();

        if (languageVoices.isNotEmpty) {
          // Try to find a voice that matches the gender preference
          String? selectedVoice;

          if (gender.toLowerCase() == 'female') {
            // Look for female voices (common patterns: female, woman, etc.)
            selectedVoice = languageVoices.firstWhere(
              (voice) {
                final name = voice['name']?.toString().toLowerCase() ?? '';
                return name.contains('female') ||
                    name.contains('woman') ||
                    name.contains('f') ||
                    name.contains('samantha') ||
                    name.contains('susan') ||
                    name.contains('karen');
              },
              orElse: () => languageVoices.first,
            )['name']?.toString();
          } else if (gender.toLowerCase() == 'male') {
            // Look for male voices (common patterns: male, man, etc.)
            selectedVoice = languageVoices.firstWhere(
              (voice) {
                final name = voice['name']?.toString().toLowerCase() ?? '';
                return name.contains('male') ||
                    name.contains('man') ||
                    name.contains('m') ||
                    name.contains('alex') ||
                    name.contains('daniel') ||
                    name.contains('david');
              },
              orElse: () => languageVoices.first,
            )['name']?.toString();
          }

          if (selectedVoice != null) {
            await _flutterTts!
                .setVoice({'name': selectedVoice, 'locale': ttsLanguage});
            debugPrint(
                'TtsService: Set voice to: $selectedVoice for gender: $gender');
          } else {
            debugPrint(
                'TtsService: No suitable voice found for gender: $gender, using default');
          }
        } else {
          debugPrint(
              'TtsService: No voices available for language: $ttsLanguage');
        }
      } else {
        debugPrint('TtsService: No voices available on this device');
      }
    } catch (e) {
      debugPrint('TtsService: Error setting voice by gender: $e');
    }
  }

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
