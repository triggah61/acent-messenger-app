import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'true_stereo_audio_service_final.dart';

/// Enhanced TTS Service that supports true stereo audio generation
/// for separate earpiece playback (left and right channels)
/// Final version with proper audio length handling (no speech cutting)
class EnhancedTtsServiceFinal {
  static final EnhancedTtsServiceFinal _instance =
      EnhancedTtsServiceFinal._internal();
  factory EnhancedTtsServiceFinal() => _instance;
  EnhancedTtsServiceFinal._internal();

  FlutterTts? _flutterTts;
  AudioPlayer? _audioPlayer;
  TrueStereoAudioServiceFinal? _stereoAudioService;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentAudioPath;

  /// Initialize the enhanced TTS service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();
      _audioPlayer = AudioPlayer();
      _stereoAudioService = TrueStereoAudioServiceFinal();

      // Initialize stereo audio service
      await _stereoAudioService!.initialize();

      // Set up TTS parameters
      await _flutterTts!.setLanguage("en-US");
      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.setVolume(1.0);
      await _flutterTts!.setPitch(1.0);

      // Set up completion handler
      _flutterTts!.setCompletionHandler(() {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceFinal: TTS playback completed');
      });

      // Set up error handler
      _flutterTts!.setErrorHandler((message) {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceFinal: TTS error: $message');
      });

      // Set up audio player completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceFinal: Audio file playback completed');
      });

      _isInitialized = true;
      debugPrint('EnhancedTtsServiceFinal: Initialized successfully');
    } catch (e) {
      debugPrint('EnhancedTtsServiceFinal: Initialization error: $e');
      rethrow;
    }
  }

  /// Generate mono audio file from text and return the file path
  ///
  /// [text] - Text to convert to speech
  /// [languageCode] - Language code for TTS
  /// [fileName] - Optional custom filename
  ///
  /// Returns the path to the generated mono audio file
  Future<String?> generateMonoAudioFile(
    String text,
    String languageCode, {
    String? fileName,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (text.isEmpty) {
      debugPrint('EnhancedTtsServiceFinal: Empty text provided');
      return null;
    }

    try {
      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint(
          'EnhancedTtsServiceFinal: Generating mono audio for language: $ttsLanguage');
      debugPrint('EnhancedTtsServiceFinal: Text: "$text"');

      // Set language for TTS
      await _flutterTts!.setLanguage(ttsLanguage);

      // Generate unique filename if not provided
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalFileName = fileName ?? 'tts_${languageCode}_$timestamp.wav';

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final audioPath = '${directory.path}/$finalFileName';

      // Generate audio file
      final result = await _flutterTts!.synthesizeToFile(text, audioPath);

      if (result == 1) {
        debugPrint(
            'EnhancedTtsServiceFinal: Mono audio file generated successfully: $audioPath');
        return audioPath;
      } else {
        debugPrint(
            'EnhancedTtsServiceFinal: Failed to generate mono audio file');
        return null;
      }
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceFinal: Error generating mono audio file: $e');
      return null;
    }
  }

  /// Generate and play true stereo audio file from two text inputs
  /// Left text will play on left channel, right text on right channel
  /// The longer audio determines the final length, shorter audio is padded with silence
  /// This ensures no speech is cut off
  ///
  /// [leftText] - Text for left channel
  /// [rightText] - Text for right channel
  /// [leftLanguageCode] - Language code for left channel TTS
  /// [rightLanguageCode] - Language code for right channel TTS
  ///
  /// Returns true if stereo playback started successfully
  Future<bool> playStereoAudioFromText(
    String leftText,
    String rightText,
    String leftLanguageCode,
    String rightLanguageCode,
  ) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint(
          'EnhancedTtsServiceFinal: Playing true stereo audio from text (no cutting)...');
      debugPrint('  Left text: "$leftText" (language: $leftLanguageCode)');
      debugPrint('  Right text: "$rightText" (language: $rightLanguageCode)');

      // Generate mono audio files for both channels
      final leftAudioPath = await generateMonoAudioFile(
        leftText,
        leftLanguageCode,
        fileName: 'left_channel_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      final rightAudioPath = await generateMonoAudioFile(
        rightText,
        rightLanguageCode,
        fileName: 'right_channel_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      if (leftAudioPath == null || rightAudioPath == null) {
        debugPrint(
            'EnhancedTtsServiceFinal: Failed to generate mono audio files');
        return false;
      }

      // Create true stereo audio file with proper length handling (no cutting)
      final stereoAudioPath =
          await _stereoAudioService!.createTrueStereoAudioFile(
        leftAudioPath,
        rightAudioPath,
        outputFileName:
            'true_stereo_final_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      if (stereoAudioPath == null) {
        debugPrint(
            'EnhancedTtsServiceFinal: Failed to create true stereo audio file');
        return false;
      }

      // Play true stereo audio file
      await _stereoAudioService!.playStereoAudio(stereoAudioPath);

      _isPlaying = true;
      debugPrint(
          'EnhancedTtsServiceFinal: True stereo audio playing successfully (no speech cut)');
      return true;
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceFinal: Error playing true stereo audio from text: $e');
      return false;
    }
  }

  /// Play text directly (without saving to file)
  ///
  /// [text] - Text to speak
  /// [languageCode] - Language code for TTS
  Future<void> speak(String text, String languageCode) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (text.isEmpty) {
      debugPrint('EnhancedTtsServiceFinal: Empty text provided');
      return;
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint(
          'EnhancedTtsServiceFinal: Speaking text in language: $ttsLanguage');
      debugPrint('EnhancedTtsServiceFinal: Text: "$text"');

      // Set language for TTS
      await _flutterTts!.setLanguage(ttsLanguage);

      _isPlaying = true;
      await _flutterTts!.speak(text);
    } catch (e) {
      _isPlaying = false;
      debugPrint('EnhancedTtsServiceFinal: Error speaking text: $e');
    }
  }

  /// Stop current TTS playback
  Future<void> stop() async {
    if (!_isInitialized) return;

    try {
      // Stop both TTS and audio player
      await _flutterTts!.stop();
      await _audioPlayer!.stop();
      await _stereoAudioService!.stop();
      _isPlaying = false;
      _currentAudioPath = null;
      debugPrint('EnhancedTtsServiceFinal: TTS playback stopped');
    } catch (e) {
      debugPrint('EnhancedTtsServiceFinal: Error stopping TTS: $e');
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
      debugPrint('EnhancedTtsServiceFinal: Available languages: $languages');
      return languages.cast<String>();
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceFinal: Error getting available languages: $e');
      return ['en-US']; // Default fallback
    }
  }

  /// Test stereo audio functionality
  Future<bool> testStereoAudioFunctionality() async {
    if (!_isInitialized) {
      await initialize();
    }

    return await _stereoAudioService!.testStereoAudioFunctionality();
  }

  /// Dispose resources
  void dispose() {
    _flutterTts?.stop();
    _audioPlayer?.stop();
    _stereoAudioService?.dispose();
    _flutterTts = null;
    _audioPlayer = null;
    _stereoAudioService = null;
    _isInitialized = false;
    _isPlaying = false;
    _currentAudioPath = null;
    debugPrint('EnhancedTtsServiceFinal: Disposed');
  }
}
