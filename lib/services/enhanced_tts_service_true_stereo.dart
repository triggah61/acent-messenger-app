import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'true_stereo_audio_service.dart';

/// Enhanced TTS Service that supports true stereo audio generation
/// for separate earpiece playback (left and right channels)
/// Uses true stereo WAV file creation for proper channel separation
class EnhancedTtsServiceTrueStereo {
  static final EnhancedTtsServiceTrueStereo _instance =
      EnhancedTtsServiceTrueStereo._internal();
  factory EnhancedTtsServiceTrueStereo() => _instance;
  EnhancedTtsServiceTrueStereo._internal();

  FlutterTts? _flutterTts;
  AudioPlayer? _audioPlayer;
  TrueStereoAudioService? _stereoAudioService;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentAudioPath;

  /// Initialize the enhanced TTS service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();
      _audioPlayer = AudioPlayer();
      _stereoAudioService = TrueStereoAudioService();

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
        debugPrint('EnhancedTtsServiceTrueStereo: TTS playback completed');
      });

      // Set up error handler
      _flutterTts!.setErrorHandler((message) {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceTrueStereo: TTS error: $message');
      });

      // Set up audio player completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint(
            'EnhancedTtsServiceTrueStereo: Audio file playback completed');
      });

      _isInitialized = true;
      debugPrint('EnhancedTtsServiceTrueStereo: Initialized successfully');
    } catch (e) {
      debugPrint('EnhancedTtsServiceTrueStereo: Initialization error: $e');
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
      debugPrint('EnhancedTtsServiceTrueStereo: Empty text provided');
      return null;
    }

    try {
      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint(
          'EnhancedTtsServiceTrueStereo: Generating mono audio for language: $ttsLanguage');
      debugPrint('EnhancedTtsServiceTrueStereo: Text: "$text"');

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
            'EnhancedTtsServiceTrueStereo: Mono audio file generated successfully: $audioPath');
        return audioPath;
      } else {
        debugPrint(
            'EnhancedTtsServiceTrueStereo: Failed to generate mono audio file');
        return null;
      }
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceTrueStereo: Error generating mono audio file: $e');
      return null;
    }
  }

  /// Generate and play true stereo audio file from two text inputs
  /// Left text will play on left channel, right text on right channel
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
          'EnhancedTtsServiceTrueStereo: Playing true stereo audio from text...');
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
            'EnhancedTtsServiceTrueStereo: Failed to generate mono audio files');
        return false;
      }

      // Create true stereo audio file
      final stereoAudioPath =
          await _stereoAudioService!.createTrueStereoAudioFile(
        leftAudioPath,
        rightAudioPath,
        outputFileName:
            'true_stereo_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      if (stereoAudioPath == null) {
        debugPrint(
            'EnhancedTtsServiceTrueStereo: Failed to create true stereo audio file');
        return false;
      }

      // Play true stereo audio file
      await _stereoAudioService!.playStereoAudio(stereoAudioPath);

      _isPlaying = true;
      debugPrint(
          'EnhancedTtsServiceTrueStereo: True stereo audio playing successfully');
      return true;
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceTrueStereo: Error playing true stereo audio from text: $e');
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
      debugPrint('EnhancedTtsServiceTrueStereo: Empty text provided');
      return;
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint(
          'EnhancedTtsServiceTrueStereo: Speaking text in language: $ttsLanguage');
      debugPrint('EnhancedTtsServiceTrueStereo: Text: "$text"');

      // Set language for TTS
      await _flutterTts!.setLanguage(ttsLanguage);

      _isPlaying = true;
      await _flutterTts!.speak(text);
    } catch (e) {
      _isPlaying = false;
      debugPrint('EnhancedTtsServiceTrueStereo: Error speaking text: $e');
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
      debugPrint('EnhancedTtsServiceTrueStereo: TTS playback stopped');
    } catch (e) {
      debugPrint('EnhancedTtsServiceTrueStereo: Error stopping TTS: $e');
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
      debugPrint(
          'EnhancedTtsServiceTrueStereo: Available languages: $languages');
      return languages.cast<String>();
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceTrueStereo: Error getting available languages: $e');
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
    debugPrint('EnhancedTtsServiceTrueStereo: Disposed');
  }
}
