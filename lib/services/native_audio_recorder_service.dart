import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native Audio Recorder Service that forces use of built-in microphone
/// This bypasses Bluetooth SCO/HFP microphone and uses the phone's internal mic only
/// 
/// CRITICAL: This service uses native Android AudioRecord with MIC audio source
/// to ensure 100% reliable recording from phone microphone regardless of
/// Bluetooth connection status
class NativeAudioRecorderService {
  static const MethodChannel _channel =
      MethodChannel('native_audio_recorder');

  bool _isRecording = false;
  String? _currentRecordingPath;

  /// Start recording with forced built-in microphone
  /// 
  /// [filePath] - Full path where the WAV file will be saved
  /// 
  /// Returns true if recording started successfully
  Future<bool> startRecording(String filePath) async {
    try {
      debugPrint('NativeAudioRecorderService: ═══ Starting Native Recording ═══');
      debugPrint('NativeAudioRecorderService: Output path: $filePath');
      
      if (_isRecording) {
        debugPrint('NativeAudioRecorderService: ⚠️ Already recording, stopping previous recording');
        await stopRecording();
      }

      final bool success = await _channel.invokeMethod(
        'startRecording',
        {'filePath': filePath},
      );

      if (success) {
        _isRecording = true;
        _currentRecordingPath = filePath;
        debugPrint('NativeAudioRecorderService: ✅ Native recording started successfully');
        debugPrint('NativeAudioRecorderService: Using AudioRecord with MIC audio source');
        debugPrint('NativeAudioRecorderService: Forced built-in microphone (NOT Bluetooth)');
      } else {
        debugPrint('NativeAudioRecorderService: ❌ Failed to start native recording');
      }

      return success;
    } catch (e) {
      debugPrint('NativeAudioRecorderService: ❌ Error starting recording: $e');
      return false;
    }
  }

  /// Stop recording
  /// 
  /// Returns the path to the recorded WAV file, or null if recording failed
  Future<String?> stopRecording() async {
    try {
      debugPrint('NativeAudioRecorderService: Stopping native recording...');

      if (!_isRecording) {
        debugPrint('NativeAudioRecorderService: ⚠️ Not currently recording');
        return null;
      }

      final bool success = await _channel.invokeMethod('stopRecording');

      if (success) {
        debugPrint('NativeAudioRecorderService: ✅ Native recording stopped successfully');
        debugPrint('NativeAudioRecorderService: Recording saved to: $_currentRecordingPath');
        
        final String? path = _currentRecordingPath;
        _isRecording = false;
        _currentRecordingPath = null;
        return path;
      } else {
        debugPrint('NativeAudioRecorderService: ❌ Failed to stop native recording');
        _isRecording = false;
        _currentRecordingPath = null;
        return null;
      }
    } catch (e) {
      debugPrint('NativeAudioRecorderService: ❌ Error stopping recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      return null;
    }
  }

  /// Check if currently recording
  Future<bool> isRecording() async {
    try {
      final bool recording = await _channel.invokeMethod('isRecording');
      return recording;
    } catch (e) {
      debugPrint('NativeAudioRecorderService: ❌ Error checking recording status: $e');
      return false;
    }
  }

  /// Get current recording status (local state)
  bool get isRecordingLocal => _isRecording;

  /// Get current recording path (local state)
  String? get currentRecordingPath => _currentRecordingPath;
}

