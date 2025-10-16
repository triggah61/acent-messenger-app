import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Enumeration for audio profiles
enum AudioProfile {
  phoneMicBluetoothSpeaker, // Speaker 1: Phone mic → TWS speaker
  bluetoothMicPhoneSpeaker, // Speaker 2: TWS mic → Phone speaker
}

/// Service for managing alternating audio profiles between phone and Bluetooth
class AudioProfileService {
  static final AudioProfileService _instance = AudioProfileService._internal();
  factory AudioProfileService() => _instance;
  AudioProfileService._internal();

  static const MethodChannel _channel = MethodChannel('audio_profile_service');

  AudioProfile _currentProfile = AudioProfile.phoneMicBluetoothSpeaker;
  bool _isInitialized = false;

  /// Initialize the audio profile service
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      debugPrint('AudioProfileService: Initializing...');

      // Request necessary permissions and setup
      final result = await _channel.invokeMethod('initializeAudioProfiles');

      if (result == true) {
        _isInitialized = true;
        debugPrint('AudioProfileService: Initialized successfully');
        return true;
      } else {
        debugPrint('AudioProfileService: Initialization failed');
        return false;
      }
    } catch (e) {
      debugPrint('AudioProfileService: Initialization error: $e');
      return false;
    }
  }

  /// Switch to Profile A: Phone Mic → Bluetooth Speaker
  Future<bool> switchToPhoneMicBluetoothSpeaker() async {
    try {
      debugPrint(
          'AudioProfileService: Switching to Phone Mic → Bluetooth Speaker');

      final result = await _channel.invokeMethod(
          'setAudioProfile', {'profile': 'phoneMicBluetoothSpeaker'});

      if (result == true) {
        _currentProfile = AudioProfile.phoneMicBluetoothSpeaker;
        debugPrint(
            'AudioProfileService: Switched to Phone Mic → Bluetooth Speaker');
        return true;
      } else {
        debugPrint(
            'AudioProfileService: Failed to switch to Phone Mic → Bluetooth Speaker');
        return false;
      }
    } catch (e) {
      debugPrint(
          'AudioProfileService: Error switching to Phone Mic → Bluetooth Speaker: $e');
      return false;
    }
  }

  /// Switch to Profile B: Bluetooth Mic → Phone Speaker
  Future<bool> switchToBluetoothMicPhoneSpeaker() async {
    try {
      debugPrint(
          'AudioProfileService: Switching to Bluetooth Mic → Phone Speaker');

      final result = await _channel.invokeMethod(
          'setAudioProfile', {'profile': 'bluetoothMicPhoneSpeaker'});

      if (result == true) {
        _currentProfile = AudioProfile.bluetoothMicPhoneSpeaker;
        debugPrint(
            'AudioProfileService: Switched to Bluetooth Mic → Phone Speaker');
        return true;
      } else {
        debugPrint(
            'AudioProfileService: Failed to switch to Bluetooth Mic → Phone Speaker');
        return false;
      }
    } catch (e) {
      debugPrint(
          'AudioProfileService: Error switching to Bluetooth Mic → Phone Speaker: $e');
      return false;
    }
  }

  /// Toggle between the two audio profiles
  Future<bool> toggleAudioProfile() async {
    switch (_currentProfile) {
      case AudioProfile.phoneMicBluetoothSpeaker:
        return await switchToBluetoothMicPhoneSpeaker();
      case AudioProfile.bluetoothMicPhoneSpeaker:
        return await switchToPhoneMicBluetoothSpeaker();
    }
  }

  /// Get current audio profile
  AudioProfile get currentProfile => _currentProfile;

  /// Get current profile description
  String get currentProfileDescription {
    switch (_currentProfile) {
      case AudioProfile.phoneMicBluetoothSpeaker:
        return 'Phone Mic → TWS Speaker';
      case AudioProfile.bluetoothMicPhoneSpeaker:
        return 'TWS Mic → Phone Speaker';
    }
  }

  /// Get current input source description
  String get currentInputSource {
    switch (_currentProfile) {
      case AudioProfile.phoneMicBluetoothSpeaker:
        return 'Phone Microphone';
      case AudioProfile.bluetoothMicPhoneSpeaker:
        return 'Bluetooth Microphone';
    }
  }

  /// Get current output destination description
  String get currentOutputDestination {
    switch (_currentProfile) {
      case AudioProfile.phoneMicBluetoothSpeaker:
        return 'Bluetooth Speaker';
      case AudioProfile.bluetoothMicPhoneSpeaker:
        return 'Phone Speaker';
    }
  }

  /// Check if Bluetooth is available for the current profile
  Future<bool> isBluetoothAvailable() async {
    try {
      final result = await _channel.invokeMethod('isBluetoothAvailable');
      return result == true;
    } catch (e) {
      debugPrint(
          'AudioProfileService: Error checking Bluetooth availability: $e');
      return false;
    }
  }

  /// Reset to default profile
  Future<void> resetToDefault() async {
    await switchToPhoneMicBluetoothSpeaker();
  }

  /// Dispose the service
  void dispose() {
    _isInitialized = false;
  }
}
