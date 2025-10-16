import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

/// Enumeration for audio channel selection
enum AudioChannel {
  left,
  right,
  stereo,
}

/// Audio player with channel-specific playback control
class ChannelAudioPlayer {
  final AudioPlayer _player = AudioPlayer();
  AudioChannel _currentChannel = AudioChannel.stereo;

  /// Play audio on a specific channel (left or right earbud only)
  Future<void> playOnChannel(String filePath, AudioChannel channel) async {
    try {
      debugPrint('ChannelAudioPlayer: Playing $filePath on $channel channel');

      _currentChannel = channel;

      // Stop any current playback
      await _player.stop();

      // Set balance based on channel
      // Balance: -1.0 (full left) to 1.0 (full right)
      double balance = 0.0;
      switch (channel) {
        case AudioChannel.left:
          balance = -1.0; // Full left
          break;
        case AudioChannel.right:
          balance = 1.0; // Full right
          break;
        case AudioChannel.stereo:
          balance = 0.0; // Center (both)
          break;
      }

      // Set the balance
      await _player.setBalance(balance);

      debugPrint('ChannelAudioPlayer: Set balance to $balance for $channel');

      // Play the audio file
      await _player.play(DeviceFileSource(filePath));

      debugPrint('ChannelAudioPlayer: Playback started on $channel channel');
    } catch (e) {
      debugPrint('ChannelAudioPlayer: Error playing audio: $e');
      rethrow;
    }
  }

  /// Stop playback
  Future<void> stop() async {
    await _player.stop();
  }

  /// Pause playback
  Future<void> pause() async {
    await _player.pause();
  }

  /// Resume playback
  Future<void> resume() async {
    await _player.resume();
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  /// Get current player state
  Future<PlayerState> getState() async {
    return _player.state;
  }

  /// Listen to player state changes
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  /// Listen to playback completion
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  /// Dispose the player
  void dispose() {
    _player.dispose();
  }
}
