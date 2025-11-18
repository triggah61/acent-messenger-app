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

  // Callbacks for UI state synchronization
  VoidCallback? _onPlaybackCompleted;
  VoidCallback? _onPlaybackError;

  /// Initialize the enhanced TTS service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();
      _audioPlayer = AudioPlayer();
      _stereoAudioService = TrueStereoAudioServiceRobust();

      // Initialize stereo audio service
      await _stereoAudioService!.initialize();

      // Set up stereo audio service callbacks
      _stereoAudioService!.setPlaybackCompletedCallback(() {
        _isPlaying = false;
        debugPrint(
            'EnhancedTtsServiceRobust: Stereo audio playback completed - forwarding callback');
        _onPlaybackCompleted?.call();
      });

      _stereoAudioService!.setPlaybackErrorCallback(() {
        _isPlaying = false;
        debugPrint(
            'EnhancedTtsServiceRobust: Stereo audio playback error - forwarding callback');
        _onPlaybackError?.call();
      });

      // Set up TTS parameters
      await _flutterTts!.setLanguage("en-US");
      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.setVolume(1.0);
      await _flutterTts!.setPitch(1.0);

      // Set up completion handler
      _flutterTts!.setCompletionHandler(() {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceRobust: TTS playback completed');
        _onPlaybackCompleted?.call();
      });

      // Set up error handler
      _flutterTts!.setErrorHandler((message) {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceRobust: TTS error: $message');
        _onPlaybackError?.call();
      });

      // Set up audio player completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint('EnhancedTtsServiceRobust: Audio file playback completed');
        _onPlaybackCompleted?.call();
      });

      _isInitialized = true;
      debugPrint('EnhancedTtsServiceRobust: Initialized successfully');
    } catch (e) {
      debugPrint('EnhancedTtsServiceRobust: Initialization error: $e');
      rethrow;
    }
  }

  /// Set callback for playback completion
  void setPlaybackCompletedCallback(VoidCallback? callback) {
    _onPlaybackCompleted = callback;
  }

  /// Set callback for playback error
  void setPlaybackErrorCallback(VoidCallback? callback) {
    _onPlaybackError = callback;
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
    String? gender,
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

      // Set voice based on gender if specified
      if (gender != null) {
        await _setVoiceByGender(gender, ttsLanguage);
      }

      // Generate unique filename if not provided
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalFileName = fileName ?? 'tts_${languageCode}_$timestamp.wav';

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final audioPath = '${directory.path}/$finalFileName';

      // Generate audio file
      final result = await _flutterTts!.synthesizeToFile(text, audioPath);

      if (result == 1) {
        debugPrint('EnhancedTtsServiceRobust: Audio file generation started: $audioPath');

        // CRITICAL FIX: Wait for the file to be completely written
        // synthesizeToFile() returns immediately after starting, but file writing happens asynchronously
        // We must poll until the file has actual content (> 44 bytes for WAV header + data)
        bool fileReady = false;
        int attempts = 0;
        const maxAttempts = 30; // 30 seconds timeout (should complete in 1-3 seconds)
        const checkInterval = Duration(milliseconds: 100); // Check every 100ms

        while (!fileReady && attempts < maxAttempts) {
          await Future.delayed(checkInterval);
          attempts++;

          final file = File(audioPath);
          if (await file.exists()) {
            final fileSize = await file.length();
            debugPrint(
                'EnhancedTtsServiceRobust: File check attempt $attempts - Size: $fileSize bytes');

            // File must have at least 44 bytes (WAV header) plus some audio data
            // A typical TTS file for a short sentence is 10-50KB
            if (fileSize > 44) {
              // CRITICAL: Verify the file is a valid WAV file by checking header
              try {
                final fileBytes = await file.readAsBytes();
                if (fileBytes.length >= 44) {
                  // Check for RIFF header
                  final riffHeader = String.fromCharCodes(fileBytes.sublist(0, 4));
                  final waveHeader = fileBytes.length >= 12 
                      ? String.fromCharCodes(fileBytes.sublist(8, 12))
                      : '';
                  
                  if (riffHeader == 'RIFF' && waveHeader == 'WAVE') {
                    // Valid WAV file - ensure it's fully written by checking file size stability
                    // Wait a bit more to ensure file is completely flushed
                    await Future.delayed(const Duration(milliseconds: 100));
                    
                    // Re-check file size to ensure it didn't change (file is stable)
                    final stableSize = await file.length();
                    if (stableSize == fileSize && stableSize > 44) {
                      fileReady = true;
                      debugPrint(
                          'EnhancedTtsServiceRobust: ✅ Mono audio file generated successfully: $audioPath');
                      debugPrint('EnhancedTtsServiceRobust: Final file size: $stableSize bytes');
                      debugPrint('EnhancedTtsServiceRobust: ✅ Valid WAV file (RIFF/WAVE headers confirmed)');
                      return audioPath;
                    } else {
                      debugPrint(
                          'EnhancedTtsServiceRobust: File size changed ($fileSize → $stableSize), waiting for stability...');
                    }
                  } else {
                    debugPrint(
                        'EnhancedTtsServiceRobust: Invalid WAV header (RIFF=$riffHeader, WAVE=$waveHeader), waiting...');
                  }
                }
              } catch (e) {
                debugPrint('EnhancedTtsServiceRobust: Error validating WAV file: $e');
                // Continue waiting
              }
            }
          } else {
            debugPrint(
                'EnhancedTtsServiceRobust: File check attempt $attempts - File does not exist yet');
          }

          // Log progress every 10 attempts (1 second)
          if (attempts % 10 == 0) {
            debugPrint(
                'EnhancedTtsServiceRobust: Still waiting for TTS file to be written... (attempt $attempts/$maxAttempts)');
          }
        }

        // Timeout - file didn't get written
        debugPrint(
            'EnhancedTtsServiceRobust: ❌ Audio file generation timeout after $maxAttempts attempts');
        debugPrint('EnhancedTtsServiceRobust: File path: $audioPath');
        
        // Check final file size
        final file = File(audioPath);
        if (await file.exists()) {
          final finalSize = await file.length();
          debugPrint('EnhancedTtsServiceRobust: Final file size at timeout: $finalSize bytes');
          if (finalSize > 44) {
            // File was written but we didn't catch it - return it anyway
            debugPrint('EnhancedTtsServiceRobust: ✅ File has content, returning path');
            return audioPath;
          }
        }
        
        return null;
      } else {
        debugPrint(
            'EnhancedTtsServiceRobust: ❌ Failed to generate mono audio file (result: $result)');
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
    String rightLanguageCode, {
    String? leftGender,
    String? rightGender,
  }) async {
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
        gender: leftGender,
      );

      final rightAudioPath = await generateMonoAudioFile(
        rightText,
        rightLanguageCode,
        fileName: 'right_channel_${DateTime.now().millisecondsSinceEpoch}.wav',
        gender: rightGender,
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

    _isPlaying = true;
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
                'EnhancedTtsServiceRobust: Set voice to: $selectedVoice for gender: $gender');
          } else {
            debugPrint(
                'EnhancedTtsServiceRobust: No suitable voice found for gender: $gender, using default');
          }
        } else {
          debugPrint(
              'EnhancedTtsServiceRobust: No voices available for language: $ttsLanguage');
        }
      } else {
        debugPrint(
            'EnhancedTtsServiceRobust: No voices available on this device');
      }
    } catch (e) {
      debugPrint('EnhancedTtsServiceRobust: Error setting voice by gender: $e');
    }
  }
}
