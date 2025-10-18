import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Whisper transcription result
class WhisperTranscriptionResult {
  final String text;
  final double confidence;
  final int startTime;
  final int endTime;
  final String language;

  WhisperTranscriptionResult({
    required this.text,
    this.confidence = 0.0,
    this.startTime = 0,
    this.endTime = 0,
    this.language = 'en',
  });
}

class WhisperService {
  static final WhisperService _instance = WhisperService._internal();
  factory WhisperService() => _instance;
  WhisperService._internal();

  // Platform channel for native Whisper integration
  static const MethodChannel _channel = MethodChannel('whisper_service');

  bool _isInitialized = false;
  String? _modelPath;

  // Stream controllers for real-time transcription
  final StreamController<WhisperTranscriptionResult> _transcriptionController =
      StreamController<WhisperTranscriptionResult>.broadcast();

  Stream<WhisperTranscriptionResult> get transcriptionStream =>
      _transcriptionController.stream;

  /// Initialize Whisper service
  Future<bool> initialize() async {
    if (_isInitialized) {
      debugPrint('WhisperService: Already initialized, skipping...');
      return true;
    }

    try {
      debugPrint('WhisperService: Initializing with platform channels...');

      // Ensure model is ready
      final modelReady = await _prepareModel();
      if (!modelReady) {
        debugPrint('WhisperService: Failed to prepare model');
        return false;
      }

      // Initialize native Whisper service
      final result = await _channel.invokeMethod('initialize');
      if (result == true) {
        _isInitialized = true;
        debugPrint(
            'WhisperService: Platform channel Whisper service initialized successfully');
        return true;
      } else {
        debugPrint('WhisperService: Native initialization failed');
        return false;
      }
    } catch (e) {
      debugPrint('WhisperService: Initialization failed: $e');
      return false;
    }
  }

  /// Prepare Whisper model (copy from assets if not exists)
  Future<bool> _prepareModel() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _modelPath = '${directory.path}/whisper_small.en.bin';

      // If model doesn't exist in documents, copy from assets
      if (!await File(_modelPath!).exists()) {
        await _copyModelFromAssets();
      }

      return await File(_modelPath!).exists();
    } catch (e) {
      debugPrint('WhisperService: Error preparing model: $e');
      return false;
    }
  }

  /// Copy Whisper model from assets to documents directory
  Future<bool> _copyModelFromAssets() async {
    try {
      debugPrint('WhisperService: Copying model from assets...');

      // Load model from assets
      final ByteData modelData =
          await rootBundle.load('assets/models/whisper-small.en.bin');
      final Uint8List modelBytes = modelData.buffer.asUint8List();

      // Write to documents directory
      final directory = await getApplicationDocumentsDirectory();
      _modelPath = '${directory.path}/whisper_small.en.bin';
      final file = File(_modelPath!);
      await file.create(recursive: true);
      await file.writeAsBytes(modelBytes);

      debugPrint(
          'WhisperService: GGML model copied successfully (${modelBytes.length} bytes)');
      return true;
    } catch (e) {
      debugPrint('WhisperService: Error copying model from assets: $e');
      return false;
    }
  }

  /// Transcribe audio data using native Whisper via platform channel
  Future<WhisperTranscriptionResult> transcribeAudio(
      Uint8List audioData) async {
    if (!_isInitialized) {
      throw Exception('WhisperService not initialized');
    }

    try {
      debugPrint(
          'WhisperService: Transcribing audio with native Whisper (${audioData.length} bytes)');

      // Create temporary audio file with proper WAV format
      final directory = await getTemporaryDirectory();
      final tempFile = File(
          '${directory.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.wav');

      // Create proper WAV file with headers
      await _createWavFile(tempFile, audioData);

      debugPrint(
          'WhisperService: Created WAV file: ${tempFile.path} (${await tempFile.length()} bytes)');

      // Call native Whisper service via platform channel
      final result = await _channel.invokeMethod('transcribe', {
        'audioPath': tempFile.path,
        'modelPath': _modelPath,
      });

      debugPrint(
          'WhisperService: Native transcription completed, result: $result');

      // Clean up temp file
      await tempFile.delete();

      // Process results
      if (result != null &&
          result['text'] != null &&
          result['text'].toString().isNotEmpty) {
        final transcription = WhisperTranscriptionResult(
          text: result['text'].toString(),
          confidence: (result['confidence'] as num?)?.toDouble() ?? 0.95,
          startTime: (result['startTime'] as num?)?.toInt() ?? 0,
          endTime: (result['endTime'] as num?)?.toInt() ?? 0,
          language: result['language']?.toString() ?? 'en',
        );

        debugPrint(
            'WhisperService: Native transcription result: ${transcription.text}');
        return transcription;
      } else {
        debugPrint('WhisperService: No transcription result or empty text');
        throw Exception('No transcription segments found');
      }
    } catch (e) {
      debugPrint('WhisperService: Transcription error: $e');
      rethrow;
    }
  }

  /// Create a proper WAV file with headers
  Future<void> _createWavFile(File file, Uint8List audioData) async {
    try {
      debugPrint('WhisperService: Creating WAV file with headers...');

      // WAV file parameters
      const int sampleRate = 16000;
      const int channels = 1;
      const int bitsPerSample = 16;
      final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
      final int blockAlign = channels * bitsPerSample ~/ 8;
      final int dataSize = audioData.length;
      final int fileSize = 36 + dataSize;

      // Create WAV header
      final ByteData header = ByteData(44);

      // RIFF header
      header.setUint8(0, 0x52); // 'R'
      header.setUint8(1, 0x49); // 'I'
      header.setUint8(2, 0x46); // 'F'
      header.setUint8(3, 0x46); // 'F'
      header.setUint32(4, fileSize, Endian.little);
      header.setUint8(8, 0x57); // 'W'
      header.setUint8(9, 0x41); // 'A'
      header.setUint8(10, 0x56); // 'V'
      header.setUint8(11, 0x45); // 'E'

      // fmt chunk
      header.setUint8(12, 0x66); // 'f'
      header.setUint8(13, 0x6D); // 'm'
      header.setUint8(14, 0x74); // 't'
      header.setUint8(15, 0x20); // ' '
      header.setUint32(16, 16, Endian.little); // fmt chunk size
      header.setUint16(20, 1, Endian.little); // audio format (PCM)
      header.setUint16(22, channels, Endian.little); // channels
      header.setUint32(24, sampleRate, Endian.little); // sample rate
      header.setUint32(28, byteRate, Endian.little); // byte rate
      header.setUint16(32, blockAlign, Endian.little); // block align
      header.setUint16(34, bitsPerSample, Endian.little); // bits per sample

      // data chunk
      header.setUint8(36, 0x64); // 'd'
      header.setUint8(37, 0x61); // 'a'
      header.setUint8(38, 0x74); // 't'
      header.setUint8(39, 0x61); // 'a'
      header.setUint32(40, dataSize, Endian.little); // data size

      // Combine header and audio data
      final Uint8List headerBytes = header.buffer.asUint8List();
      final Uint8List wavFile =
          Uint8List(headerBytes.length + audioData.length);
      wavFile.setRange(0, headerBytes.length, headerBytes);
      wavFile.setRange(
          headerBytes.length, headerBytes.length + audioData.length, audioData);

      // Write to file
      await file.writeAsBytes(wavFile);

      debugPrint(
          'WhisperService: WAV file created successfully (${wavFile.length} bytes total)');
    } catch (e) {
      debugPrint('WhisperService: Error creating WAV file: $e');
      rethrow;
    }
  }

  /// Start real-time transcription with audio streaming
  Future<void> startRealtimeTranscription() async {
    if (!_isInitialized) {
      throw Exception('WhisperService not initialized');
    }

    try {
      debugPrint(
          'WhisperService: Starting real-time transcription with native Whisper');

      // Start native real-time transcription
      await _channel.invokeMethod('startRealtimeTranscription');

      debugPrint('WhisperService: Native real-time transcription started');
    } catch (e) {
      debugPrint('WhisperService: Error starting real-time transcription: $e');
      rethrow;
    }
  }

  /// Stop real-time transcription
  Future<void> stopRealtimeTranscription() async {
    if (!_isInitialized) {
      throw Exception('WhisperService not initialized');
    }

    try {
      debugPrint('WhisperService: Stopping native real-time transcription');

      // Stop native real-time transcription
      await _channel.invokeMethod('stopRealtimeTranscription');

      debugPrint('WhisperService: Native real-time transcription stopped');
    } catch (e) {
      debugPrint('WhisperService: Error stopping real-time transcription: $e');
      rethrow;
    }
  }

  /// Process an audio chunk for real-time transcription
  Future<void> processAudioChunk(Uint8List audioData) async {
    if (!_isInitialized) {
      throw Exception('WhisperService not initialized');
    }

    try {
      debugPrint(
          'WhisperService: Processing audio chunk with native Whisper (${audioData.length} bytes)');

      // Create temporary audio file with proper WAV format
      final directory = await getTemporaryDirectory();
      final tempFile = File(
          '${directory.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.wav');

      // Create proper WAV file with headers
      await _createWavFile(tempFile, audioData);

      debugPrint(
          'WhisperService: Created WAV file for chunk: ${tempFile.path} (${await tempFile.length()} bytes)');

      // Call native Whisper service via platform channel
      final result = await _channel.invokeMethod('processAudioChunk', {
        'audioPath': tempFile.path,
        'modelPath': _modelPath,
      });

      debugPrint(
          'WhisperService: Native chunk processing completed, result: $result');

      // Clean up temp file
      await tempFile.delete();

      // Process results
      if (result != null &&
          result['text'] != null &&
          result['text'].toString().isNotEmpty) {
        final transcription = WhisperTranscriptionResult(
          text: result['text'].toString(),
          confidence: (result['confidence'] as num?)?.toDouble() ?? 0.95,
          startTime: (result['startTime'] as num?)?.toInt() ?? 0,
          endTime: (result['endTime'] as num?)?.toInt() ?? 0,
          language: result['language']?.toString() ?? 'en',
        );

        debugPrint(
            'WhisperService: Native chunk transcription result: ${transcription.text}');

        // Only add to stream if it's not closed
        if (!_transcriptionController.isClosed) {
          _transcriptionController.add(transcription);
        } else {
          debugPrint(
              'WhisperService: Stream controller is closed, cannot add transcription result');
        }
      } else {
        debugPrint(
            'WhisperService: No transcription segments found for this chunk.');
      }
    } catch (e) {
      debugPrint('WhisperService: Error processing audio chunk: $e');
      // Optionally, add an error to the stream or handle it differently
    }
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Stop all ongoing operations and cleanup
  Future<void> cleanup() async {
    try {
      debugPrint('WhisperService: Cleaning up...');

      // Stop any ongoing real-time transcription
      if (_isInitialized) {
        await stopRealtimeTranscription();
      }

      // Only close the stream controller if it's not already closed
      if (!_transcriptionController.isClosed) {
        _transcriptionController.close();
      }

      _isInitialized = false;
      debugPrint('WhisperService: Cleanup completed');
    } catch (e) {
      debugPrint('WhisperService: Error during cleanup: $e');
    }
  }

  /// Dispose resources (legacy method for compatibility)
  void dispose() {
    cleanup();
  }
}
