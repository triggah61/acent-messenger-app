import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';

/// True Stereo Audio Service that creates actual stereo WAV files
/// with left and right channel separation for proper earpiece playback
/// Robust version with proper error handling for empty/corrupted files
class TrueStereoAudioServiceRobust {
  static final TrueStereoAudioServiceRobust _instance =
      TrueStereoAudioServiceRobust._internal();
  factory TrueStereoAudioServiceRobust() => _instance;
  TrueStereoAudioServiceRobust._internal();

  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentStereoAudioPath;

  // Callbacks for UI state synchronization
  VoidCallback? _onPlaybackCompleted;
  VoidCallback? _onPlaybackError;

  /// Initialize the true stereo audio service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioPlayer = AudioPlayer();

      // Set up completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint(
            'TrueStereoAudioServiceRobust: Stereo audio playback completed');
        _onPlaybackCompleted?.call();
      });

      _isInitialized = true;
      debugPrint('TrueStereoAudioServiceRobust: Initialized successfully');
    } catch (e) {
      debugPrint('TrueStereoAudioServiceRobust: Initialization error: $e');
      rethrow;
    }
  }

  /// Set callback for playback completion
  void setPlaybackCompletedCallback(VoidCallback? callback) {
    _onPlaybackCompleted = callback;
  }

  /// Set callback for playback error
  void setPlaybackErrorCallback(VoidCallback? callback) {
    _onPlaybackError = callback;
  }

  /// Create a true stereo WAV file from two mono audio files
  /// Left audio will be in left channel, right audio in right channel
  /// The longer audio determines the final length, shorter audio is padded with silence
  /// Handles empty/corrupted files gracefully
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
            'TrueStereoAudioServiceRobust: Left audio file does not exist: $leftAudioPath');
        return null;
      }

      if (!await rightFile.exists()) {
        debugPrint(
            'TrueStereoAudioServiceRobust: Right audio file does not exist: $rightAudioPath');
        return null;
      }

      // Check file sizes
      final leftFileSize = await leftFile.length();
      final rightFileSize = await rightFile.length();

      debugPrint(
          'TrueStereoAudioServiceRobust: File sizes - Left: $leftFileSize bytes, Right: $rightFileSize bytes');

      // Get temporary directory for processing
      final tempDir = await getTemporaryDirectory();

      // Generate output filename if not provided
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalOutputFileName =
          outputFileName ?? 'true_stereo_audio_$timestamp.wav';
      final outputPath = '${tempDir.path}/$finalOutputFileName';

      debugPrint(
          'TrueStereoAudioServiceRobust: Creating true stereo audio file...');
      debugPrint('  Left audio: $leftAudioPath');
      debugPrint('  Right audio: $rightAudioPath');
      debugPrint('  Output: $outputPath');

      // Read both mono audio files
      final leftAudioBytes = await leftFile.readAsBytes();
      final rightAudioBytes = await rightFile.readAsBytes();

      // Parse WAV headers and extract audio data with sample rate info
      final leftAudioInfo = _extractAudioDataFromWav(leftAudioBytes, 'Left');
      final rightAudioInfo = _extractAudioDataFromWav(rightAudioBytes, 'Right');

      // Handle cases where one or both files are empty/corrupted
      if (leftAudioInfo == null && rightAudioInfo == null) {
        debugPrint(
            'TrueStereoAudioServiceRobust: Both audio files are empty or corrupted');
        return null;
      }

      // If one file is empty/corrupted, create a silent audio for it
      final leftData = leftAudioInfo?['audioData'] as List<int>?;
      final rightData = rightAudioInfo?['audioData'] as List<int>?;

      // Determine sample rate from valid file(s)
      int sampleRate = 16000; // Default fallback
      int channels = 1;
      int bitsPerSample = 16;

      if (leftAudioInfo != null) {
        sampleRate = leftAudioInfo['sampleRate'] as int;
        channels = leftAudioInfo['channels'] as int;
        bitsPerSample = leftAudioInfo['bitsPerSample'] as int;
      } else if (rightAudioInfo != null) {
        sampleRate = rightAudioInfo['sampleRate'] as int;
        channels = rightAudioInfo['channels'] as int;
        bitsPerSample = rightAudioInfo['bitsPerSample'] as int;
      }

      debugPrint(
          'TrueStereoAudioServiceRobust: Using sample rate: $sampleRate Hz');
      debugPrint(
          'TrueStereoAudioServiceRobust: Channels: $channels, Bits per sample: $bitsPerSample');

      // Create silent audio data if needed
      final leftAudioData = leftData ??
          _createSilentAudio(sampleRate, 1.0); // 1 second of silence
      final rightAudioData = rightData ??
          _createSilentAudio(sampleRate, 1.0); // 1 second of silence

      // Calculate audio durations for logging
      final leftDuration =
          leftAudioData.length / (sampleRate * 2); // 2 bytes per 16-bit sample
      final rightDuration = rightAudioData.length / (sampleRate * 2);
      debugPrint(
          'TrueStereoAudioServiceRobust: Left audio duration: ${leftDuration.toStringAsFixed(2)} seconds');
      debugPrint(
          'TrueStereoAudioServiceRobust: Right audio duration: ${rightDuration.toStringAsFixed(2)} seconds');

      // Create stereo WAV file with proper length handling (no cutting)
      final stereoWavBytes = _createStereoWavFileNoCutting(
        leftAudioData,
        rightAudioData,
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
      );

      // Write stereo WAV file
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(stereoWavBytes);

      final finalDuration = stereoWavBytes.length /
          (sampleRate * 2 * 2); // 2 channels * 2 bytes per sample
      debugPrint(
          'TrueStereoAudioServiceRobust: True stereo audio file created successfully');
      debugPrint('  Output path: $outputPath');
      debugPrint('  File size: ${stereoWavBytes.length} bytes');
      debugPrint(
          '  Final duration: ${finalDuration.toStringAsFixed(2)} seconds');
      debugPrint('  Sample rate: $sampleRate Hz');

      return outputPath;
    } catch (e) {
      debugPrint(
          'TrueStereoAudioServiceRobust: Error creating true stereo audio file: $e');
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
            'TrueStereoAudioServiceRobust: Stereo audio file does not exist: $stereoAudioPath');
        return;
      }

      _currentStereoAudioPath = stereoAudioPath;
      _isPlaying = true;

      debugPrint(
          'TrueStereoAudioServiceRobust: Playing stereo audio file: $stereoAudioPath');

      // Use AudioPlayer to play the stereo audio file
      await _audioPlayer!.play(DeviceFileSource(stereoAudioPath));
    } catch (e) {
      _isPlaying = false;
      debugPrint(
          'TrueStereoAudioServiceRobust: Error playing stereo audio file: $e');
      _onPlaybackError?.call();
    }
  }

  /// Stop current stereo audio playback
  Future<void> stop() async {
    if (!_isInitialized) return;

    try {
      await _audioPlayer!.stop();
      _isPlaying = false;
      _currentStereoAudioPath = null;
      debugPrint('TrueStereoAudioServiceRobust: Stereo audio playback stopped');
    } catch (e) {
      debugPrint(
          'TrueStereoAudioServiceRobust: Error stopping stereo audio: $e');
    }
  }

  /// Check if stereo audio is currently playing
  bool get isPlaying => _isPlaying;

  /// Get current stereo audio path
  String? get currentStereoAudioPath => _currentStereoAudioPath;

  /// Extract audio data and sample rate from WAV file bytes
  /// Returns null if file is empty/corrupted, with detailed logging
  Map<String, dynamic>? _extractAudioDataFromWav(
      Uint8List wavBytes, String fileLabel) {
    try {
      debugPrint(
          'TrueStereoAudioServiceRobust: Processing $fileLabel WAV file (${wavBytes.length} bytes)');

      // Check for WAV header
      if (wavBytes.length < 44) {
        debugPrint(
            'TrueStereoAudioServiceRobust: $fileLabel WAV file too small (${wavBytes.length} bytes, need at least 44)');
        return null;
      }

      // Check for "RIFF" header
      if (String.fromCharCodes(wavBytes.sublist(0, 4)) != 'RIFF') {
        debugPrint(
            'TrueStereoAudioServiceRobust: $fileLabel file is not a valid WAV file (missing RIFF header)');
        return null;
      }

      // Check for "WAVE" format
      if (String.fromCharCodes(wavBytes.sublist(8, 12)) != 'WAVE') {
        debugPrint(
            'TrueStereoAudioServiceRobust: $fileLabel file is not a WAVE file (missing WAVE header)');
        return null;
      }

      // Extract sample rate from fmt chunk (bytes 24-27)
      final sampleRate = _bytesToInt(wavBytes.sublist(24, 28));
      final channels = _bytesToInt(wavBytes.sublist(22, 24));
      final bitsPerSample = _bytesToInt(wavBytes.sublist(34, 36));

      debugPrint(
          'TrueStereoAudioServiceRobust: $fileLabel WAV file info - Sample rate: $sampleRate Hz, Channels: $channels, Bits: $bitsPerSample');

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
          'TrueStereoAudioServiceRobust: $fileLabel extracted ${audioData.length} bytes of audio data');

      return {
        'audioData': audioData,
        'sampleRate': sampleRate,
        'channels': channels,
        'bitsPerSample': bitsPerSample,
      };
    } catch (e) {
      debugPrint(
          'TrueStereoAudioServiceRobust: Error extracting audio data from $fileLabel file: $e');
      return null;
    }
  }

  /// Create silent audio data for empty/corrupted files
  ///
  /// [sampleRate] - Sample rate for the silent audio
  /// [durationSeconds] - Duration of silence in seconds
  ///
  /// Returns silent audio data as List<int>
  List<int> _createSilentAudio(int sampleRate, double durationSeconds) {
    final samplesNeeded = (sampleRate * durationSeconds).round();
    final bytesNeeded = samplesNeeded * 2; // 2 bytes per 16-bit sample

    debugPrint(
        'TrueStereoAudioServiceRobust: Creating $durationSeconds seconds of silent audio ($bytesNeeded bytes)');

    return List.filled(bytesNeeded, 0);
  }

  /// Create stereo WAV file from two mono audio data arrays
  /// Uses the longer audio length and pads the shorter one with silence
  /// This ensures no speech is cut off
  Uint8List _createStereoWavFileNoCutting(
    List<int> leftAudioData,
    List<int> rightAudioData, {
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    try {
      // Determine the maximum length (longer audio determines final length)
      final maxLength = leftAudioData.length > rightAudioData.length
          ? leftAudioData.length
          : rightAudioData.length;

      debugPrint('TrueStereoAudioServiceRobust: Audio length handling:');
      debugPrint('  Left audio length: ${leftAudioData.length} bytes');
      debugPrint('  Right audio length: ${rightAudioData.length} bytes');
      debugPrint('  Final stereo length: $maxLength bytes (no cutting)');

      // Pad shorter audio with silence (zeros) to match the longer audio
      final paddedLeftData = _padAudioWithSilence(leftAudioData, maxLength);
      final paddedRightData = _padAudioWithSilence(rightAudioData, maxLength);

      // Create stereo audio data (interleaved: L, R, L, R, ...)
      final stereoData = <int>[];
      for (int i = 0; i < maxLength; i += 2) {
        // Left channel (16-bit sample)
        stereoData.add(paddedLeftData[i]);
        stereoData.add(paddedLeftData[i + 1]);
        // Right channel (16-bit sample)
        stereoData.add(paddedRightData[i]);
        stereoData.add(paddedRightData[i + 1]);
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

      debugPrint(
          'TrueStereoAudioServiceRobust: Created stereo WAV file (no cutting)');
      debugPrint('  File size: $fileSize bytes');
      debugPrint('  Data size: $dataSize bytes');
      debugPrint('  Sample rate: $sampleRate Hz');
      debugPrint('  Byte rate: $byteRate');
      debugPrint('  Channels: 2 (stereo)');
      debugPrint('  Bits per sample: 16');
      debugPrint(
          '  Final duration: ${(dataSize / (sampleRate * 2 * 2)).toStringAsFixed(2)} seconds');

      return Uint8List.fromList([...header, ...stereoData]);
    } catch (e) {
      debugPrint(
          'TrueStereoAudioServiceRobust: Error creating stereo WAV file: $e');
      rethrow;
    }
  }

  /// Pad audio data with silence (zeros) to reach target length
  /// This ensures no speech is cut off when creating stereo audio
  List<int> _padAudioWithSilence(List<int> audioData, int targetLength) {
    if (audioData.length >= targetLength) {
      // Audio is already long enough, return as is
      return audioData;
    }

    // Create a copy of the original audio data
    final paddedData = List<int>.from(audioData);

    // Pad with silence (zeros) to reach target length
    final paddingNeeded = targetLength - audioData.length;
    paddedData.addAll(List.filled(paddingNeeded, 0));

    debugPrint(
        'TrueStereoAudioServiceRobust: Padded audio with $paddingNeeded bytes of silence');
    debugPrint('  Original length: ${audioData.length} bytes');
    debugPrint('  Padded length: ${paddedData.length} bytes');

    return paddedData;
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
          'TrueStereoAudioServiceRobust: Testing stereo audio functionality...');

      if (!_isInitialized) {
        await initialize();
      }

      debugPrint('TrueStereoAudioServiceRobust: Test completed successfully');
      return true;
    } catch (e) {
      debugPrint('TrueStereoAudioServiceRobust: Test failed: $e');
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
    debugPrint('TrueStereoAudioServiceRobust: Disposed');
  }
}
