import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'stereo_audio_service.dart';

/// Enhanced TTS Service that supports stereo audio generation
/// for separate earpiece playback (left and right channels)
class EnhancedTtsService {
  static final EnhancedTtsService _instance = EnhancedTtsService._internal();
  factory EnhancedTtsService() => _instance;
  EnhancedTtsService._internal();

  FlutterTts? _flutterTts;
  AudioPlayer? _audioPlayer;
  StereoAudioService? _stereoAudioService;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentAudioPath;

  /// Initialize the enhanced TTS service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();
      _audioPlayer = AudioPlayer();
      _stereoAudioService = StereoAudioService();

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
        debugPrint('EnhancedTtsService: TTS playback completed');
      });

      // Set up error handler
      _flutterTts!.setErrorHandler((message) {
        _isPlaying = false;
        debugPrint('EnhancedTtsService: TTS error: $message');
      });

      // Set up audio player completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint('EnhancedTtsService: Audio file playback completed');
      });

      _isInitialized = true;
      debugPrint('EnhancedTtsService: Initialized successfully');
    } catch (e) {
      debugPrint('EnhancedTtsService: Initialization error: $e');
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
      debugPrint('EnhancedTtsService: Empty text provided');
      return null;
    }

    try {
      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint(
          'EnhancedTtsService: Generating mono audio for language: $ttsLanguage');
      debugPrint('EnhancedTtsService: Text: "$text"');

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
            'EnhancedTtsService: Mono audio file generated successfully: $audioPath');
        return audioPath;
      } else {
        debugPrint('EnhancedTtsService: Failed to generate mono audio file');
        return null;
      }
    } catch (e) {
      debugPrint('EnhancedTtsService: Error generating mono audio file: $e');
      return null;
    }
  }

  /// Generate stereo audio file from two text inputs
  /// Left text will play on left channel, right text on right channel
  ///
  /// [leftText] - Text for left channel
  /// [rightText] - Text for right channel
  /// [leftLanguageCode] - Language code for left channel TTS
  /// [rightLanguageCode] - Language code for right channel TTS
  /// [outputFileName] - Optional custom output filename
  /// [leftVolume] - Volume level for left channel (0.0 to 1.0)
  /// [rightVolume] - Volume level for right channel (0.0 to 1.0)
  ///
  /// Returns the path to the generated stereo audio file
  Future<String?> generateStereoAudioFile(
    String leftText,
    String rightText,
    String leftLanguageCode,
    String rightLanguageCode, {
    String? outputFileName,
    double leftVolume = 1.0,
    double rightVolume = 1.0,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      debugPrint('EnhancedTtsService: Generating stereo audio file...');
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
        debugPrint('EnhancedTtsService: Failed to generate mono audio files');
        return null;
      }

      // Create stereo audio file using StereoAudioService
      final stereoAudioPath =
          await _stereoAudioService!.createEnhancedStereoAudioFile(
        leftAudioPath,
        rightAudioPath,
        outputFileName: outputFileName,
        leftVolume: leftVolume,
        rightVolume: rightVolume,
      );

      // Clean up temporary mono files
      await _stereoAudioService!
          .cleanupTempFiles([leftAudioPath, rightAudioPath]);

      if (stereoAudioPath != null) {
        debugPrint(
            'EnhancedTtsService: Stereo audio file generated successfully: $stereoAudioPath');
      } else {
        debugPrint('EnhancedTtsService: Failed to create stereo audio file');
      }

      return stereoAudioPath;
    } catch (e) {
      debugPrint('EnhancedTtsService: Error generating stereo audio file: $e');
      return null;
    }
  }

  /// Play stereo audio file
  ///
  /// [stereoAudioPath] - Path to the stereo audio file
  Future<void> playStereoAudio(String stereoAudioPath) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      _currentAudioPath = stereoAudioPath;
      _isPlaying = true;

      debugPrint(
          'EnhancedTtsService: Playing stereo audio file: $stereoAudioPath');

      // Use AudioPlayer to play the stereo audio file
      await _audioPlayer!.play(DeviceFileSource(stereoAudioPath));
    } catch (e) {
      _isPlaying = false;
      debugPrint('EnhancedTtsService: Error playing stereo audio file: $e');
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
      debugPrint('EnhancedTtsService: Empty text provided');
      return;
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint('EnhancedTtsService: Speaking text in language: $ttsLanguage');
      debugPrint('EnhancedTtsService: Text: "$text"');

      // Set language for TTS
      await _flutterTts!.setLanguage(ttsLanguage);

      _isPlaying = true;
      await _flutterTts!.speak(text);
    } catch (e) {
      _isPlaying = false;
      debugPrint('EnhancedTtsService: Error speaking text: $e');
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
      debugPrint('EnhancedTtsService: TTS playback stopped');
    } catch (e) {
      debugPrint('EnhancedTtsService: Error stopping TTS: $e');
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
      debugPrint('EnhancedTtsService: Available languages: $languages');
      return languages.cast<String>();
    } catch (e) {
      debugPrint('EnhancedTtsService: Error getting available languages: $e');
      return ['en-US']; // Default fallback
    }
  }

  /// Test FFmpeg functionality
  Future<bool> testFFmpegFunctionality() async {
    if (!_isInitialized) {
      await initialize();
    }

    return await _stereoAudioService!.testFFmpegFunctionality();
  }

  /// Get FFmpeg version information
  Future<String?> getFFmpegVersion() async {
    if (!_isInitialized) {
      await initialize();
    }

    return await _stereoAudioService!.getFFmpegVersion();
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
    debugPrint('EnhancedTtsService: Disposed');
  }
}
