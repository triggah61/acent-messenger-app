import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

class SoundNotificationService {
  static SoundNotificationService? _instance;
  
  // Audio player states
  bool _isMuted = false;
  double _volume = 1.0;
  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;
  
  // Audio file paths
  static const String _notificationSound = 'sounds/notification.wav';
  static const String _messageSound = 'sounds/notification.wav'; // Using same file for now
  static const String _callSound = 'sounds/notification.wav'; // Using same file for now
  
  // Singleton pattern
  static SoundNotificationService get instance {
    _instance ??= SoundNotificationService();
    return _instance!;
  }

  // Initialize sound service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setVolume(_volume);
      _isInitialized = true;
      debugPrint('SoundNotificationService: Initialized with custom audio player');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to initialize - $e');
      _audioPlayer = null;
      _isInitialized = false;
    }
  }

  // Play custom audio file with fallback to system sound
  Future<void> _playCustomSound(String audioPath, SystemSoundType fallbackSound) async {
    if (_isMuted) return;
    
    if (!_isInitialized || _audioPlayer == null) {
      await initialize();
    }
    
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.play(AssetSource(audioPath));
        debugPrint('SoundNotificationService: Played custom sound: $audioPath');
        return;
      }
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to play custom sound $audioPath - $e');
    }
    
    try {
      await SystemSound.play(fallbackSound);
      debugPrint('SoundNotificationService: Played fallback system sound');
    } catch (systemError) {
      debugPrint('SoundNotificationService: Failed to play system sound - $systemError');
    }
  }

  // Play new message sound
  Future<void> playNewMessageSound() async {
    await _playCustomSound(_messageSound, SystemSoundType.alert);
    debugPrint('SoundNotificationService: Played new message sound');
  }

  // Play general notification sound
  Future<void> playNotificationSound() async {
    await _playCustomSound(_notificationSound, SystemSoundType.click);
    debugPrint('SoundNotificationService: Played notification sound');
  }

  // Play incoming call sound (ringtone)
  Future<void> playIncomingCallSound() async {
    await _playCustomSound(_callSound, SystemSoundType.alert);
    debugPrint('SoundNotificationService: Played incoming call sound');
  }

  // Play typing sound
  Future<void> playTypingSound() async {
    if (_isMuted) return;
    
    try {
      // For typing, use a lighter system sound to avoid being annoying
      await SystemSound.play(SystemSoundType.click);
      debugPrint('SoundNotificationService: Played typing sound');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to play typing sound - $e');
    }
  }

  // Play sent message sound
  Future<void> playSentMessageSound() async {
    if (_isMuted) return;
    
    try {
      // For sent messages, use a subtle system sound
      await SystemSound.play(SystemSoundType.click);
      debugPrint('SoundNotificationService: Played sent message sound');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to play sent message sound - $e');
    }
  }

  // Play error sound
  Future<void> playErrorSound() async {
    if (_isMuted) return;
    
    try {
      await SystemSound.play(SystemSoundType.alert);
      debugPrint('SoundNotificationService: Played error sound');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to play error sound - $e');
    }
  }

  // Stop all sounds
  Future<void> stopAllSounds() async {
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.stop();
      }
      debugPrint('SoundNotificationService: Stopped all sounds');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to stop sounds - $e');
    }
  }

  // Mute/unmute sounds
  void setMuted(bool muted) {
    _isMuted = muted;
    debugPrint('SoundNotificationService: Muted = $muted');
  }

  // Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.setVolume(_volume);
      }
      debugPrint('SoundNotificationService: Volume set to $_volume');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to set volume - $e');
    }
  }

  // Get current settings
  bool get isMuted => _isMuted;
  double get volume => _volume;

  // Vibration feedback
  Future<void> vibrate() async {
    try {
      await HapticFeedback.mediumImpact();
      debugPrint('SoundNotificationService: Vibration triggered');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to vibrate - $e');
    }
  }

  // Light vibration for typing
  Future<void> lightVibrate() async {
    try {
      await HapticFeedback.lightImpact();
      debugPrint('SoundNotificationService: Light vibration triggered');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to light vibrate - $e');
    }
  }

  // Heavy vibration for calls
  Future<void> heavyVibrate() async {
    try {
      await HapticFeedback.heavyImpact();
      debugPrint('SoundNotificationService: Heavy vibration triggered');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to heavy vibrate - $e');
    }
  }

  // Dispose resources
  Future<void> dispose() async {
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.dispose();
        _audioPlayer = null;
      }
      _isInitialized = false;
      debugPrint('SoundNotificationService: Disposed audio player');
    } catch (e) {
      debugPrint('SoundNotificationService: Failed to dispose - $e');
    }
  }
} 