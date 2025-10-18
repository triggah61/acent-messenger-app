import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

/// Enhanced transcription result with speaker information
class SherpaWhisperResult {
  final String text;
  final double confidence;
  final int startTime;
  final int endTime;
  final String language;
  final int speakerId; // Added speaker identification
  final double speakerConfidence; // Confidence in speaker assignment

  SherpaWhisperResult({
    required this.text,
    this.confidence = 0.0,
    this.startTime = 0,
    this.endTime = 0,
    this.language = 'en',
    this.speakerId = 0,
    this.speakerConfidence = 0.0,
  });

  @override
  String toString() {
    return 'SherpaWhisperResult(text: $text, speakerId: $speakerId, confidence: $confidence)';
  }
}

/// Simple speaker segment for basic diarization
class SpeakerSegment {
  final int speakerId;
  final double startTime;
  final double endTime;
  final double confidence;
  final String? text; // Optional transcribed text for this segment

  SpeakerSegment({
    required this.speakerId,
    required this.startTime,
    required this.endTime,
    required this.confidence,
    this.text,
  });
}

class SherpaWhisperService {
  static final SherpaWhisperService _instance =
      SherpaWhisperService._internal();
  factory SherpaWhisperService() => _instance;
  SherpaWhisperService._internal();

  // Sherpa-ONNX recognizer for transcription
  OfflineRecognizer? _recognizer;

  bool _isInitialized = false;
  String? _encoderModelPath;
  String? _decoderModelPath;
  String? _tokensPath;

  // Stream controllers for real-time transcription
  final StreamController<SherpaWhisperResult> _transcriptionController =
      StreamController<SherpaWhisperResult>.broadcast();
  final StreamController<List<SpeakerSegment>> _diarizationController =
      StreamController<List<SpeakerSegment>>.broadcast();

  // Audio processing state - much more conservative approach
  bool _isProcessing = false;
  Timer? _processingTimer;
  final List<Float32List> _audioBuffer = [];
  final int _maxBufferSize = 5; // Further reduced buffer size

  // Crash recovery
  int _crashCount = 0;
  static const int _maxCrashCount = 3;
  bool _isRecovering = false;

  // Simple speaker tracking based on audio characteristics
  final Map<int, double> _speakerEnergyLevels = {};
  final Map<int, double> _speakerPitchLevels = {};
  int _currentSpeakerId = 0;
  double _lastEnergyLevel = 0.0;
  double _lastPitchLevel = 0.0;

  // Speaker change detection
  static const double _energyThreshold = 0.3;
  static const double _pitchThreshold = 0.2;
  int _speakerChangeCounter = 0;

  // Audio analysis
  final List<double> _recentEnergyLevels = [];
  final List<double> _recentPitchLevels = [];
  static const int _analysisWindowSize = 5;

  // Processing safety
  bool _isTranscribing = false;
  DateTime? _lastTranscriptionTime;
  static const Duration _minTranscriptionInterval = Duration(seconds: 3);

  Stream<SherpaWhisperResult> get transcriptionStream =>
      _transcriptionController.stream;
  Stream<List<SpeakerSegment>> get diarizationStream =>
      _diarizationController.stream;

  /// Initialize Sherpa-ONNX for transcription
  Future<bool> initialize() async {
    if (_isInitialized) {
      debugPrint('SherpaWhisperService: Already initialized, skipping...');
      return true;
    }

    try {
      debugPrint('SherpaWhisperService: Initializing Sherpa-ONNX...');

      // Prepare models
      final modelReady = await _prepareModels();
      if (!modelReady) {
        debugPrint('SherpaWhisperService: Failed to prepare models');
        return false;
      }

      // Initialize Sherpa-ONNX recognizer
      await _initializeRecognizer();

      _isInitialized = true;
      _crashCount = 0; // Reset crash count on successful initialization
      debugPrint('SherpaWhisperService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('SherpaWhisperService: Initialization failed: $e');
      return false;
    }
  }

  /// Prepare models for transcription
  Future<bool> _prepareModels() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final modelsDir = '${directory.path}/sherpa_models';

      // Create models directory
      await Directory(modelsDir).create(recursive: true);

      // Model paths for Whisper transcription
      _encoderModelPath = '$modelsDir/tiny-encoder.onnx';
      _decoderModelPath = '$modelsDir/tiny-decoder.onnx';
      _tokensPath = '$modelsDir/tiny-tokens.txt';

      // Check if models exist, if not, copy them from assets
      final encoderFile = File(_encoderModelPath!);
      final decoderFile = File(_decoderModelPath!);
      final tokensFile = File(_tokensPath!);

      if (!await encoderFile.exists() ||
          !await decoderFile.exists() ||
          !await tokensFile.exists()) {
        debugPrint('SherpaWhisperService: Copying models from assets...');
        await _copyModelsFromAssets();
      }

      return await encoderFile.exists() &&
          await decoderFile.exists() &&
          await tokensFile.exists();
    } catch (e) {
      debugPrint('SherpaWhisperService: Error preparing models: $e');
      return false;
    }
  }

  /// Copy models from assets to documents directory
  Future<void> _copyModelsFromAssets() async {
    try {
      debugPrint('SherpaWhisperService: Copying models from assets...');

      final directory = await getApplicationDocumentsDirectory();
      final modelsDir = '${directory.path}/sherpa_models';

      // Copy Whisper models
      final encoderData =
          await rootBundle.load('assets/models/sherpa_onnx/tiny-encoder.onnx');
      final encoderFile = File('$modelsDir/tiny-encoder.onnx');
      await encoderFile.create(recursive: true);
      await encoderFile.writeAsBytes(encoderData.buffer.asUint8List());

      final decoderData =
          await rootBundle.load('assets/models/sherpa_onnx/tiny-decoder.onnx');
      final decoderFile = File('$modelsDir/tiny-decoder.onnx');
      await decoderFile.create(recursive: true);
      await decoderFile.writeAsBytes(decoderData.buffer.asUint8List());

      final tokensData =
          await rootBundle.load('assets/models/sherpa_onnx/tiny-tokens.txt');
      final tokensFile = File('$modelsDir/tiny-tokens.txt');
      await tokensFile.create(recursive: true);
      await tokensFile.writeAsBytes(tokensData.buffer.asUint8List());

      debugPrint('SherpaWhisperService: Models copied successfully');
    } catch (e) {
      debugPrint('SherpaWhisperService: Error copying models from assets: $e');
      rethrow;
    }
  }

  /// Initialize Sherpa-ONNX recognizer with error handling
  Future<void> _initializeRecognizer() async {
    try {
      debugPrint('SherpaWhisperService: Initializing recognizer...');

      // Initialize Sherpa-ONNX first
      await _initializeSherpaOnnx();

      // Create recognizer configuration for offline Whisper
      final config = OfflineRecognizerConfig(
        feat: FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        model: OfflineModelConfig(
          whisper: OfflineWhisperModelConfig(
            encoder: _encoderModelPath!,
            decoder: _decoderModelPath!,
            language: 'en',
            task: 'transcribe',
          ),
          tokens: _tokensPath!,
        ),
        decodingMethod: 'greedy_search',
        maxActivePaths: 4,
      );

      // Initialize recognizer
      _recognizer = OfflineRecognizer(config);

      debugPrint('SherpaWhisperService: Recognizer initialized successfully');
    } catch (e) {
      debugPrint('SherpaWhisperService: Error initializing recognizer: $e');
      rethrow;
    }
  }

  /// Initialize Sherpa-ONNX native library
  Future<void> _initializeSherpaOnnx() async {
    try {
      debugPrint(
          'SherpaWhisperService: Initializing Sherpa-ONNX native library...');
      initBindings();
      debugPrint(
          'SherpaWhisperService: Sherpa-ONNX native library initialized');
    } catch (e) {
      debugPrint(
          'SherpaWhisperService: Error initializing Sherpa-ONNX native library: $e');
      rethrow;
    }
  }

  /// Start real-time transcription with crash protection
  Future<void> startRealtimeTranscription() async {
    if (!_isInitialized || _recognizer == null) {
      throw Exception('SherpaWhisperService not initialized');
    }

    if (_isProcessing) {
      debugPrint('SherpaWhisperService: Already processing, skipping start');
      return;
    }

    if (_isRecovering) {
      debugPrint(
          'SherpaWhisperService: Still recovering from crash, please wait');
      return;
    }

    try {
      debugPrint('SherpaWhisperService: Starting real-time transcription');

      _isProcessing = true;
      _audioBuffer.clear();
      _currentSpeakerId = 0;
      _isTranscribing = false;
      _lastTranscriptionTime = null;

      // Start periodic processing with much more conservative approach
      _processingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (!_isProcessing) {
          timer.cancel();
          return;
        }
        _processBufferedAudioSafely();
      });

      debugPrint('SherpaWhisperService: Real-time processing started');
    } catch (e) {
      debugPrint(
          'SherpaWhisperService: Error starting real-time transcription: $e');
      _isProcessing = false;
      rethrow;
    }
  }

  /// Stop real-time transcription
  Future<void> stopRealtimeTranscription() async {
    try {
      debugPrint('SherpaWhisperService: Stopping real-time transcription');

      _isProcessing = false;
      _processingTimer?.cancel();
      _processingTimer = null;

      // Don't process remaining audio to avoid crashes
      _audioBuffer.clear();

      debugPrint('SherpaWhisperService: Real-time transcription stopped');
    } catch (e) {
      debugPrint(
          'SherpaWhisperService: Error stopping real-time transcription: $e');
    }
  }

  /// Process audio chunk and add to buffer with strict limits
  Future<void> processAudioChunk(Uint8List audioData) async {
    if (!_isInitialized || _recognizer == null) {
      throw Exception('SherpaWhisperService not initialized');
    }

    if (_isRecovering) {
      debugPrint('SherpaWhisperService: Skipping audio chunk during recovery');
      return;
    }

    try {
      // Limit audio data size to prevent crashes
      if (audioData.length > 500000) {
        // 500KB limit
        debugPrint(
            'SherpaWhisperService: Audio chunk too large (${audioData.length} bytes), skipping');
        return;
      }

      // Convert audio bytes to Float32List
      final Float32List audioFloatList = _convertBytesToFloat32List(audioData);

      // Limit sample count to prevent crashes
      if (audioFloatList.length > 100000) {
        // 100K samples limit
        debugPrint(
            'SherpaWhisperService: Audio samples too many (${audioFloatList.length}), truncating');
        final truncatedAudio = Float32List(100000);
        truncatedAudio.setRange(0, 100000, audioFloatList);
        _analyzeAudioCharacteristics(truncatedAudio);

        // Add to buffer (strict limit)
        if (_audioBuffer.length >= _maxBufferSize) {
          _audioBuffer.removeAt(0);
        }
        _audioBuffer.add(truncatedAudio);
      } else {
        // Analyze audio for speaker characteristics
        _analyzeAudioCharacteristics(audioFloatList);

        // Add to buffer (strict limit)
        if (_audioBuffer.length >= _maxBufferSize) {
          _audioBuffer.removeAt(0);
        }
        _audioBuffer.add(audioFloatList);
      }

      debugPrint(
          'SherpaWhisperService: Added audio chunk to buffer (${audioFloatList.length} samples)');
    } catch (e) {
      debugPrint('SherpaWhisperService: Error processing audio chunk: $e');
      _handleCrash();
    }
  }

  /// Safely process buffered audio with crash protection
  Future<void> _processBufferedAudioSafely() async {
    if (_audioBuffer.isEmpty || _isRecovering) return;

    // Check if we should skip this processing cycle
    if (_isTranscribing) {
      debugPrint(
          'SherpaWhisperService: Still transcribing, skipping this cycle');
      return;
    }

    final now = DateTime.now();
    if (_lastTranscriptionTime != null &&
        now.difference(_lastTranscriptionTime!) < _minTranscriptionInterval) {
      debugPrint(
          'SherpaWhisperService: Too soon since last transcription, skipping');
      return;
    }

    try {
      debugPrint(
          'SherpaWhisperService: Processing buffered audio safely (${_audioBuffer.length} chunks)');

      // Take only the most recent chunk to minimize processing
      final audioChunk = _audioBuffer.last;

      // Clear buffer to prevent accumulation
      _audioBuffer.clear();

      // Process only if chunk is reasonable size
      if (audioChunk.length > 10000 && audioChunk.length < 200000) {
        await _performTranscriptionSafely(audioChunk);
        await _performSimpleSpeakerDiarization(audioChunk);
      } else {
        debugPrint(
            'SherpaWhisperService: Audio chunk size not suitable (${audioChunk.length}), skipping');
      }
    } catch (e) {
      debugPrint('SherpaWhisperService: Error in safe audio processing: $e');
      _handleCrash();
    }
  }

  /// Perform transcription with crash protection
  Future<void> _performTranscriptionSafely(Float32List audioData) async {
    if (_isTranscribing || _isRecovering) {
      debugPrint(
          'SherpaWhisperService: Skipping transcription - already in progress or recovering');
      return;
    }

    _isTranscribing = true;
    _lastTranscriptionTime = DateTime.now();

    try {
      debugPrint('SherpaWhisperService: Starting safe transcription...');

      // Create stream for transcription
      final stream = _recognizer!.createStream();

      // Feed audio data to recognizer
      stream.acceptWaveform(samples: audioData, sampleRate: 16000);

      // Decode and get result
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);

      // Clean up stream immediately to prevent memory leaks
      stream.free();

      if (result.text.isNotEmpty) {
        final transcription = SherpaWhisperResult(
          text: result.text,
          confidence: 0.95,
          startTime: 0,
          endTime: audioData.length ~/ 16000,
          language: result.lang.isNotEmpty ? result.lang : 'en',
          speakerId: _currentSpeakerId,
          speakerConfidence: _calculateSpeakerConfidence(),
        );

        debugPrint(
            'SherpaWhisperService: Safe transcription result: ${transcription.text} (Speaker: ${transcription.speakerId})');

        // Add to stream if not closed
        if (!_transcriptionController.isClosed) {
          _transcriptionController.add(transcription);
        }

        // Reset crash count on successful transcription
        _crashCount = 0;
      }
    } catch (e) {
      debugPrint('SherpaWhisperService: Error in safe transcription: $e');
      _handleCrash();
    } finally {
      _isTranscribing = false;
    }
  }

  /// Handle crashes and implement recovery
  Future<void> _handleCrash() async {
    _crashCount++;
    debugPrint('SherpaWhisperService: Crash detected (count: $_crashCount)');

    if (_crashCount >= _maxCrashCount) {
      debugPrint('SherpaWhisperService: Too many crashes, stopping service');
      await stopRealtimeTranscription();
      _isRecovering = true;

      // Try to recover after a delay
      Timer(const Duration(seconds: 10), () async {
        debugPrint('SherpaWhisperService: Attempting recovery...');
        await _attemptRecovery();
      });
    } else {
      // Brief pause before continuing
      _isRecovering = true;
      Timer(const Duration(seconds: 2), () {
        _isRecovering = false;
        debugPrint('SherpaWhisperService: Recovery pause completed');
      });
    }
  }

  /// Attempt to recover from crashes
  Future<void> _attemptRecovery() async {
    try {
      debugPrint('SherpaWhisperService: Attempting service recovery...');

      // Cleanup current recognizer
      _recognizer?.free();
      _recognizer = null;

      // Reinitialize
      await _initializeRecognizer();

      _isRecovering = false;
      _crashCount = 0;

      debugPrint('SherpaWhisperService: Recovery successful');
    } catch (e) {
      debugPrint('SherpaWhisperService: Recovery failed: $e');
      _isRecovering = false;
    }
  }

  /// Analyze audio characteristics for simple speaker detection
  void _analyzeAudioCharacteristics(Float32List audioData) {
    try {
      // Calculate energy level (RMS)
      double energy = 0.0;
      for (double sample in audioData) {
        energy += sample * sample;
      }
      energy = sqrt(energy / audioData.length);

      // Calculate simple pitch approximation (zero-crossing rate)
      int zeroCrossings = 0;
      for (int i = 1; i < audioData.length; i++) {
        if ((audioData[i] >= 0) != (audioData[i - 1] >= 0)) {
          zeroCrossings++;
        }
      }
      double pitch = zeroCrossings / audioData.length;

      // Store recent values for smoothing
      _recentEnergyLevels.add(energy);
      _recentPitchLevels.add(pitch);

      if (_recentEnergyLevels.length > _analysisWindowSize) {
        _recentEnergyLevels.removeAt(0);
      }
      if (_recentPitchLevels.length > _analysisWindowSize) {
        _recentPitchLevels.removeAt(0);
      }

      // Calculate smoothed values
      double smoothedEnergy = _recentEnergyLevels.fold(0.0, (a, b) => a + b) /
          _recentEnergyLevels.length;
      double smoothedPitch = _recentPitchLevels.fold(0.0, (a, b) => a + b) /
          _recentPitchLevels.length;

      // Detect speaker change
      bool speakerChanged = false;
      if (_lastEnergyLevel > 0 && _lastPitchLevel > 0) {
        double energyDiff = (smoothedEnergy - _lastEnergyLevel).abs() /
            (_lastEnergyLevel + 0.001);
        double pitchDiff =
            (smoothedPitch - _lastPitchLevel).abs() / (_lastPitchLevel + 0.001);

        if (energyDiff > _energyThreshold || pitchDiff > _pitchThreshold) {
          speakerChanged = true;
        }
      }

      if (speakerChanged) {
        _speakerChangeCounter++;
        _currentSpeakerId =
            _speakerChangeCounter % 2; // Alternate between 2 speakers

        debugPrint(
            'SherpaWhisperService: Speaker change detected. New speaker: $_currentSpeakerId');
      }

      // Update speaker characteristics
      _speakerEnergyLevels[_currentSpeakerId] = smoothedEnergy;
      _speakerPitchLevels[_currentSpeakerId] = smoothedPitch;

      _lastEnergyLevel = smoothedEnergy;
      _lastPitchLevel = smoothedPitch;
    } catch (e) {
      debugPrint(
          'SherpaWhisperService: Error analyzing audio characteristics: $e');
    }
  }

  /// Perform simple speaker diarization based on audio characteristics
  Future<void> _performSimpleSpeakerDiarization(Float32List audioData) async {
    try {
      debugPrint(
          'SherpaWhisperService: Performing simple speaker diarization...');

      final segments = <SpeakerSegment>[];

      // Create segments based on current speaker
      if (_speakerEnergyLevels.containsKey(_currentSpeakerId)) {
        final segment = SpeakerSegment(
          speakerId: _currentSpeakerId,
          startTime: 0.0,
          endTime: audioData.length / 16000.0, // Duration in seconds
          confidence: _calculateSpeakerConfidence(),
        );

        segments.add(segment);

        debugPrint(
            'SherpaWhisperService: Created speaker segment for Speaker $_currentSpeakerId');

        // Add to stream if not closed
        if (!_diarizationController.isClosed) {
          _diarizationController.add(segments);
        }
      }
    } catch (e) {
      debugPrint(
          'SherpaWhisperService: Error in simple speaker diarization: $e');
    }
  }

  /// Calculate speaker confidence based on audio characteristics
  double _calculateSpeakerConfidence() {
    try {
      if (_speakerEnergyLevels.isEmpty) return 0.5;

      final currentEnergy = _speakerEnergyLevels[_currentSpeakerId] ?? 0.0;
      final currentPitch = _speakerPitchLevels[_currentSpeakerId] ?? 0.0;

      // Simple confidence calculation based on consistency
      double energyConsistency = 1.0;
      double pitchConsistency = 1.0;

      for (final entry in _speakerEnergyLevels.entries) {
        if (entry.key != _currentSpeakerId) {
          double diff = (currentEnergy - entry.value).abs() /
              (currentEnergy + entry.value + 0.001);
          energyConsistency = energyConsistency * (1.0 - diff);
        }
      }

      for (final entry in _speakerPitchLevels.entries) {
        if (entry.key != _currentSpeakerId) {
          double diff = (currentPitch - entry.value).abs() /
              (currentPitch + entry.value + 0.001);
          pitchConsistency = pitchConsistency * (1.0 - diff);
        }
      }

      return (energyConsistency + pitchConsistency) / 2.0;
    } catch (e) {
      debugPrint(
          'SherpaWhisperService: Error calculating speaker confidence: $e');
      return 0.5;
    }
  }

  /// Convert audio bytes to Float32List
  Float32List _convertBytesToFloat32List(Uint8List audioBytes) {
    // Skip WAV header if present (44 bytes)
    final audioData =
        audioBytes.length > 44 ? audioBytes.sublist(44) : audioBytes;

    final Float32List audioFloatList = Float32List(audioData.length ~/ 2);
    for (int i = 0; i < audioFloatList.length; i++) {
      int int16 = (audioData[i * 2] | (audioData[i * 2 + 1] << 8));
      if (int16 > 32767) int16 -= 65536; // Convert to signed
      audioFloatList[i] = int16 / 32768.0; // Normalize to [-1, 1]
    }

    return audioFloatList;
  }

  /// Transcribe audio file with crash protection
  Future<SherpaWhisperResult> transcribeAudio(Uint8List audioData) async {
    if (!_isInitialized || _recognizer == null) {
      throw Exception('SherpaWhisperService not initialized');
    }

    if (_isRecovering) {
      throw Exception(
          'Service is recovering from crash, please try again later');
    }

    try {
      debugPrint(
          'SherpaWhisperService: Transcribing audio file (${audioData.length} bytes)');

      // Limit audio size
      if (audioData.length > 1000000) {
        // 1MB limit
        throw Exception('Audio file too large for processing');
      }

      // Convert to Float32List
      final Float32List audioFloatList = _convertBytesToFloat32List(audioData);

      // Limit sample count
      if (audioFloatList.length > 200000) {
        // 200K samples limit
        throw Exception('Audio too long for processing');
      }

      // Analyze audio characteristics
      _analyzeAudioCharacteristics(audioFloatList);

      // Create stream for transcription
      final stream = _recognizer!.createStream();

      // Feed audio data to recognizer
      stream.acceptWaveform(samples: audioFloatList, sampleRate: 16000);

      // Decode and get result
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);

      // Clean up stream
      stream.free();

      if (result.text.isNotEmpty) {
        final transcription = SherpaWhisperResult(
          text: result.text,
          confidence: 0.95,
          startTime: 0,
          endTime: audioFloatList.length ~/ 16000,
          language: result.lang.isNotEmpty ? result.lang : 'en',
          speakerId: _currentSpeakerId,
          speakerConfidence: _calculateSpeakerConfidence(),
        );

        debugPrint(
            'SherpaWhisperService: Transcription result: ${transcription.text}');
        return transcription;
      } else {
        throw Exception('No transcription segments found');
      }
    } catch (e) {
      debugPrint('SherpaWhisperService: Transcription error: $e');
      _handleCrash();
      rethrow;
    }
  }

  /// Get speaker name by ID
  String getSpeakerName(int speakerId) {
    return 'Speaker ${speakerId + 1}';
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if speaker diarization is available
  bool get isDiarizationAvailable => !_isRecovering;

  /// Check if service is recovering
  bool get isRecovering => _isRecovering;

  /// Get crash count
  int get crashCount => _crashCount;

  /// Stop all ongoing operations and cleanup
  Future<void> cleanup() async {
    try {
      debugPrint('SherpaWhisperService: Cleaning up...');

      // Stop processing
      await stopRealtimeTranscription();

      // Cleanup recognizer
      _recognizer?.free();
      _recognizer = null;

      // Clear audio buffer and analysis data
      _audioBuffer.clear();
      _recentEnergyLevels.clear();
      _recentPitchLevels.clear();
      _speakerEnergyLevels.clear();
      _speakerPitchLevels.clear();

      // Close stream controllers if not already closed
      if (!_transcriptionController.isClosed) {
        _transcriptionController.close();
      }
      if (!_diarizationController.isClosed) {
        _diarizationController.close();
      }

      _isInitialized = false;
      _isRecovering = false;
      _crashCount = 0;
      debugPrint('SherpaWhisperService: Cleanup completed');
    } catch (e) {
      debugPrint('SherpaWhisperService: Error during cleanup: $e');
    }
  }

  /// Dispose resources (legacy method for compatibility)
  void dispose() {
    cleanup();
  }
}
