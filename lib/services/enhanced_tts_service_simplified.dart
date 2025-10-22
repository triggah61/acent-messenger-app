import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'simplified_stereo_audio_service.dart';

/// Enhanced TTS Service that supports stereo audio generation
/// for separate earpiece playback (left and right channels)
/// Uses simplified stereo approach without FFmpeg dependency
class EnhancedTtsServiceSimplified {
  static final EnhancedTtsServiceSimplified _instance =
      EnhancedTtsServiceSimplified._internal();
  factory EnhancedTtsServiceSimplified() => _instance;
  EnhancedTtsServiceSimplified._internal();

  FlutterTts? _flutterTts;
  AudioPlayer? _audioPlayer;
  SimplifiedStereoAudioService? _stereoAudioService;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentAudioPath;

  /// Initialize the enhanced TTS service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();
      _audioPlayer = AudioPlayer();
      _stereoAudioService = SimplifiedStereoAudioService();

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
        debugPrint('EnhancedTtsServiceSimplified: TTS playback completed');
      });

      // Set up error handler
      _flutterTts!.setErrorHandler((message) {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceSimplified: TTS error: $message');
      });

      // Set up audio player completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint(
            'EnhancedTtsServiceSimplified: Audio file playback completed');
      });

      _isInitialized = true;
      debugPrint('EnhancedTtsServiceSimplified: Initialized successfully');
    } catch (e) {
      debugPrint('EnhancedTtsServiceSimplified: Initialization error: $e');
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
      debugPrint('EnhancedTtsServiceSimplified: Empty text provided');
      return null;
    }

    try {
      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint(
          'EnhancedTtsServiceSimplified: Generating mono audio for language: $ttsLanguage');
      debugPrint('EnhancedTtsServiceSimplified: Text: "$text"');

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
            'EnhancedTtsServiceSimplified: Mono audio file generated successfully: $audioPath');
        return audioPath;
      } else {
        debugPrint(
            'EnhancedTtsServiceSimplified: Failed to generate mono audio file');
        return null;
      }
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceSimplified: Error generating mono audio file: $e');
      return null;
    }
  }

  /// Play stereo audio from two text inputs
  /// Left text will play on left channel, right text on right channel
  ///
  /// [leftText] - Text for left channel
  /// [rightText] - Text for right channel
  /// [leftLanguageCode] - Language code for left channel TTS
  /// [rightLanguageCode] - Language code for right channel TTS
  /// [leftVolume] - Volume level for left channel (0.0 to 1.0)
  /// [rightVolume] - Volume level for right channel (0.0 to 1.0)
  ///
  /// Returns true if stereo playback started successfully
  Future<bool> playStereoAudioFromText(
    String leftText,
    String rightText,
    String leftLanguageCode,
    String rightLanguageCode, {
    double leftVolume = 1.0,
    double rightVolume = 1.0,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint(
          'EnhancedTtsServiceSimplified: Playing stereo audio from text...');
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
            'EnhancedTtsServiceSimplified: Failed to generate mono audio files');
        return false;
      }

      // Play stereo audio using SimplifiedStereoAudioService
      final success = await _stereoAudioService!.playStereoAudio(
        leftAudioPath,
        rightAudioPath,
        leftVolume: leftVolume,
        rightVolume: rightVolume,
      );

      if (success) {
        debugPrint(
            'EnhancedTtsServiceSimplified: Stereo audio playback started successfully');
        _isPlaying = true;
      } else {
        debugPrint(
            'EnhancedTtsServiceSimplified: Failed to start stereo audio playback');
      }

      return success;
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceSimplified: Error playing stereo audio from text: $e');
      return false;
    }
  }

  /// Play stereo audio from existing audio files
  ///
  /// [leftAudioPath] - Path to the left channel audio file
  /// [rightAudioPath] - Path to the right channel audio file
  /// [leftVolume] - Volume level for left channel (0.0 to 1.0)
  /// [rightVolume] - Volume level for right channel (0.0 to 1.0)
  ///
  /// Returns true if stereo playback started successfully
  Future<bool> playStereoAudioFromFiles(
    String leftAudioPath,
    String rightAudioPath, {
    double leftVolume = 1.0,
    double rightVolume = 1.0,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint(
          'EnhancedTtsServiceSimplified: Playing stereo audio from files...');
      debugPrint('  Left audio: $leftAudioPath');
      debugPrint('  Right audio: $rightAudioPath');

      // Play stereo audio using SimplifiedStereoAudioService
      final success = await _stereoAudioService!.playStereoAudio(
        leftAudioPath,
        rightAudioPath,
        leftVolume: leftVolume,
        rightVolume: rightVolume,
      );

      if (success) {
        debugPrint(
            'EnhancedTtsServiceSimplified: Stereo audio playback started successfully');
        _isPlaying = true;
      } else {
        debugPrint(
            'EnhancedTtsServiceSimplified: Failed to start stereo audio playback');
      }

      return success;
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceSimplified: Error playing stereo audio from files: $e');
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
      debugPrint('EnhancedTtsServiceSimplified: Empty text provided');
      return;
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint(
          'EnhancedTtsServiceSimplified: Speaking text in language: $ttsLanguage');
      debugPrint('EnhancedTtsServiceSimplified: Text: "$text"');

      // Set language for TTS
      await _flutterTts!.setLanguage(ttsLanguage);

      _isPlaying = true;
      await _flutterTts!.speak(text);
    } catch (e) {
      _isPlaying = false;
      debugPrint('EnhancedTtsServiceSimplified: Error speaking text: $e');
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
      debugPrint('EnhancedTtsServiceSimplified: TTS playback stopped');
    } catch (e) {
      debugPrint('EnhancedTtsServiceSimplified: Error stopping TTS: $e');
    }
  }

  /// Pause current TTS playback
  Future<void> pause() async {
    if (!_isInitialized) return;

    try {
      await _stereoAudioService!.pause();
      debugPrint('EnhancedTtsServiceSimplified: TTS playback paused');
    } catch (e) {
      debugPrint('EnhancedTtsServiceSimplified: Error pausing TTS: $e');
    }
  }

  /// Resume current TTS playback
  Future<void> resume() async {
    if (!_isInitialized) return;

    try {
      await _stereoAudioService!.resume();
      debugPrint('EnhancedTtsServiceSimplified: TTS playback resumed');
    } catch (e) {
      debugPrint('EnhancedTtsServiceSimplified: Error resuming TTS: $e');
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
          'EnhancedTtsServiceSimplified: Available languages: $languages');
      return languages.cast<String>();
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceSimplified: Error getting available languages: $e');
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
    debugPrint('EnhancedTtsServiceSimplified: Disposed');
  }
}
