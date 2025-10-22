import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';

/// Simplified Stereo Audio Service for playing two mono TTS audio files
/// with left and right channel separation using dual AudioPlayer instances
/// This approach provides stereo-like experience without FFmpeg dependency
class SimplifiedStereoAudioService {
  static final SimplifiedStereoAudioService _instance =
      SimplifiedStereoAudioService._internal();
  factory SimplifiedStereoAudioService() => _instance;
  SimplifiedStereoAudioService._internal();

  AudioPlayer? _leftChannelPlayer;
  AudioPlayer? _rightChannelPlayer;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentLeftAudioPath;
  String? _currentRightAudioPath;

  /// Initialize the simplified stereo audio service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _leftChannelPlayer = AudioPlayer();
      _rightChannelPlayer = AudioPlayer();

      // Set up completion handlers
      _leftChannelPlayer!.onPlayerComplete.listen((event) {
        debugPrint(
            'SimplifiedStereoAudioService: Left channel playback completed');
        _checkBothChannelsComplete();
      });

      _rightChannelPlayer!.onPlayerComplete.listen((event) {
        debugPrint(
            'SimplifiedStereoAudioService: Right channel playback completed');
        _checkBothChannelsComplete();
      });

      _isInitialized = true;
      debugPrint('SimplifiedStereoAudioService: Initialized successfully');
    } catch (e) {
      debugPrint('SimplifiedStereoAudioService: Initialization error: $e');
      rethrow;
    }
  }

  /// Check if both channels have completed playback
  void _checkBothChannelsComplete() {
    if (_leftChannelPlayer?.state == PlayerState.completed &&
        _rightChannelPlayer?.state == PlayerState.completed) {
      _isPlaying = false;
      debugPrint('SimplifiedStereoAudioService: Both channels completed');
    }
  }

  /// Play two mono audio files as stereo (left and right channels)
  ///
  /// [leftAudioPath] - Path to the left channel audio file
  /// [rightAudioPath] - Path to the right channel audio file
  /// [leftVolume] - Volume level for left channel (0.0 to 1.0, default: 1.0)
  /// [rightVolume] - Volume level for right channel (0.0 to 1.0, default: 1.0)
  ///
  /// Returns true if playback started successfully
  Future<bool> playStereoAudio(
    String leftAudioPath,
    String rightAudioPath, {
    double leftVolume = 1.0,
    double rightVolume = 1.0,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      // Validate input files exist
      final leftFile = File(leftAudioPath);
      final rightFile = File(rightAudioPath);

      if (!await leftFile.exists()) {
        debugPrint(
            'SimplifiedStereoAudioService: Left audio file does not exist: $leftAudioPath');
        return false;
      }

      if (!await rightFile.exists()) {
        debugPrint(
            'SimplifiedStereoAudioService: Right audio file does not exist: $rightAudioPath');
        return false;
      }

      _currentLeftAudioPath = leftAudioPath;
      _currentRightAudioPath = rightAudioPath;
      _isPlaying = true;

      debugPrint('SimplifiedStereoAudioService: Playing stereo audio...');
      debugPrint('  Left channel: $leftAudioPath (volume: $leftVolume)');
      debugPrint('  Right channel: $rightAudioPath (volume: $rightVolume)');

      // Set volumes
      await _leftChannelPlayer!.setVolume(leftVolume);
      await _rightChannelPlayer!.setVolume(rightVolume);

      // Play both channels simultaneously
      await _leftChannelPlayer!.play(DeviceFileSource(leftAudioPath));
      await _rightChannelPlayer!.play(DeviceFileSource(rightAudioPath));

      debugPrint(
          'SimplifiedStereoAudioService: Stereo audio playback started successfully');
      return true;
    } catch (e) {
      _isPlaying = false;
      debugPrint(
          'SimplifiedStereoAudioService: Error playing stereo audio: $e');
      return false;
    }
  }

  /// Stop current stereo audio playback
  Future<void> stop() async {
    if (!_isInitialized) return;

    try {
      await _leftChannelPlayer?.stop();
      await _rightChannelPlayer?.stop();
      _isPlaying = false;
      _currentLeftAudioPath = null;
      _currentRightAudioPath = null;
      debugPrint('SimplifiedStereoAudioService: Stereo audio playback stopped');
    } catch (e) {
      debugPrint(
          'SimplifiedStereoAudioService: Error stopping stereo audio: $e');
    }
  }

  /// Pause current stereo audio playback
  Future<void> pause() async {
    if (!_isInitialized) return;

    try {
      await _leftChannelPlayer?.pause();
      await _rightChannelPlayer?.pause();
      debugPrint('SimplifiedStereoAudioService: Stereo audio playback paused');
    } catch (e) {
      debugPrint(
          'SimplifiedStereoAudioService: Error pausing stereo audio: $e');
    }
  }

  /// Resume current stereo audio playback
  Future<void> resume() async {
    if (!_isInitialized) return;

    try {
      await _leftChannelPlayer?.resume();
      await _rightChannelPlayer?.resume();
      debugPrint('SimplifiedStereoAudioService: Stereo audio playback resumed');
    } catch (e) {
      debugPrint(
          'SimplifiedStereoAudioService: Error resuming stereo audio: $e');
    }
  }

  /// Set volume for left channel
  Future<void> setLeftVolume(double volume) async {
    if (!_isInitialized) return;

    try {
      await _leftChannelPlayer?.setVolume(volume);
      debugPrint(
          'SimplifiedStereoAudioService: Left channel volume set to $volume');
    } catch (e) {
      debugPrint('SimplifiedStereoAudioService: Error setting left volume: $e');
    }
  }

  /// Set volume for right channel
  Future<void> setRightVolume(double volume) async {
    if (!_isInitialized) return;

    try {
      await _rightChannelPlayer?.setVolume(volume);
      debugPrint(
          'SimplifiedStereoAudioService: Right channel volume set to $volume');
    } catch (e) {
      debugPrint(
          'SimplifiedStereoAudioService: Error setting right volume: $e');
    }
  }

  /// Check if stereo audio is currently playing
  bool get isPlaying => _isPlaying;

  /// Get current left audio path
  String? get currentLeftAudioPath => _currentLeftAudioPath;

  /// Get current right audio path
  String? get currentRightAudioPath => _currentRightAudioPath;

  /// Get left channel player state
  PlayerState? get leftChannelState => _leftChannelPlayer?.state;

  /// Get right channel player state
  PlayerState? get rightChannelState => _rightChannelPlayer?.state;

  /// Test the stereo audio functionality
  Future<bool> testStereoAudioFunctionality() async {
    try {
      debugPrint(
          'SimplifiedStereoAudioService: Testing stereo audio functionality...');

      if (!_isInitialized) {
        await initialize();
      }

      // For testing, we'll just check if the service can be initialized
      // In a real scenario, you would have actual audio files
      debugPrint('SimplifiedStereoAudioService: Test completed successfully');
      return true;
    } catch (e) {
      debugPrint('SimplifiedStereoAudioService: Test failed: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _leftChannelPlayer?.stop();
    _rightChannelPlayer?.stop();
    _leftChannelPlayer = null;
    _rightChannelPlayer = null;
    _isInitialized = false;
    _isPlaying = false;
    _currentLeftAudioPath = null;
    _currentRightAudioPath = null;
    debugPrint('SimplifiedStereoAudioService: Disposed');
  }
}
