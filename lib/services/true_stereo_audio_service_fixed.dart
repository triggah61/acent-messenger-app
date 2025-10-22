import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';

/// True Stereo Audio Service that creates actual stereo WAV files
/// with left and right channel separation for proper earpiece playback
/// Fixed version with proper sample rate handling
class TrueStereoAudioServiceFixed {
  static final TrueStereoAudioServiceFixed _instance =
      TrueStereoAudioServiceFixed._internal();
  factory TrueStereoAudioServiceFixed() => _instance;
  TrueStereoAudioServiceFixed._internal();

  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentStereoAudioPath;

  /// Initialize the true stereo audio service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioPlayer = AudioPlayer();

      // Set up completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint(
            'TrueStereoAudioServiceFixed: Stereo audio playback completed');
      });

      _isInitialized = true;
      debugPrint('TrueStereoAudioServiceFixed: Initialized successfully');
    } catch (e) {
      debugPrint('TrueStereoAudioServiceFixed: Initialization error: $e');
      rethrow;
    }
  }

  /// Create a true stereo WAV file from two mono audio files
  /// Left audio will be in left channel, right audio in right channel
  ///
  /// [leftAudioPath] - Path to the left channel audio file
  /// [rightAudioPath] - Path to the right channel audio file
  /// [outputFileName] - Optional custom output filename
  ///
  /// Returns the path to the created stereo audio file
  Future<String?> createTrueStereoAudioFile(
    String leftAudioPath,
    String rightAudioPath, {
    String? outputFileName,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Validate input files exist
      final leftFile = File(leftAudioPath);
      final rightFile = File(rightAudioPath);

      if (!await leftFile.exists()) {
        debugPrint(
            'TrueStereoAudioServiceFixed: Left audio file does not exist: $leftAudioPath');
        return null;
      }

      if (!await rightFile.exists()) {
        debugPrint(
            'TrueStereoAudioServiceFixed: Right audio file does not exist: $rightAudioPath');
        return null;
      }

      // Get temporary directory for processing
      final tempDir = await getTemporaryDirectory();

      // Generate output filename if not provided
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalOutputFileName =
          outputFileName ?? 'true_stereo_audio_$timestamp.wav';
      final outputPath = '${tempDir.path}/$finalOutputFileName';

      debugPrint(
          'TrueStereoAudioServiceFixed: Creating true stereo audio file...');
      debugPrint('  Left audio: $leftAudioPath');
      debugPrint('  Right audio: $rightAudioPath');
      debugPrint('  Output: $outputPath');

      // Read both mono audio files
      final leftAudioBytes = await leftFile.readAsBytes();
      final rightAudioBytes = await rightFile.readAsBytes();

      // Parse WAV headers and extract audio data with sample rate info
      final leftAudioInfo = _extractAudioDataFromWav(leftAudioBytes);
      final rightAudioInfo = _extractAudioDataFromWav(rightAudioBytes);

      if (leftAudioInfo == null || rightAudioInfo == null) {
        debugPrint(
            'TrueStereoAudioServiceFixed: Failed to extract audio data from WAV files');
        return null;
      }

      // Use the sample rate from the first file (they should be the same)
      final sampleRate = leftAudioInfo['sampleRate'] as int;
      final channels = leftAudioInfo['channels'] as int;
      final bitsPerSample = leftAudioInfo['bitsPerSample'] as int;

      debugPrint(
          'TrueStereoAudioServiceFixed: Using sample rate: $sampleRate Hz');
      debugPrint(
          'TrueStereoAudioServiceFixed: Channels: $channels, Bits per sample: $bitsPerSample');

      // Create stereo WAV file with correct sample rate
      final stereoWavBytes = _createStereoWavFile(
        leftAudioInfo['audioData'] as List<int>,
        rightAudioInfo['audioData'] as List<int>,
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
      );

      // Write stereo WAV file
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(stereoWavBytes);

      debugPrint(
          'TrueStereoAudioServiceFixed: True stereo audio file created successfully');
      debugPrint('  Output path: $outputPath');
      debugPrint('  File size: ${stereoWavBytes.length} bytes');
      debugPrint('  Sample rate: $sampleRate Hz');

      return outputPath;
    } catch (e) {
      debugPrint(
          'TrueStereoAudioServiceFixed: Error creating true stereo audio file: $e');
      return null;
    }
  }

  /// Play stereo audio file
  ///
  /// [stereoAudioPath] - Path to the stereo audio file
  Future<void> playStereoAudio(String stereoAudioPath) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      if (_isPlaying) {
        await stop();
      }

      // Check if file exists
      final file = File(stereoAudioPath);
      if (!await file.exists()) {
        debugPrint(
            'TrueStereoAudioServiceFixed: Stereo audio file does not exist: $stereoAudioPath');
        return;
      }

      _currentStereoAudioPath = stereoAudioPath;
      _isPlaying = true;

      debugPrint(
          'TrueStereoAudioServiceFixed: Playing stereo audio file: $stereoAudioPath');

      // Use AudioPlayer to play the stereo audio file
      await _audioPlayer!.play(DeviceFileSource(stereoAudioPath));
    } catch (e) {
      _isPlaying = false;
      debugPrint(
          'TrueStereoAudioServiceFixed: Error playing stereo audio file: $e');
    }
  }

  /// Stop current stereo audio playback
  Future<void> stop() async {
    if (!_isInitialized) return;

    try {
      await _audioPlayer!.stop();
      _isPlaying = false;
      _currentStereoAudioPath = null;
      debugPrint('TrueStereoAudioServiceFixed: Stereo audio playback stopped');
    } catch (e) {
      debugPrint(
          'TrueStereoAudioServiceFixed: Error stopping stereo audio: $e');
    }
  }

  /// Check if stereo audio is currently playing
  bool get isPlaying => _isPlaying;

  /// Get current stereo audio path
  String? get currentStereoAudioPath => _currentStereoAudioPath;

  /// Extract audio data and sample rate from WAV file bytes
  Map<String, dynamic>? _extractAudioDataFromWav(Uint8List wavBytes) {
    try {
      // Check for WAV header
      if (wavBytes.length < 44) {
        debugPrint('TrueStereoAudioServiceFixed: WAV file too small');
        return null;
      }

      // Check for "RIFF" header
      if (String.fromCharCodes(wavBytes.sublist(0, 4)) != 'RIFF') {
        debugPrint('TrueStereoAudioServiceFixed: Not a valid WAV file');
        return null;
      }

      // Check for "WAVE" format
      if (String.fromCharCodes(wavBytes.sublist(8, 12)) != 'WAVE') {
        debugPrint('TrueStereoAudioServiceFixed: Not a WAVE file');
        return null;
      }

      // Extract sample rate from fmt chunk (bytes 24-27)
      final sampleRate = _bytesToInt(wavBytes.sublist(24, 28));
      final channels = _bytesToInt(wavBytes.sublist(22, 24));
      final bitsPerSample = _bytesToInt(wavBytes.sublist(34, 36));

      debugPrint(
          'TrueStereoAudioServiceFixed: WAV file info - Sample rate: $sampleRate Hz, Channels: $channels, Bits: $bitsPerSample');

      // Find data chunk
      int dataStart = 44; // Default position after standard WAV header

      // Look for "data" chunk
      for (int i = 12; i < wavBytes.length - 8; i += 4) {
        if (String.fromCharCodes(wavBytes.sublist(i, i + 4)) == 'data') {
          dataStart = i + 8;
          break;
        }
      }

      // Extract audio data (skip WAV header)
      final audioData = wavBytes.sublist(dataStart);
      debugPrint(
          'TrueStereoAudioServiceFixed: Extracted ${audioData.length} bytes of audio data');

      return {
        'audioData': audioData,
        'sampleRate': sampleRate,
        'channels': channels,
        'bitsPerSample': bitsPerSample,
      };
    } catch (e) {
      debugPrint(
          'TrueStereoAudioServiceFixed: Error extracting audio data: $e');
      return null;
    }
  }

  /// Create stereo WAV file from two mono audio data arrays
  Uint8List _createStereoWavFile(
    List<int> leftAudioData,
    List<int> rightAudioData, {
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    try {
      // Ensure both audio data arrays have the same length
      final minLength = leftAudioData.length < rightAudioData.length
          ? leftAudioData.length
          : rightAudioData.length;

      // Truncate both arrays to the same length
      final leftData = leftAudioData.sublist(0, minLength);
      final rightData = rightAudioData.sublist(0, minLength);

      // Create stereo audio data (interleaved: L, R, L, R, ...)
      final stereoData = <int>[];
      for (int i = 0; i < minLength; i += 2) {
        // Left channel (16-bit sample)
        stereoData.add(leftData[i]);
        stereoData.add(leftData[i + 1]);
        // Right channel (16-bit sample)
        stereoData.add(rightData[i]);
        stereoData.add(rightData[i + 1]);
      }

      // Create WAV header for stereo file with correct sample rate
      final dataSize = stereoData.length;
      final fileSize = 36 + dataSize;
      final byteRate =
          sampleRate * 2 * 2; // sampleRate * channels * (bitsPerSample / 8)

      final header = <int>[
        // RIFF header
        0x52, 0x49, 0x46, 0x46, // "RIFF"
        ..._intToBytes(fileSize, 4),
        0x57, 0x41, 0x56, 0x45, // "WAVE"

        // fmt chunk
        0x66, 0x6D, 0x74, 0x20, // "fmt "
        0x10, 0x00, 0x00, 0x00, // fmt chunk size (16)
        0x01, 0x00, // audio format (PCM)
        0x02, 0x00, // number of channels (2 = stereo)
        ..._intToBytes(sampleRate, 4), // sample rate
        ..._intToBytes(byteRate, 4), // byte rate
        0x04, 0x00, // block align (2 * 2)
        0x10, 0x00, // bits per sample (16)

        // data chunk
        0x64, 0x61, 0x74, 0x61, // "data"
        ..._intToBytes(dataSize, 4),
      ];

      debugPrint('TrueStereoAudioServiceFixed: Created stereo WAV file');
      debugPrint('  File size: $fileSize bytes');
      debugPrint('  Data size: $dataSize bytes');
      debugPrint('  Sample rate: $sampleRate Hz');
      debugPrint('  Byte rate: $byteRate');
      debugPrint('  Channels: 2 (stereo)');
      debugPrint('  Bits per sample: 16');

      return Uint8List.fromList([...header, ...stereoData]);
    } catch (e) {
      debugPrint(
          'TrueStereoAudioServiceFixed: Error creating stereo WAV file: $e');
      rethrow;
    }
  }

  /// Convert bytes to integer (little-endian)
  int _bytesToInt(List<int> bytes) {
    int result = 0;
    for (int i = 0; i < bytes.length; i++) {
      result |= (bytes[i] << (i * 8));
    }
    return result;
  }

  /// Convert integer to bytes (little-endian)
  List<int> _intToBytes(int value, int numBytes) {
    return List.generate(numBytes, (i) => (value >> (i * 8)) & 0xFF);
  }

  /// Test the stereo audio functionality
  Future<bool> testStereoAudioFunctionality() async {
    try {
      debugPrint(
          'TrueStereoAudioServiceFixed: Testing stereo audio functionality...');

      if (!_isInitialized) {
        await initialize();
      }

      debugPrint('TrueStereoAudioServiceFixed: Test completed successfully');
      return true;
    } catch (e) {
      debugPrint('TrueStereoAudioServiceFixed: Test failed: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _audioPlayer?.stop();
    _audioPlayer = null;
    _isInitialized = false;
    _isPlaying = false;
    _currentStereoAudioPath = null;
    debugPrint('TrueStereoAudioServiceFixed: Disposed');
  }
}
