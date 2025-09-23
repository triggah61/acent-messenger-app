import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

/// Service for handling speech-to-text functionality in voice mode
class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();

  static SpeechService get instance => _instance;

  // Speech to text instance
  late stt.SpeechToText _speechToText;

  // Service state
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isAvailable = false;

  // Speech recognition state
  String _lastWords = '';
  String _currentWords = '';
  double _confidence = 0.0;

  // Callbacks for speech events
  Function(String)? _onResult;
  Function(String)? _onPartialResult;
  Function(bool)? _onListeningStateChanged;
  Function(String)? _onError;
  Function(double)? _onSoundLevel;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  bool get isAvailable => _isAvailable;
  String get lastWords => _lastWords;
  String get currentWords => _currentWords;
  double get confidence => _confidence;

  /// Initialize the speech service
  Future<bool> initialize() async {
    try {
      debugPrint('SpeechService: Initializing...');

      _speechToText = stt.SpeechToText();

      // Initialize speech to text
      _isAvailable = await _speechToText.initialize(
        onError: (error) {
          debugPrint('SpeechService: Error occurred: $error');
          _onError?.call(error.errorMsg);
          _isListening = false;
          _onListeningStateChanged?.call(false);
        },
        onStatus: (status) {
          debugPrint('SpeechService: Status changed: $status');
          final isListening = status == 'listening';
          if (_isListening != isListening) {
            _isListening = isListening;
            _onListeningStateChanged?.call(_isListening);
          }
        },
      );

      if (_isAvailable) {
        _isInitialized = true;
        debugPrint('SpeechService: Initialization successful');

        // Get available locales
        final locales = await _speechToText.locales();
        debugPrint('SpeechService: Available locales: ${locales.length}');
        for (var locale in locales) {
          debugPrint('  - ${locale.name} (${locale.localeId})');
        }
      } else {
        debugPrint('SpeechService: Speech recognition not available');
      }

      return _isAvailable;
    } catch (e) {
      debugPrint('SpeechService: Initialization failed: $e');
      _isInitialized = false;
      _isAvailable = false;
      return false;
    }
  }

  /// Check and request microphone permission
  Future<bool> checkMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      debugPrint('SpeechService: Current microphone permission: $status');

      if (status.isGranted) {
        return true;
      }

      if (status.isDenied) {
        final result = await Permission.microphone.request();
        debugPrint('SpeechService: Permission request result: $result');
        return result.isGranted;
      }

      if (status.isPermanentlyDenied) {
        debugPrint('SpeechService: Microphone permission permanently denied');
        return false;
      }

      return false;
    } catch (e) {
      debugPrint('SpeechService: Error checking microphone permission: $e');
      return false;
    }
  }

  /// Start listening for speech
  Future<bool> startListening({
    String? localeId,
    Duration? pauseFor,
    Duration? listenFor,
  }) async {
    try {
      if (!_isInitialized || !_isAvailable) {
        debugPrint('SpeechService: Service not initialized or available');
        return false;
      }

      if (_isListening) {
        debugPrint('SpeechService: Already listening');
        return true;
      }

      // Check microphone permission
      final hasPermission = await checkMicrophonePermission();
      if (!hasPermission) {
        debugPrint('SpeechService: Microphone permission not granted');
        _onError?.call('Microphone permission not granted');
        return false;
      }

      debugPrint('SpeechService: Starting to listen...');

      // Clear previous results
      _currentWords = '';
      _lastWords = '';
      _confidence = 0.0;

      await _speechToText.listen(
        onResult: (result) {
          _currentWords = result.recognizedWords;
          _confidence = result.confidence;

          debugPrint(
              'SpeechService: Recognized: "${_currentWords}" (confidence: ${_confidence.toStringAsFixed(2)})');

          // Call partial result callback
          _onPartialResult?.call(_currentWords);

          // If result is final, update last words and call result callback
          if (result.finalResult) {
            _lastWords = _currentWords;
            _onResult?.call(_lastWords);
            debugPrint('SpeechService: Final result: "$_lastWords"');
          }
        },
        localeId: localeId,
        pauseFor: pauseFor ?? const Duration(seconds: 3),
        listenFor: listenFor ?? const Duration(seconds: 30),
        onSoundLevelChange: (level) {
          _onSoundLevel?.call(level);
        },
      );

      return true;
    } catch (e) {
      debugPrint('SpeechService: Error starting listening: $e');
      _onError?.call('Failed to start listening: $e');
      return false;
    }
  }

  /// Stop listening for speech
  Future<void> stopListening() async {
    try {
      if (!_isListening) {
        debugPrint('SpeechService: Not currently listening');
        return;
      }

      debugPrint('SpeechService: Stopping listening...');
      await _speechToText.stop();
      _isListening = false;
      _onListeningStateChanged?.call(false);
    } catch (e) {
      debugPrint('SpeechService: Error stopping listening: $e');
      _onError?.call('Failed to stop listening: $e');
    }
  }

  /// Cancel current listening session
  Future<void> cancelListening() async {
    try {
      if (!_isListening) {
        debugPrint('SpeechService: Not currently listening');
        return;
      }

      debugPrint('SpeechService: Cancelling listening...');
      await _speechToText.cancel();
      _isListening = false;
      _onListeningStateChanged?.call(false);
    } catch (e) {
      debugPrint('SpeechService: Error cancelling listening: $e');
      _onError?.call('Failed to cancel listening: $e');
    }
  }

  /// Get available locales for speech recognition
  Future<List<stt.LocaleName>> getAvailableLocales() async {
    try {
      if (!_isInitialized || !_isAvailable) {
        return [];
      }
      return await _speechToText.locales();
    } catch (e) {
      debugPrint('SpeechService: Error getting locales: $e');
      return [];
    }
  }

  /// Set callback for speech recognition results
  void setOnResult(Function(String) callback) {
    _onResult = callback;
  }

  /// Set callback for partial speech recognition results
  void setOnPartialResult(Function(String) callback) {
    _onPartialResult = callback;
  }

  /// Set callback for listening state changes
  void setOnListeningStateChanged(Function(bool) callback) {
    _onListeningStateChanged = callback;
  }

  /// Set callback for errors
  void setOnError(Function(String) callback) {
    _onError = callback;
  }

  /// Set callback for sound level changes
  void setOnSoundLevel(Function(double) callback) {
    _onSoundLevel = callback;
  }

  /// Clear all callbacks
  void clearCallbacks() {
    _onResult = null;
    _onPartialResult = null;
    _onListeningStateChanged = null;
    _onError = null;
    _onSoundLevel = null;
  }

  /// Get service status for debugging
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': _isInitialized,
      'isListening': _isListening,
      'isAvailable': _isAvailable,
      'lastWords': _lastWords,
      'currentWords': _currentWords,
      'confidence': _confidence,
    };
  }

  /// Dispose the service
  Future<void> dispose() async {
    try {
      if (_isListening) {
        await stopListening();
      }
      clearCallbacks();
      _isInitialized = false;
      debugPrint('SpeechService: Service disposed');
    } catch (e) {
      debugPrint('SpeechService: Error disposing service: $e');
    }
  }
}
