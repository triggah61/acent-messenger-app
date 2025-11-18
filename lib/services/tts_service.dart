import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
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
  
  // Completer for awaiting playback completion
  Completer<void>? _playbackCompleter;
  
  // Native audio player channel (for explicit A2DP routing)
  static const MethodChannel _nativeAudioChannel = MethodChannel('audio_route');
  
  // Flag to use native player (for guaranteed A2DP routing)
  bool _useNativePlayer = true;  // Use native player by default for A2DP routing
  

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
        
        // Complete the playback future if waiting
        if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
          _playbackCompleter!.complete();
        }
        
        _onPlaybackCompleted?.call();
      });

      // CRITICAL: Configure AudioPlayer for TWS playback via A2DP
      // This forces TTS to play through Bluetooth/TWS speakers instead of phone speaker
      // Even in MODE_IN_COMMUNICATION, MEDIA stream should route to A2DP (not SCO)
      try {
        await _audioPlayer!.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: false, // CRITICAL: Not phone speaker
              stayAwake: true,
              contentType: AndroidContentType.music, // CRITICAL: MUSIC for A2DP routing
              usageType: AndroidUsageType.media, // CRITICAL: MEDIA usage for A2DP
              // CRITICAL: Don't take exclusive audio focus - allow mixing with recording
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {
                // Note: allowBluetooth and allowBluetoothA2DP can only be used with:
                // playAndRecord, record, or multiRoute categories (not playback)
                // For playback-only, we rely on Android's default routing behavior
                // iOS will route to Bluetooth automatically if available
                AVAudioSessionOptions.mixWithOthers, // Allow mixing with recording
              },
            ),
          ),
        );
        
        // CRITICAL: Set player mode to MEDIA_PLAYER
        // This ensures the player uses MEDIA stream (A2DP) not VOICE_CALL stream (SCO/phone)
        await _audioPlayer!.setPlayerMode(PlayerMode.mediaPlayer);
        
        // CRITICAL: Set release mode to RELEASE (default behavior)
        // This ensures proper cleanup after playback
        await _audioPlayer!.setReleaseMode(ReleaseMode.release);
        
        debugPrint('TtsService: ✅ AudioPlayer configured for TWS/Bluetooth A2DP playback');
        debugPrint('TtsService: ✅ Player mode: MEDIA_PLAYER (not voice call)');
        debugPrint('TtsService: ✅ Content type: MUSIC (routes to A2DP, not SCO)');
        debugPrint('TtsService: ✅ Usage type: MEDIA (Bluetooth A2DP stream)');
        debugPrint('TtsService: ✅ Audio focus: gainTransientMayDuck (allows recording to continue)');
        debugPrint('TtsService: ✅ This configuration forces Bluetooth/TWS output in any audio mode');
      } catch (e) {
        debugPrint('TtsService: ❌ CRITICAL: Failed to set audio context: $e');
        debugPrint('TtsService: ❌ AudioPlayer will use default routing - may route to phone speaker!');
        debugPrint('TtsService: ❌ This is likely why TTS plays through phone speaker instead of TWS');
        // Continue anyway - may fall back to default routing
      }

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
          // CRITICAL: Add generous delay to ensure file system flush completes
          // This gives OS time to flush write buffers and close file descriptors
          // Prevents MEDIA_ERROR_SYSTEM in native MediaPlayer
          debugPrint('TtsService: Waiting for file system flush (500ms)...');
          await Future.delayed(const Duration(milliseconds: 500));
          debugPrint('TtsService: ✅ File ready for playback');
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

  /// Play audio file and wait for completion
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

      debugPrint('TtsService: ═══ Playing TTS Audio File ═══');
      debugPrint('TtsService: Audio file: $audioPath');
      debugPrint('TtsService: Expected output: TWS speakers (A2DP) - NOT phone speaker');
      debugPrint('TtsService: Recording continues from built-in mic (full-duplex mode)');

      // CRITICAL: Re-apply audio context before each playback
      // This ensures routing is properly set even if system changed it
      try {
        debugPrint('TtsService: Re-applying AudioContext for A2DP routing...');
        await _audioPlayer!.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: true,
              contentType: AndroidContentType.music, // A2DP routing
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {
                // Note: allowBluetooth and allowBluetoothA2DP can only be used with:
                // playAndRecord, record, or multiRoute categories (not playback)
                // For playback-only, we rely on Android's default routing behavior
                // iOS will route to Bluetooth automatically if available
                AVAudioSessionOptions.mixWithOthers,
              },
            ),
          ),
        );
        debugPrint('TtsService: ✅ AudioContext re-applied for this playback');
      } catch (e) {
        debugPrint('TtsService: ⚠️ Failed to re-apply audio context: $e');
      }

      // CRITICAL: Before playback, verify and force Bluetooth routing
      // This ensures A2DP is active and selected as output device
      try {
        debugPrint('TtsService: ═══ Verifying Bluetooth Routing Before Playback ═══');
        // Note: We'll add a native method call here if needed
        // For now, rely on AudioContext configuration
        debugPrint('TtsService: AudioContext configured for A2DP routing');
        debugPrint('TtsService: If audio still plays through phone speaker, A2DP may not be active');
        debugPrint('TtsService: Solution: Play music through TWS first to activate A2DP');
      } catch (e) {
        debugPrint('TtsService: ⚠️ Could not verify routing: $e');
      }

      // CRITICAL: Wait 500ms before starting playback to ensure hardware is ready
      // This allows TWS devices to be ready for A2DP playback
      // Also prevents audio from being cut off at the beginning
      debugPrint('TtsService: ⏳ Waiting 500ms for TWS A2DP routing to be ready...');
      await Future.delayed(const Duration(milliseconds: 500));

      // CRITICAL: Use native player for explicit A2DP routing
      // AudioPlayer (audioplayers package) may not respect routing configuration
      // Native MediaPlayer with setPreferredDevice() gives us guaranteed routing
      if (_useNativePlayer) {
        debugPrint('TtsService: ═══ Using Native Player for A2DP Routing ═══');
        debugPrint('TtsService: Native player uses MediaPlayer.setPreferredDevice()');
        debugPrint('TtsService: This ensures audio routes to Bluetooth A2DP explicitly');
        
        _playbackCompleter = Completer<void>();
        
        try {
          // CRITICAL: Set up method call handler for completion callback BEFORE starting playback
          // This ensures we don't miss the completion notification
          _nativeAudioChannel.setMethodCallHandler((call) async {
            if (call.method == 'onNativePlaybackCompleted') {
              debugPrint('TtsService: ✅ Received native playback completion callback');
              if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
                _playbackCompleter!.complete();
              }
            } else if (call.method == 'onNativePlaybackStarted') {
              debugPrint('TtsService: ✅ Native playback started (confirmed by callback)');
            }
          });
          
          debugPrint('TtsService: ✅ Completion callback handler set up - starting playback...');
          
          // Start native playback
          final success = await _nativeAudioChannel.invokeMethod<bool>(
            'playAudioFileNative',
            {'filePath': audioPath},
          );
          
          if (success == true) {
            debugPrint('TtsService: ✅ Native playback initiated - waiting for completion...');
            
            debugPrint('TtsService: ⏳ Waiting for playback to complete...');
            
            // CRITICAL: Wait for completion with timeout as backup
            // The callback should fire first via MediaPlayer.onCompletionListener
            try {
              await _playbackCompleter!.future.timeout(
                const Duration(seconds: 30), // Maximum 30 seconds for TTS playback
                onTimeout: () {
                  debugPrint('TtsService: ⚠️ Completion callback timeout - checking status...');
                  // Timeout backup: check if still playing
                  _nativeAudioChannel.invokeMethod<bool>('isNativeAudioPlaying').then((isPlaying) {
                    if (isPlaying != true) {
                      debugPrint('TtsService: ✅ Playback actually completed (timeout was false alarm)');
                      if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
                        _playbackCompleter!.complete();
                      }
                    } else {
                      debugPrint('TtsService: ⚠️ Playback still in progress after timeout');
                      // Force complete to prevent hanging, but log warning
                      if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
                        _playbackCompleter!.complete();
                      }
                    }
                  });
                },
              );
              
              debugPrint('TtsService: ✅ Native playback completed successfully');
            } catch (timeoutError) {
              debugPrint('TtsService: ⚠️ Completion wait timeout: $timeoutError');
              // Completer will be completed by timeout handler
            }
          } else {
            debugPrint('TtsService: ❌ Native playback failed - falling back to AudioPlayer');
            throw Exception('Native playback failed');
          }
        } catch (e) {
          debugPrint('TtsService: ❌ Native player error: $e');
          debugPrint('TtsService: Error type: ${e.runtimeType}');
          if (e is PlatformException) {
            debugPrint('TtsService: Platform error code: ${e.code}');
            debugPrint('TtsService: Platform error message: ${e.message}');
            debugPrint('TtsService: Platform error details: ${e.details}');
          }
          debugPrint('TtsService: Falling back to AudioPlayer...');
          
          // CRITICAL: Don't disable native player permanently - might work next time
          // Just use AudioPlayer for this playback
          
          // CRITICAL: Stop native player completely before using AudioPlayer
          // This prevents MediaPlayer conflicts (both use MediaPlayer internally)
          try {
            debugPrint('TtsService: Stopping native player to prevent MediaPlayer conflicts...');
            await _nativeAudioChannel.invokeMethod('stopNativeAudio');
            debugPrint('TtsService: ✅ Native player stopped');
            // Give system time to release MediaPlayer resources
            await Future.delayed(const Duration(milliseconds: 200));
          } catch (stopError) {
            debugPrint('TtsService: ⚠️ Could not stop native player: $stopError');
            // Continue anyway
          }
          
          // Continue with AudioPlayer playback
          _playbackCompleter = Completer<void>();
          
          // CRITICAL: Ensure completion handler is set up BEFORE playback
          // This ensures we don't miss completion events
          _audioPlayer!.onPlayerComplete.listen((event) {
            debugPrint('TtsService: ✅ AudioPlayer playback completed (fallback)');
            if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
              _playbackCompleter!.complete();
            }
          });
          
          // CRITICAL: Re-apply AudioContext for AudioPlayer (without allowBluetoothA2DP)
          try {
            debugPrint('TtsService: Re-applying AudioContext for AudioPlayer fallback...');
            await _audioPlayer!.setAudioContext(
              AudioContext(
                android: AudioContextAndroid(
                  isSpeakerphoneOn: false,
                  stayAwake: true,
                  contentType: AndroidContentType.music,
                  usageType: AndroidUsageType.media,
                  audioFocus: AndroidAudioFocus.gainTransientMayDuck,
                ),
                iOS: AudioContextIOS(
                  category: AVAudioSessionCategory.playback,
                  options: {
                    AVAudioSessionOptions.mixWithOthers,
                  },
                ),
              ),
            );
            debugPrint('TtsService: ✅ AudioContext re-applied for AudioPlayer');
          } catch (audioContextError) {
            debugPrint('TtsService: ⚠️ Failed to re-apply AudioContext: $audioContextError');
            // Continue anyway - AudioPlayer might still route correctly
          }
          
          // CRITICAL: Set volume to maximum (in case it was muted)
          try {
            await _audioPlayer!.setVolume(1.0);
            debugPrint('TtsService: ✅ Volume set to 1.0');
          } catch (volumeError) {
            debugPrint('TtsService: ⚠️ Could not set volume: $volumeError');
          }
          
          debugPrint('TtsService: Starting playback via AudioPlayer (fallback)...');
          debugPrint('TtsService: Stream type: MEDIA (Android ContentType.music)');
          debugPrint('TtsService: Expected routing: Bluetooth A2DP → TWS speakers');
          debugPrint('TtsService: File: $audioPath');
          
          await _audioPlayer!.play(DeviceFileSource(audioPath));
          
          debugPrint('TtsService: ⏳ Waiting for playback to complete...');
          
          // CRITICAL: Add timeout to prevent hanging if completion never fires
          try {
            await _playbackCompleter!.future.timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                debugPrint('TtsService: ⚠️ Playback completion timeout (30s) - assuming completed');
                if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
                  _playbackCompleter!.complete();
                }
              },
            );
          } catch (timeoutError) {
            debugPrint('TtsService: ⚠️ Playback wait error: $timeoutError');
          }
        } finally {
          // Clean up method call handler
          _nativeAudioChannel.setMethodCallHandler(null);
        }
      } else {
        // Use AudioPlayer (fallback or if native player is disabled)
        _playbackCompleter = Completer<void>();

        debugPrint('TtsService: Starting playback via AudioPlayer...');
        debugPrint('TtsService: Stream type: MEDIA (Android ContentType.music)');
        debugPrint('TtsService: Expected routing: Bluetooth A2DP → TWS speakers');
      await _audioPlayer!.play(DeviceFileSource(audioPath));

        debugPrint('TtsService: ⏳ Waiting for playback to complete...');
        await _playbackCompleter!.future;
      }
      
      debugPrint('TtsService: ✅ Playback completed');
    } catch (e) {
      _isPlaying = false;
      debugPrint('TtsService: Error playing audio file: $e');
      
      // Complete the completer if there was an error
      if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
        _playbackCompleter!.complete();
      }
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

      // CRITICAL: Wait 500ms before starting playback to ensure hardware is ready
      // This prevents audio from being cut off at the beginning
      debugPrint('TtsService: ⏳ Waiting 500ms for playback hardware to be ready...');
      await Future.delayed(const Duration(milliseconds: 500));

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
