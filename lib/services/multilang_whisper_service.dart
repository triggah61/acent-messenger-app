import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Multi-language Whisper transcription service
/// Supports transcribing audio files in different languages
class MultiLangWhisperService {
  static final MultiLangWhisperService _instance =
      MultiLangWhisperService._internal();
  factory MultiLangWhisperService() => _instance;
  MultiLangWhisperService._internal();

  bool _isInitialized = false;
  String? _encoderModelPath;
  String? _decoderModelPath;
  String? _tokensPath;
  Isolate? _transcriptionIsolate;
  SendPort? _isolateSendPort;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize the Whisper model files
  Future<bool> initialize() async {
    if (_isInitialized) {
      debugPrint('MultiLangWhisperService: Already initialized');
      return true;
    }

    try {
      debugPrint('MultiLangWhisperService: Initializing...');

      // Prepare model files
      final modelReady = await _prepareModels();
      if (!modelReady) {
        debugPrint('MultiLangWhisperService: Failed to prepare models');
        return false;
      }

      // Initialize Sherpa-ONNX library
      await _initializeSherpaOnnx();

      // Initialize background isolate for transcription
      await _initializeTranscriptionIsolate();

      _isInitialized = true;
      debugPrint('MultiLangWhisperService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('MultiLangWhisperService: Initialization failed: $e');
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

      // Model paths for Whisper transcription - using WHISPER-SMALL MULTILINGUAL model
      _encoderModelPath = '$modelsDir/small-encoder-multilang.onnx';
      _decoderModelPath = '$modelsDir/small-decoder-multilang.onnx';
      _tokensPath = '$modelsDir/small-tokens-multilang.txt';

      // Check if models exist, if not, copy them from assets
      final encoderFile = File(_encoderModelPath!);
      final decoderFile = File(_decoderModelPath!);
      final tokensFile = File(_tokensPath!);

      // FORCE re-copy if using old models (tiny or English-only)
      bool needsRecopy = false;
      if (await encoderFile.exists()) {
        final size = await encoderFile.length();
        debugPrint(
            'MultiLangWhisperService: Existing encoder size: $size bytes');
        // Whisper-Small encoder should be ~112MB (112442483 bytes)
        // If it's much smaller, it's probably the tiny model
        if (size < 100000000) {
          // Less than 100MB is suspicious for small model
          debugPrint(
              '⚠️ Encoder file too small for Whisper-Small, forcing recopy');
          needsRecopy = true;
        }
      }

      if (!await encoderFile.exists() ||
          !await decoderFile.exists() ||
          !await tokensFile.exists() ||
          needsRecopy) {
        debugPrint(
            'MultiLangWhisperService: Copying WHISPER-SMALL MULTILINGUAL models from assets...');
        await _copyModelsFromAssets();
      } else {
        debugPrint(
            'MultiLangWhisperService: Using existing Whisper-Small multilingual models');
      }

      return await encoderFile.exists() &&
          await decoderFile.exists() &&
          await tokensFile.exists();
    } catch (e) {
      debugPrint('MultiLangWhisperService: Error preparing models: $e');
      return false;
    }
  }

  /// Copy models from assets to documents directory
  Future<void> _copyModelsFromAssets() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final modelsDir = '${directory.path}/sherpa_models';

      debugPrint(
          '🔄 MultiLangWhisperService: Copying WHISPER-SMALL MULTILINGUAL models...');

      // Copy Whisper SMALL models (MULTILINGUAL VERSION - Much better accuracy!)
      debugPrint('   Loading SMALL encoder from assets...');
      final encoderData = await rootBundle.load(
          'assets/models/whisper/sherpa-onnx-whisper-small/small-encoder.int8.onnx');
      debugPrint(
          '   SMALL Encoder loaded: ${encoderData.lengthInBytes} bytes (~112 MB)');

      final encoderFile = File('$modelsDir/small-encoder-multilang.onnx');
      await encoderFile.create(recursive: true);
      await encoderFile.writeAsBytes(encoderData.buffer.asUint8List());
      debugPrint('   ✅ SMALL Encoder copied to: ${encoderFile.path}');

      debugPrint('   Loading SMALL decoder from assets...');
      final decoderData = await rootBundle.load(
          'assets/models/whisper/sherpa-onnx-whisper-small/small-decoder.int8.onnx');
      debugPrint(
          '   SMALL Decoder loaded: ${decoderData.lengthInBytes} bytes (~262 MB)');

      final decoderFile = File('$modelsDir/small-decoder-multilang.onnx');
      await decoderFile.create(recursive: true);
      await decoderFile.writeAsBytes(decoderData.buffer.asUint8List());
      debugPrint('   ✅ SMALL Decoder copied to: ${decoderFile.path}');

      debugPrint('   Loading SMALL tokens from assets...');
      final tokensData = await rootBundle.load(
          'assets/models/whisper/sherpa-onnx-whisper-small/small-tokens.txt');
      debugPrint('   SMALL Tokens loaded: ${tokensData.lengthInBytes} bytes');

      final tokensFile = File('$modelsDir/small-tokens-multilang.txt');
      await tokensFile.create(recursive: true);
      await tokensFile.writeAsBytes(tokensData.buffer.asUint8List());
      debugPrint('   ✅ SMALL Tokens copied to: ${tokensFile.path}');

      debugPrint(
          '✅ MultiLangWhisperService: All WHISPER-SMALL MULTILINGUAL models copied successfully!');
      debugPrint(
          '   Model: Whisper SMALL (multilingual) - Much better accuracy!');
      debugPrint('   Encoder: ${encoderData.lengthInBytes} bytes');
      debugPrint('   Decoder: ${decoderData.lengthInBytes} bytes');
      debugPrint('   Tokens: ${tokensData.lengthInBytes} bytes');
    } catch (e, stackTrace) {
      debugPrint('❌ MultiLangWhisperService: Error copying models: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Initialize Sherpa-ONNX native library
  Future<void> _initializeSherpaOnnx() async {
    try {
      debugPrint(
          'MultiLangWhisperService: Initializing Sherpa-ONNX library...');
      sherpa.initBindings();
      debugPrint('MultiLangWhisperService: Sherpa-ONNX library initialized');
    } catch (e) {
      debugPrint('MultiLangWhisperService: Error initializing library: $e');
      rethrow;
    }
  }

  /// Initialize background isolate for transcription
  Future<void> _initializeTranscriptionIsolate() async {
    try {
      debugPrint('MultiLangWhisperService: Starting transcription isolate...');

      final receivePort = ReceivePort();
      _transcriptionIsolate = await Isolate.spawn(
        _transcriptionIsolateEntry,
        receivePort.sendPort,
      );

      _isolateSendPort = await receivePort.first as SendPort;
      debugPrint('MultiLangWhisperService: Transcription isolate ready');
    } catch (e) {
      debugPrint('MultiLangWhisperService: Error starting isolate: $e');
      rethrow;
    }
  }

  /// Entry point for transcription isolate
  static void _transcriptionIsolateEntry(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String;

        if (type == 'transcribe') {
          try {
            final audioPath = message['audioPath'] as String;
            final languageCode = message['languageCode'] as String;
            final encoderPath = message['encoderPath'] as String;
            final decoderPath = message['decoderPath'] as String;
            final tokensPath = message['tokensPath'] as String;

            // Initialize Sherpa-ONNX in isolate
            sherpa.initBindings();

            // Perform transcription
            final result = await _performTranscriptionInIsolate(
                audioPath, languageCode, encoderPath, decoderPath, tokensPath);

            sendPort.send({
              'type': 'result',
              'success': true,
              'transcription': result,
            });
          } catch (e) {
            sendPort.send({
              'type': 'result',
              'success': false,
              'error': e.toString(),
            });
          }
        }
      }
    });
  }

  /// Perform transcription in isolate
  static Future<String> _performTranscriptionInIsolate(
    String audioPath,
    String languageCode,
    String encoderPath,
    String decoderPath,
    String tokensPath,
  ) async {
    sherpa.OfflineRecognizer? recognizer;
    sherpa.OfflineStream? stream;

    try {
      // Read audio file
      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        throw Exception('Audio file not found: $audioPath');
      }

      final audioBytes = await audioFile.readAsBytes();
      final Float32List audioSamples =
          _convertBytesToFloat32ListInIsolate(audioBytes);

      // Map language code
      final whisperLanguage = _mapLanguageCodeInIsolate(languageCode);

      // Create recognizer
      final config = sherpa.OfflineRecognizerConfig(
        feat: sherpa.FeatureConfig(
          sampleRate: 16000,
          featureDim: 80,
        ),
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: encoderPath,
            decoder: decoderPath,
            language: whisperLanguage,
            task: 'transcribe',
          ),
          tokens: tokensPath,
        ),
        decodingMethod: 'greedy_search',
        maxActivePaths: 1,
      );

      recognizer = sherpa.OfflineRecognizer(config);
      stream = recognizer.createStream();
      stream.acceptWaveform(samples: audioSamples, sampleRate: 16000);
      recognizer.decode(stream);

      final result = recognizer.getResult(stream);
      final transcription = result.text.trim();

      // Cleanup
      stream.free();
      recognizer.free();

      return transcription;
    } catch (e) {
      // Cleanup on error
      try {
        stream?.free();
        recognizer?.free();
      } catch (cleanupError) {
        // Ignore cleanup errors
      }
      rethrow;
    }
  }

  /// Convert audio bytes to Float32List in isolate
  static Float32List _convertBytesToFloat32ListInIsolate(Uint8List audioBytes) {
    final audioData =
        audioBytes.length > 44 ? audioBytes.sublist(44) : audioBytes;
    final Float32List audioFloatList = Float32List(audioData.length ~/ 2);

    for (int i = 0; i < audioFloatList.length; i++) {
      int int16 = (audioData[i * 2] | (audioData[i * 2 + 1] << 8));
      if (int16 > 32767) int16 -= 65536;
      audioFloatList[i] = int16 / 32768.0;
    }

    return audioFloatList;
  }

  /// Map language code in isolate
  static String _mapLanguageCodeInIsolate(String languageCode) {
    String cleanCode = languageCode.toLowerCase().trim();
    if (cleanCode.contains('-')) {
      cleanCode = cleanCode.split('-')[0];
    }

    final Map<String, String> languageMap = {
      'en': 'en',
      'bn': 'bn',
      'hi': 'hi',
      'ur': 'ur',
      'es': 'es',
      'fr': 'fr',
      'de': 'de',
      'it': 'it',
      'pt': 'pt',
      'ru': 'ru',
      'ja': 'ja',
      'ko': 'ko',
      'zh': 'zh',
      'ar': 'ar',
      'tr': 'tr',
      'vi': 'vi',
      'th': 'th',
      'id': 'id',
      'ms': 'ms',
      'tl': 'tl',
      'nl': 'nl',
      'pl': 'pl',
      'sv': 'sv',
      'da': 'da',
      'no': 'no',
      'fi': 'fi',
      'el': 'el',
      'he': 'he',
      'cs': 'cs',
      'ro': 'ro',
      'hu': 'hu',
      'uk': 'uk',
    };

    return languageMap[cleanCode] ?? 'en';
  }

  /// Transcribe audio file in specified language
  ///
  /// [audioPath] - Path to the audio file (WAV format, 16kHz, mono)
  /// [languageCode] - ISO language code (e.g., 'en', 'bn', 'es')
  /// Returns transcribed text or empty string if failed
  Future<String> transcribeAudio(String audioPath, String languageCode) async {
    if (!_isInitialized) {
      throw Exception('MultiLangWhisperService not initialized');
    }

    if (_isolateSendPort == null) {
      throw Exception('Transcription isolate not available');
    }

    try {
      debugPrint(
          'MultiLangWhisperService: Transcribing $audioPath in language: $languageCode (using isolate)');

      // Send transcription request to isolate
      final receivePort = ReceivePort();
      _isolateSendPort!.send({
        'type': 'transcribe',
        'audioPath': audioPath,
        'languageCode': languageCode,
        'encoderPath': _encoderModelPath!,
        'decoderPath': _decoderModelPath!,
        'tokensPath': _tokensPath!,
        'replyPort': receivePort.sendPort,
      });

      // Wait for result from isolate
      final result = await receivePort.first as Map<String, dynamic>;

      if (result['success'] == true) {
        final transcription = result['transcription'] as String;
        debugPrint(
            'MultiLangWhisperService: Transcription result: "$transcription"');
        return transcription;
      } else {
        final error = result['error'] as String;
        throw Exception('Transcription failed: $error');
      }
    } catch (e, stackTrace) {
      debugPrint('MultiLangWhisperService: Transcription error: $e');
      debugPrint('MultiLangWhisperService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Cleanup resources
  void dispose() {
    debugPrint('MultiLangWhisperService: Disposing');
    _transcriptionIsolate?.kill();
    _transcriptionIsolate = null;
    _isolateSendPort = null;
    _isInitialized = false;
  }
}
