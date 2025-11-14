import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Streaming Audio Recorder Service for real-time audio capture
/// Extends native audio recorder to support reading audio chunks while recording
/// Used for streaming audio to Soniox real-time translation
class StreamingAudioRecorderService {
  static const MethodChannel _channel =
      MethodChannel('streaming_audio_recorder');

  bool _isRecording = false;
  String? _currentRecordingPath;
  StreamController<Uint8List>? _audioStreamController;

  /// Start recording with streaming support
  /// 
  /// [filePath] - Full path where the WAV file will be saved
  /// [chunkDuration] - Duration of each audio chunk in milliseconds (default: 100ms)
  /// 
  /// Returns a stream of audio chunks (PCM 16-bit, 16kHz, mono)
  Future<Stream<Uint8List>?> startRecording(
    String filePath, {
    int chunkDuration = 100,
  }) async {
    try {
      debugPrint('StreamingAudioRecorderService: ═══ Starting Streaming Recording ═══');
      debugPrint('StreamingAudioRecorderService: Output path: $filePath');
      debugPrint('StreamingAudioRecorderService: Chunk duration: ${chunkDuration}ms');

      if (_isRecording) {
        debugPrint('StreamingAudioRecorderService: ⚠️ Already recording, stopping previous');
        await stopRecording();
      }

      // Create stream controller for audio chunks
      _audioStreamController = StreamController<Uint8List>.broadcast();

      // Start native recording with streaming enabled
      final bool success = await _channel.invokeMethod(
        'startStreamingRecording',
        {
          'filePath': filePath,
          'chunkDurationMs': chunkDuration,
        },
      );

      if (success) {
        _isRecording = true;
        _currentRecordingPath = filePath;
        debugPrint('StreamingAudioRecorderService: ✅ Streaming recording started');

        // Set up method call handler to receive audio chunks from native side
        _channel.setMethodCallHandler(_handleMethodCall);

        return _audioStreamController!.stream;
      } else {
        debugPrint('StreamingAudioRecorderService: ❌ Failed to start streaming recording');
        await _audioStreamController?.close();
        _audioStreamController = null;
        return null;
      }
    } catch (e) {
      debugPrint('StreamingAudioRecorderService: ❌ Error starting recording: $e');
      await _audioStreamController?.close();
      _audioStreamController = null;
      return null;
    }
  }

  /// Handle method calls from native side (audio chunks)
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onAudioChunk':
        final Uint8List audioData = call.arguments as Uint8List;
        debugPrint('StreamingAudioRecorderService: 📥 Received audio chunk: ${audioData.length} bytes');
        _audioStreamController?.add(audioData);
        break;
      case 'onRecordingError':
        final String error = call.arguments as String;
        debugPrint('StreamingAudioRecorderService: ❌ Recording error: $error');
        _audioStreamController?.addError(error);
        break;
      default:
        debugPrint('StreamingAudioRecorderService: ⚠️ Unknown method: ${call.method}');
    }
  }

  /// Stop streaming recording
  /// 
  /// Returns the path to the recorded WAV file, or null if recording failed
  Future<String?> stopRecording() async {
    try {
      debugPrint('StreamingAudioRecorderService: Stopping streaming recording...');

      if (!_isRecording) {
        debugPrint('StreamingAudioRecorderService: ⚠️ Not currently recording');
        return null;
      }

      // Stop native recording
      final bool success = await _channel.invokeMethod('stopStreamingRecording');

      if (success) {
        debugPrint('StreamingAudioRecorderService: ✅ Streaming recording stopped');
        debugPrint('StreamingAudioRecorderService: Recording saved to: $_currentRecordingPath');

        final String? path = _currentRecordingPath;
        _isRecording = false;
        _currentRecordingPath = null;

        // Close stream controller
        await _audioStreamController?.close();
        _audioStreamController = null;

        // Remove method call handler
        _channel.setMethodCallHandler(null);

        return path;
      } else {
        debugPrint('StreamingAudioRecorderService: ❌ Failed to stop streaming recording');
        _isRecording = false;
        _currentRecordingPath = null;
        await _audioStreamController?.close();
        _audioStreamController = null;
        return null;
      }
    } catch (e) {
      debugPrint('StreamingAudioRecorderService: ❌ Error stopping recording: $e');
      _isRecording = false;
      _currentRecordingPath = null;
      await _audioStreamController?.close();
      _audioStreamController = null;
      return null;
    }
  }

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Get current recording path
  String? get currentRecordingPath => _currentRecordingPath;

  /// Dispose resources
  Future<void> dispose() async {
    if (_isRecording) {
      await stopRecording();
    }
    await _audioStreamController?.close();
    _audioStreamController = null;
    _channel.setMethodCallHandler(null);
    debugPrint('StreamingAudioRecorderService: Disposed');
  }
}

