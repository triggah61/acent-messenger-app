import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

/// Service for managing call ringtones like native phone calls
class CallRingtoneService {
  static CallRingtoneService? _instance;
  static CallRingtoneService get instance {
    _instance ??= CallRingtoneService._internal();
    return _instance!;
  }

  CallRingtoneService._internal();

  AudioPlayer? _ringtonePlayer;
  bool _isPlaying = false;
  Timer? _ringtoneTimer;
  Timer? _autoStopTimer;
  StreamSubscription? _playerStateSubscription;

  /// Initialize the ringtone service
  Future<void> initialize() async {
    try {
      _ringtonePlayer = AudioPlayer();
      await _ringtonePlayer!.setReleaseMode(ReleaseMode.stop);
      await _ringtonePlayer!
          .setVolume(0.8); // Moderate volume for call ringtone
      debugPrint('CallRingtoneService: Initialized successfully');
    } catch (e) {
      debugPrint('CallRingtoneService: Failed to initialize - $e');
    }
  }

  /// Start playing call ringtone (system-like behavior)
  Future<void> startRingtone() async {
    if (_isPlaying) return;

    try {
      debugPrint('CallRingtoneService: Starting call ringtone');
      _isPlaying = true;

      // Auto-stop after 30 seconds to match call timeout
      _autoStopTimer = Timer(const Duration(seconds: 30), () {
        debugPrint(
            'CallRingtoneService: Auto-stopping ringtone after 30 seconds');
        stopRingtone();
      });

      // Use system call ringtone behavior
      await _playSystemCallRingtone();
    } catch (e) {
      debugPrint('CallRingtoneService: Error starting ringtone - $e');
      _isPlaying = false;
    }
  }

  /// Stop the ringtone immediately
  Future<void> stopRingtone() async {
    if (!_isPlaying) return;

    try {
      debugPrint('CallRingtoneService: Stopping call ringtone');
      _isPlaying = false;

      // Cancel all timers
      _ringtoneTimer?.cancel();
      _ringtoneTimer = null;
      _autoStopTimer?.cancel();
      _autoStopTimer = null;

      // Cancel subscriptions
      _playerStateSubscription?.cancel();
      _playerStateSubscription = null;

      // Stop audio player
      if (_ringtonePlayer != null) {
        await _ringtonePlayer!.stop();
      }

      debugPrint('CallRingtoneService: Ringtone stopped successfully');
    } catch (e) {
      debugPrint('CallRingtoneService: Error stopping ringtone - $e');
    }
  }

  /// Play system call ringtone with realistic timing
  Future<void> _playSystemCallRingtone() async {
    if (!_isPlaying) return;

    try {
      if (Platform.isAndroid) {
        // Android: Use a pattern similar to phone call ringtone
        await _playAndroidCallRingtone();
      } else if (Platform.isIOS) {
        // iOS: Use system alert sound with call-like pattern
        await _playIOSCallRingtone();
      } else {
        // Other platforms: fallback to simple pattern
        await _playFallbackCallRingtone();
      }
    } catch (e) {
      debugPrint('CallRingtoneService: Error in system call ringtone - $e');
    }
  }

  /// Android call ringtone pattern
  Future<void> _playAndroidCallRingtone() async {
    // Play ringtone with realistic intervals (similar to phone calls)
    _ringtoneTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      try {
        // Vibrate first (like incoming call)
        HapticFeedback.heavyImpact();

        // Play system sound
        await SystemSound.play(SystemSoundType.alert);

        // Short delay then another sound burst for call effect
        Timer(const Duration(milliseconds: 500), () async {
          if (_isPlaying) {
            await SystemSound.play(SystemSoundType.alert);
          }
        });
      } catch (e) {
        debugPrint('CallRingtoneService: Error in Android ringtone cycle - $e');
      }
    });
  }

  /// iOS call ringtone pattern
  Future<void> _playIOSCallRingtone() async {
    // iOS pattern: longer intervals with distinct sound
    _ringtoneTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      try {
        // Vibrate pattern for incoming call
        HapticFeedback.heavyImpact();

        // Play system alert sound twice with delay
        await SystemSound.play(SystemSoundType.alert);

        Timer(const Duration(milliseconds: 300), () async {
          if (_isPlaying) {
            await SystemSound.play(SystemSoundType.alert);
          }
        });

        Timer(const Duration(milliseconds: 600), () async {
          if (_isPlaying) {
            await SystemSound.play(SystemSoundType.alert);
          }
        });
      } catch (e) {
        debugPrint('CallRingtoneService: Error in iOS ringtone cycle - $e');
      }
    });
  }

  /// Fallback call ringtone pattern
  Future<void> _playFallbackCallRingtone() async {
    _ringtoneTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }

      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (e) {
        debugPrint('CallRingtoneService: Error in fallback ringtone - $e');
      }
    });
  }

  /// Check if ringtone is currently playing
  bool get isPlaying => _isPlaying;

  /// Dispose the service
  Future<void> dispose() async {
    await stopRingtone();

    try {
      await _ringtonePlayer?.dispose();
      _ringtonePlayer = null;
      debugPrint('CallRingtoneService: Disposed successfully');
    } catch (e) {
      debugPrint('CallRingtoneService: Error during disposal - $e');
    }
  }

  /// Set ringtone volume (for future audio file support)
  Future<void> setVolume(double volume) async {
    try {
      await _ringtonePlayer?.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('CallRingtoneService: Error setting volume - $e');
    }
  }

  /// Pulse vibration for incoming call feel
  Future<void> pulseVibration() async {
    if (!_isPlaying) return;

    try {
      for (int i = 0; i < 3; i++) {
        if (!_isPlaying) break;
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (e) {
      debugPrint('CallRingtoneService: Error in pulse vibration - $e');
    }
  }
}
