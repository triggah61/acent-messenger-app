import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';
import 'dart:typed_data';
import 'true_stereo_audio_service_robust.dart';

/// Enhanced TTS Service that supports true stereo audio generation
/// for separate earpiece playback (left and right channels)
/// Robust version with proper error handling for empty/corrupted files
class EnhancedTtsServiceRobust {
  static final EnhancedTtsServiceRobust _instance =
      EnhancedTtsServiceRobust._internal();
  factory EnhancedTtsServiceRobust() => _instance;
  EnhancedTtsServiceRobust._internal();

  FlutterTts? _flutterTts;
  AudioPlayer? _audioPlayer;
  TrueStereoAudioServiceRobust? _stereoAudioService;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentAudioPath;

  /// Initialize the enhanced TTS service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();
      _audioPlayer = AudioPlayer();
      _stereoAudioService = TrueStereoAudioServiceRobust();

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
        debugPrint('EnhancedTtsServiceRobust: TTS playback completed');
      });

      // Set up error handler
      _flutterTts!.setErrorHandler((message) {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceRobust: TTS error: $message');
      });

      // Set up audio player completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceRobust: Audio file playback completed');
      });

      _isInitialized = true;
      debugPrint('EnhancedTtsServiceRobust: Initialized successfully');
    } catch (e) {
      debugPrint('EnhancedTtsServiceRobust: Initialization error: $e');
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
      debugPrint('EnhancedTtsServiceRobust: Empty text provided');
      return null;
    }

    try {
      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint(
          'EnhancedTtsServiceRobust: Generating mono audio for language: $ttsLanguage');
      debugPrint('EnhancedTtsServiceRobust: Text: "$text"');

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
        // Verify the file was created and has content
        final file = File(audioPath);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint(
              'EnhancedTtsServiceRobust: Mono audio file generated successfully: $audioPath');
          debugPrint('EnhancedTtsServiceRobust: File size: $fileSize bytes');

          if (fileSize < 44) {
            debugPrint(
                'EnhancedTtsServiceRobust: Warning - Generated file is too small ($fileSize bytes)');
            // Don't return null, let the robust service handle it
          }

          return audioPath;
        } else {
          debugPrint('EnhancedTtsServiceRobust: File was not created');
          return null;
        }
      } else {
        debugPrint(
            'EnhancedTtsServiceRobust: Failed to generate mono audio file (result: $result)');
        return null;
      }
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceRobust: Error generating mono audio file: $e');
      return null;
    }
  }

  /// Generate and play true stereo audio file from two text inputs
  /// Left text will play on left channel, right text on right channel
  /// The longer audio determines the final length, shorter audio is padded with silence
  /// Handles empty/corrupted files gracefully
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
          'EnhancedTtsServiceRobust: Playing true stereo audio from text (robust handling)...');
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

      // Check if at least one audio file was generated successfully
      if (leftAudioPath == null && rightAudioPath == null) {
        debugPrint(
            'EnhancedTtsServiceRobust: Failed to generate any mono audio files');
        return false;
      }

      // If one file failed, create a dummy file for the robust service to handle
      final finalLeftPath =
          leftAudioPath ?? await _createDummyAudioFile('left');
      final finalRightPath =
          rightAudioPath ?? await _createDummyAudioFile('right');

      debugPrint('EnhancedTtsServiceRobust: Using audio files:');
      debugPrint('  Left: $finalLeftPath');
      debugPrint('  Right: $finalRightPath');

      // Create true stereo audio file with robust error handling
      final stereoAudioPath =
          await _stereoAudioService!.createTrueStereoAudioFile(
        finalLeftPath,
        finalRightPath,
        outputFileName:
            'true_stereo_robust_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      if (stereoAudioPath == null) {
        debugPrint(
            'EnhancedTtsServiceRobust: Failed to create true stereo audio file');
        return false;
      }

      // Play true stereo audio file
      await _stereoAudioService!.playStereoAudio(stereoAudioPath);

      _isPlaying = true;
      debugPrint(
          'EnhancedTtsServiceRobust: True stereo audio playing successfully (robust handling)');
      return true;
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceRobust: Error playing true stereo audio from text: $e');
      return false;
    }
  }

  /// Create a dummy audio file for cases where TTS generation fails
  /// This allows the robust service to handle the error gracefully
  Future<String> _createDummyAudioFile(String label) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final dummyPath = '${directory.path}/dummy_${label}_$timestamp.wav';

      // Create a minimal WAV file (just header, no audio data)
      final dummyWavBytes = _createMinimalWavFile();
      final file = File(dummyPath);
      await file.writeAsBytes(dummyWavBytes);

      debugPrint(
          'EnhancedTtsServiceRobust: Created dummy audio file: $dummyPath');
      return dummyPath;
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceRobust: Error creating dummy audio file: $e');
      // Return a non-existent path, the robust service will handle it
      return '/dummy/path/that/does/not/exist.wav';
    }
  }

  /// Create a minimal WAV file with just the header
  Uint8List _createMinimalWavFile() {
    // Create a minimal WAV header (44 bytes) with no audio data
    final header = <int>[
      // RIFF header
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      0x24, 0x00, 0x00, 0x00, // file size (36 bytes)
      0x57, 0x41, 0x56, 0x45, // "WAVE"

      // fmt chunk
      0x66, 0x6D, 0x74, 0x20, // "fmt "
      0x10, 0x00, 0x00, 0x00, // fmt chunk size (16)
      0x01, 0x00, // audio format (PCM)
      0x01, 0x00, // number of channels (1 = mono)
      0x40, 0x3E, 0x00, 0x00, // sample rate (16000)
      0x80, 0x7C, 0x00, 0x00, // byte rate (16000 * 1 * 2)
      0x02, 0x00, // block align (1 * 2)
      0x10, 0x00, // bits per sample (16)

      // data chunk
      0x64, 0x61, 0x74, 0x61, // "data"
      0x00, 0x00, 0x00, 0x00, // data size (0 bytes)
    ];

    return Uint8List.fromList(header);
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
      debugPrint('EnhancedTtsServiceRobust: Empty text provided');
      return;
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      // Map language code to TTS language
      final ttsLanguage = _mapLanguageToTtsCode(languageCode);
      debugPrint(
          'EnhancedTtsServiceRobust: Speaking text in language: $ttsLanguage');
      debugPrint('EnhancedTtsServiceRobust: Text: "$text"');

      // Set language for TTS
      await _flutterTts!.setLanguage(ttsLanguage);

      _isPlaying = true;
      await _flutterTts!.speak(text);
    } catch (e) {
      _isPlaying = false;
      debugPrint('EnhancedTtsServiceRobust: Error speaking text: $e');
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
      debugPrint('EnhancedTtsServiceRobust: TTS playback stopped');
    } catch (e) {
      debugPrint('EnhancedTtsServiceRobust: Error stopping TTS: $e');
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
      debugPrint('EnhancedTtsServiceRobust: Available languages: $languages');
      return languages.cast<String>();
    } catch (e) {
      debugPrint(
          'EnhancedTtsServiceRobust: Error getting available languages: $e');
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

  /// Create a true stereo WAV file from two mono audio files
  /// This method is exposed for direct use by the Google STT Translator
  Future<String?> createTrueStereoAudioFile(
    String leftAudioPath,
    String rightAudioPath, {
    String? outputFileName,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    return await _stereoAudioService!.createTrueStereoAudioFile(
      leftAudioPath,
      rightAudioPath,
      outputFileName: outputFileName,
    );
  }

  /// Play stereo audio file
  /// This method is exposed for direct use by the Google STT Translator
  Future<void> playStereoAudio(String stereoAudioPath) async {
    if (!_isInitialized) {
      await initialize();
    }

    await _stereoAudioService!.playStereoAudio(stereoAudioPath);
  }

  /// Stop stereo audio playback
  /// This method is exposed for direct use by the Google STT Translator
  Future<void> stopStereoAudio() async {
    if (!_isInitialized) return;

    await _stereoAudioService!.stop();
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
    debugPrint('EnhancedTtsServiceRobust: Disposed');
  }
}
