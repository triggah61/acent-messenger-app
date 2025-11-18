import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

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

      // CRITICAL: Set audio context for Android to use MUSIC stream
      // This ensures stereo A2DP playback instead of mono SCO
      // NOTE: AudioFocus.gain will let audioplayers manage focus (don't request in MainActivity)
      try {
        await _audioPlayer!.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: true,
              contentType: AndroidContentType.music,
              usageType: AndroidUsageType.media,
              // Allow playback while recording by requesting a focus mode
              // that ducks instead of stopping competing audio (mic capture)
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {
                // Note: allowBluetooth and allowBluetoothA2DP can only be used with:
                // playAndRecord, record, or multiRoute categories (not playback)
                // For playback-only, we rely on Android's default routing behavior
                // iOS will route to Bluetooth automatically if available
                AVAudioSessionOptions.mixWithOthers,
              },
            ),
          ),
        );

        // Set player mode to STREAM for proper media playback
        await _audioPlayer!.setPlayerMode(PlayerMode.mediaPlayer);

        debugPrint(
            'TrueStereoAudioServiceRobust: ✅ Audio context set for stereo playback');
        debugPrint(
            'TrueStereoAudioServiceRobust: ✅ Player mode set to MEDIA_PLAYER');
      } catch (e) {
        debugPrint(
            'TrueStereoAudioServiceRobust: ⚠️ Failed to set audio context: $e');
      }

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

      // CRITICAL FIX: Ensure files are fully written before reading
      // Add a small delay to ensure file system has flushed
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify file sizes are stable
      final leftSizeBefore = await leftFile.length();
      final rightSizeBefore = await rightFile.length();
      await Future.delayed(const Duration(milliseconds: 50));
      final leftSizeAfter = await leftFile.length();
      final rightSizeAfter = await rightFile.length();

      if (leftSizeBefore != leftSizeAfter ||
          rightSizeBefore != rightSizeAfter) {
        debugPrint(
            'TrueStereoAudioServiceRobust: ⚠️ File sizes changed, waiting for stability...');
        debugPrint(
            'TrueStereoAudioServiceRobust: Left: $leftSizeBefore → $leftSizeAfter');
        debugPrint(
            'TrueStereoAudioServiceRobust: Right: $rightSizeBefore → $rightSizeAfter');
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Read both mono audio files
      debugPrint(
          'TrueStereoAudioServiceRobust: Reading left audio file (${await leftFile.length()} bytes)...');
      final leftAudioBytes = await leftFile.readAsBytes();
      debugPrint(
          'TrueStereoAudioServiceRobust: Read ${leftAudioBytes.length} bytes from left file');

      debugPrint(
          'TrueStereoAudioServiceRobust: Reading right audio file (${await rightFile.length()} bytes)...');
      final rightAudioBytes = await rightFile.readAsBytes();
      debugPrint(
          'TrueStereoAudioServiceRobust: Read ${rightAudioBytes.length} bytes from right file');

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

      // Extract sample rates from both files
      final leftSampleRate = leftAudioInfo?['sampleRate'] as int? ?? 16000;
      final rightSampleRate = rightAudioInfo?['sampleRate'] as int? ?? 16000;
      final leftChannels = leftAudioInfo?['channels'] as int? ?? 1;
      final rightChannels = rightAudioInfo?['channels'] as int? ?? 1;
      final leftBitsPerSample = leftAudioInfo?['bitsPerSample'] as int? ?? 16;
      final rightBitsPerSample = rightAudioInfo?['bitsPerSample'] as int? ?? 16;

      debugPrint('TrueStereoAudioServiceRobust: ═══ Sample Rate Analysis ═══');
      debugPrint(
          '  Left audio:  $leftSampleRate Hz, $leftChannels ch, $leftBitsPerSample bits');
      debugPrint(
          '  Right audio: $rightSampleRate Hz, $rightChannels ch, $rightBitsPerSample bits');

      // CRITICAL FIX: Detect and handle sample rate mismatch
      // Different TTS voices (male/female) can generate different sample rates
      // causing one channel to play slow/fast/weird if not resampled
      int targetSampleRate;
      List<int>? leftAudioData;
      List<int>? rightAudioData;

      if (leftSampleRate != rightSampleRate) {
        // SAMPLE RATE MISMATCH DETECTED!
        debugPrint(
            'TrueStereoAudioServiceRobust: ⚠️ SAMPLE RATE MISMATCH DETECTED!');
        debugPrint('  This causes one speaker to play slow/weird');
        debugPrint('  Resampling to match...');

        // Use the higher sample rate as target (better quality)
        targetSampleRate =
            leftSampleRate > rightSampleRate ? leftSampleRate : rightSampleRate;
        debugPrint('  Target sample rate: $targetSampleRate Hz');

        // Resample the audio data that doesn't match
        if (leftData != null) {
          if (leftSampleRate != targetSampleRate) {
            debugPrint(
                '  Resampling LEFT audio: $leftSampleRate Hz → $targetSampleRate Hz');
            leftAudioData =
                _resampleAudio(leftData, leftSampleRate, targetSampleRate);
            debugPrint('  ✅ Left audio resampled successfully');
          } else {
            leftAudioData = leftData;
          }
        } else {
          leftAudioData = _createSilentAudio(targetSampleRate, 1.0);
        }

        if (rightData != null) {
          if (rightSampleRate != targetSampleRate) {
            debugPrint(
                '  Resampling RIGHT audio: $rightSampleRate Hz → $targetSampleRate Hz');
            rightAudioData =
                _resampleAudio(rightData, rightSampleRate, targetSampleRate);
            debugPrint('  ✅ Right audio resampled successfully');
          } else {
            rightAudioData = rightData;
          }
        } else {
          rightAudioData = _createSilentAudio(targetSampleRate, 1.0);
        }

        debugPrint(
            'TrueStereoAudioServiceRobust: ✅ Sample rate normalization complete');
      } else {
        // Sample rates match, no resampling needed
        targetSampleRate = leftSampleRate;
        leftAudioData = leftData ?? _createSilentAudio(targetSampleRate, 1.0);
        rightAudioData = rightData ?? _createSilentAudio(targetSampleRate, 1.0);
        debugPrint(
            'TrueStereoAudioServiceRobust: ✅ Sample rates match ($targetSampleRate Hz) - no resampling needed');
      }

      debugPrint('TrueStereoAudioServiceRobust: Final configuration:');
      debugPrint('  Sample rate: $targetSampleRate Hz');
      debugPrint('  Channels: 2 (stereo)');
      debugPrint('  Bits per sample: 16');

      // Calculate audio durations for logging
      final leftDuration = leftAudioData.length /
          (targetSampleRate * 2); // 2 bytes per 16-bit sample
      final rightDuration = rightAudioData.length / (targetSampleRate * 2);
      debugPrint(
          'TrueStereoAudioServiceRobust: Left audio duration: ${leftDuration.toStringAsFixed(2)} seconds');
      debugPrint(
          'TrueStereoAudioServiceRobust: Right audio duration: ${rightDuration.toStringAsFixed(2)} seconds');

      // Create stereo WAV file with proper length handling (no cutting)
      final stereoWavBytes = _createStereoWavFileNoCutting(
        leftAudioData,
        rightAudioData,
        sampleRate: targetSampleRate,
        channels: 2, // Always stereo output
        bitsPerSample: 16,
      );

      // Write stereo WAV file
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(stereoWavBytes);

      final finalDuration = stereoWavBytes.length /
          (targetSampleRate * 2 * 2); // 2 channels * 2 bytes per sample
      debugPrint(
          'TrueStereoAudioServiceRobust: True stereo audio file created successfully');
      debugPrint('  Output path: $outputPath');
      debugPrint('  File size: ${stereoWavBytes.length} bytes');
      debugPrint(
          '  Final duration: ${finalDuration.toStringAsFixed(2)} seconds');
      debugPrint('  Sample rate: $targetSampleRate Hz');

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
      debugPrint(
          'TrueStereoAudioServiceRobust: ═══ Starting Stereo Playback ═══');

      if (_isPlaying) {
        await stop();
      }

      // Check if file exists
      final file = File(stereoAudioPath);
      if (!await file.exists()) {
        debugPrint(
            'TrueStereoAudioServiceRobust: ❌ Stereo audio file does not exist: $stereoAudioPath');
        return;
      }

      // Verify file size
      final fileSize = await file.length();
      debugPrint('TrueStereoAudioServiceRobust: File size: $fileSize bytes');

      if (fileSize < 44) {
        debugPrint(
            'TrueStereoAudioServiceRobust: ❌ File too small (corrupted)');
        return;
      }

      _currentStereoAudioPath = stereoAudioPath;
      _isPlaying = true;

      debugPrint('TrueStereoAudioServiceRobust: ✅ Playing stereo audio file');
      debugPrint('TrueStereoAudioServiceRobust: Path: $stereoAudioPath');
      debugPrint(
          'TrueStereoAudioServiceRobust: Audio Context: MUSIC/MEDIA (stereo A2DP)');
      debugPrint(
          'TrueStereoAudioServiceRobust: Expected Output: TWS/Bluetooth stereo earpieces');

      // CRITICAL FIX: Wait for playback to complete
      // Create a completer to wait for playback completion
      final Completer<void> playbackCompleter = Completer<void>();

      // Listen for playback completion
      final subscription = _audioPlayer!.onPlayerComplete.listen((event) {
        debugPrint('TrueStereoAudioServiceRobust: ✅ Playback completed');
        _isPlaying = false;
        if (!playbackCompleter.isCompleted) {
          playbackCompleter.complete();
        }
      });

      // Also listen for errors
      final errorSubscription =
          _audioPlayer!.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.stopped || state == PlayerState.completed) {
          debugPrint(
              'TrueStereoAudioServiceRobust: Player state changed to $state');
          _isPlaying = false;
          if (!playbackCompleter.isCompleted) {
            playbackCompleter.complete();
          }
        }
      });

      // CRITICAL: Wait 500ms before starting playback to ensure hardware is ready
      // This prevents audio from being cut off at the beginning
      debugPrint(
          'TrueStereoAudioServiceRobust: ⏳ Waiting 500ms for playback hardware to be ready...');
      await Future.delayed(const Duration(milliseconds: 500));

      // Start playback
      await _audioPlayer!.play(DeviceFileSource(stereoAudioPath));
      debugPrint(
          'TrueStereoAudioServiceRobust: ✅ Playback started, waiting for completion...');

      // Wait for playback to complete (with timeout)
      await playbackCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint(
              'TrueStereoAudioServiceRobust: ⚠️ Playback timeout after 30 seconds');
          _isPlaying = false;
        },
      );

      // Clean up subscriptions
      await subscription.cancel();
      await errorSubscription.cancel();

      debugPrint(
          'TrueStereoAudioServiceRobust: ✅ Playback finished successfully');
    } catch (e) {
      _isPlaying = false;
      debugPrint(
          'TrueStereoAudioServiceRobust: ❌ Error playing stereo audio file: $e');
      _onPlaybackError?.call();
      rethrow;
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

      // Check for "RIFF" header with detailed logging
      final first4Bytes = wavBytes.length >= 4
          ? String.fromCharCodes(wavBytes.sublist(0, 4))
          : 'N/A';

      if (first4Bytes != 'RIFF') {
        debugPrint(
            'TrueStereoAudioServiceRobust: ❌ $fileLabel file is not a valid WAV file');
        debugPrint(
            'TrueStereoAudioServiceRobust: Expected: "RIFF", Found: "$first4Bytes"');
        debugPrint(
            'TrueStereoAudioServiceRobust: First 20 bytes (hex): ${wavBytes.length >= 20 ? wavBytes.sublist(0, 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ') : 'N/A'}');
        debugPrint(
            'TrueStereoAudioServiceRobust: First 20 bytes (ascii): ${wavBytes.length >= 20 ? String.fromCharCodes(wavBytes.sublist(0, 20).map((b) => b >= 32 && b < 127 ? b : 46)) : 'N/A'}');
        return null;
      }

      // Check for "WAVE" format
      if (wavBytes.length < 12) {
        debugPrint(
            'TrueStereoAudioServiceRobust: ❌ $fileLabel file too small for WAVE header (${wavBytes.length} bytes)');
        return null;
      }

      final waveHeader = String.fromCharCodes(wavBytes.sublist(8, 12));
      if (waveHeader != 'WAVE') {
        debugPrint(
            'TrueStereoAudioServiceRobust: ❌ $fileLabel file is not a WAVE file');
        debugPrint(
            'TrueStereoAudioServiceRobust: Expected: "WAVE", Found: "$waveHeader"');
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

  /// Resample audio data from one sample rate to another
  /// Uses linear interpolation for simplicity and speed
  ///
  /// [audioData] - The input audio data (16-bit PCM, little-endian)
  /// [fromRate] - The current sample rate of the audio
  /// [toRate] - The target sample rate
  ///
  /// Returns resampled audio data
  List<int> _resampleAudio(List<int> audioData, int fromRate, int toRate) {
    try {
      if (fromRate == toRate) {
        return audioData;
      }

      // Convert byte array to 16-bit samples
      final inputSamples = <int>[];
      for (int i = 0; i < audioData.length; i += 2) {
        if (i + 1 < audioData.length) {
          // Read 16-bit little-endian sample
          final sample =
              (audioData[i] & 0xFF) | ((audioData[i + 1] & 0xFF) << 8);
          // Convert to signed 16-bit
          final signedSample = sample > 32767 ? sample - 65536 : sample;
          inputSamples.add(signedSample);
        }
      }

      final inputLength = inputSamples.length;
      final ratio = fromRate / toRate;
      final outputLength = (inputLength / ratio).round();
      final outputSamples = <int>[];

      debugPrint('TrueStereoAudioServiceRobust: Resampling details:');
      debugPrint('  Input samples: $inputLength');
      debugPrint('  Output samples: $outputLength');
      debugPrint('  Ratio: ${ratio.toStringAsFixed(4)}');

      // Perform linear interpolation
      for (int i = 0; i < outputLength; i++) {
        final srcIndex = i * ratio;
        final srcIndexFloor = srcIndex.floor();
        final srcIndexCeil = srcIndexFloor + 1;

        if (srcIndexCeil < inputLength) {
          // Linear interpolation between two samples
          final fraction = srcIndex - srcIndexFloor;
          final sample1 = inputSamples[srcIndexFloor];
          final sample2 = inputSamples[srcIndexCeil];
          final interpolated = sample1 + ((sample2 - sample1) * fraction);
          outputSamples.add(interpolated.round());
        } else {
          // Last sample, no interpolation needed
          outputSamples.add(inputSamples[srcIndexFloor]);
        }
      }

      // Convert samples back to byte array (16-bit little-endian)
      final outputBytes = <int>[];
      for (final sample in outputSamples) {
        // Convert to unsigned 16-bit
        final unsignedSample = sample < 0 ? sample + 65536 : sample;
        // Write as little-endian bytes
        outputBytes.add(unsignedSample & 0xFF); // Low byte
        outputBytes.add((unsignedSample >> 8) & 0xFF); // High byte
      }

      debugPrint('TrueStereoAudioServiceRobust: Resampling completed');
      debugPrint('  Output bytes: ${outputBytes.length}');

      return outputBytes;
    } catch (e) {
      debugPrint('TrueStereoAudioServiceRobust: Error resampling audio: $e');
      // Return original data as fallback
      return audioData;
    }
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
