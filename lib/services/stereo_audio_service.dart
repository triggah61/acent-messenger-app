import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit/ffmpeg_kit.dart';
import 'package:ffmpeg_kit/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';

/// Stereo Audio Service for merging mono TTS audio files into stereo
/// with left and right channel separation for earpiece playback
class StereoAudioService {
  static final StereoAudioService _instance = StereoAudioService._internal();
  factory StereoAudioService() => _instance;
  StereoAudioService._internal();

  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;
  bool _isPlaying = false;
  String? _currentStereoAudioPath;

  /// Initialize the stereo audio service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioPlayer = AudioPlayer();

      // Set up audio player completion handler
      _audioPlayer!.onPlayerComplete.listen((event) {
        _isPlaying = false;
        debugPrint('StereoAudioService: Stereo audio playback completed');
      });

      _isInitialized = true;
      debugPrint('StereoAudioService: Initialized successfully');
    } catch (e) {
      debugPrint('StereoAudioService: Initialization error: $e');
      rethrow;
    }
  }

  /// Create stereo audio file from two mono audio files
  /// Left audio will play on left channel, right audio on right channel
  ///
  /// [leftAudioPath] - Path to the left channel audio file
  /// [rightAudioPath] - Path to the right channel audio file
  /// [outputFileName] - Optional custom output filename (default: auto-generated)
  ///
  /// Returns the path to the created stereo audio file
  Future<String?> createStereoAudioFile(
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
            'StereoAudioService: Left audio file does not exist: $leftAudioPath');
        return null;
      }

      if (!await rightFile.exists()) {
        debugPrint(
            'StereoAudioService: Right audio file does not exist: $rightAudioPath');
        return null;
      }

      // Get temporary directory for processing
      final tempDir = await getTemporaryDirectory();

      // Generate output filename if not provided
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalOutputFileName =
          outputFileName ?? 'stereo_audio_$timestamp.wav';
      final outputPath = '${tempDir.path}/$finalOutputFileName';

      debugPrint('StereoAudioService: Creating stereo audio file...');
      debugPrint('  Left audio: $leftAudioPath');
      debugPrint('  Right audio: $rightAudioPath');
      debugPrint('  Output: $outputPath');

      // FFmpeg command to merge two mono files into stereo
      // Left audio goes to left channel, right audio goes to right channel
      final ffmpegCommand = '-i "$leftAudioPath" -i "$rightAudioPath" '
          '-filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[a]" '
          '-map "[a]" '
          '-acodec pcm_s16le '
          '-ar 44100 '
          '-y '
          '"$outputPath"';

      debugPrint('StereoAudioService: FFmpeg command: $ffmpegCommand');

      // Execute FFmpeg command
      final session = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // Verify output file was created
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          debugPrint(
              'StereoAudioService: Stereo audio file created successfully');
          debugPrint('  Output path: $outputPath');
          debugPrint('  File size: ${fileSize} bytes');
          return outputPath;
        } else {
          debugPrint('StereoAudioService: Output file was not created');
          return null;
        }
      } else {
        final logs = await session.getLogs();
        final errorMessage = logs.map((log) => log.getMessage()).join('\n');
        debugPrint('StereoAudioService: FFmpeg execution failed');
        debugPrint('  Return code: $returnCode');
        debugPrint('  Error logs: $errorMessage');
        return null;
      }
    } catch (e) {
      debugPrint('StereoAudioService: Error creating stereo audio file: $e');
      return null;
    }
  }

  /// Create stereo audio file with enhanced channel separation
  /// This version ensures proper channel isolation and audio quality
  ///
  /// [leftAudioPath] - Path to the left channel audio file
  /// [rightAudioPath] - Path to the right channel audio file
  /// [outputFileName] - Optional custom output filename
  /// [leftVolume] - Volume level for left channel (0.0 to 1.0, default: 1.0)
  /// [rightVolume] - Volume level for right channel (0.0 to 1.0, default: 1.0)
  ///
  /// Returns the path to the created stereo audio file
  Future<String?> createEnhancedStereoAudioFile(
    String leftAudioPath,
    String rightAudioPath, {
    String? outputFileName,
    double leftVolume = 1.0,
    double rightVolume = 1.0,
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
            'StereoAudioService: Left audio file does not exist: $leftAudioPath');
        return null;
      }

      if (!await rightFile.exists()) {
        debugPrint(
            'StereoAudioService: Right audio file does not exist: $rightAudioPath');
        return null;
      }

      // Get temporary directory for processing
      final tempDir = await getTemporaryDirectory();

      // Generate output filename if not provided
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalOutputFileName =
          outputFileName ?? 'enhanced_stereo_audio_$timestamp.wav';
      final outputPath = '${tempDir.path}/$finalOutputFileName';

      debugPrint('StereoAudioService: Creating enhanced stereo audio file...');
      debugPrint('  Left audio: $leftAudioPath (volume: $leftVolume)');
      debugPrint('  Right audio: $rightAudioPath (volume: $rightVolume)');
      debugPrint('  Output: $outputPath');

      // Enhanced FFmpeg command with volume control and better audio processing
      final ffmpegCommand = '-i "$leftAudioPath" -i "$rightAudioPath" '
          '-filter_complex "[0:a]volume=$leftVolume[a0];[1:a]volume=$rightVolume[a1];[a0][a1]join=inputs=2:channel_layout=stereo[a]" '
          '-map "[a]" '
          '-acodec pcm_s16le '
          '-ar 44100 '
          '-ac 2 '
          '-y '
          '"$outputPath"';

      debugPrint('StereoAudioService: Enhanced FFmpeg command: $ffmpegCommand');

      // Execute FFmpeg command
      final session = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        // Verify output file was created
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          debugPrint(
              'StereoAudioService: Enhanced stereo audio file created successfully');
          debugPrint('  Output path: $outputPath');
          debugPrint('  File size: ${fileSize} bytes');
          return outputPath;
        } else {
          debugPrint('StereoAudioService: Output file was not created');
          return null;
        }
      } else {
        final logs = await session.getLogs();
        final errorMessage = logs.map((log) => log.getMessage()).join('\n');
        debugPrint('StereoAudioService: Enhanced FFmpeg execution failed');
        debugPrint('  Return code: $returnCode');
        debugPrint('  Error logs: $errorMessage');
        return null;
      }
    } catch (e) {
      debugPrint(
          'StereoAudioService: Error creating enhanced stereo audio file: $e');
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
            'StereoAudioService: Stereo audio file does not exist: $stereoAudioPath');
        return;
      }

      _currentStereoAudioPath = stereoAudioPath;
      _isPlaying = true;

      debugPrint(
          'StereoAudioService: Playing stereo audio file: $stereoAudioPath');

      // Use AudioPlayer to play the stereo audio file
      await _audioPlayer!.play(DeviceFileSource(stereoAudioPath));
    } catch (e) {
      _isPlaying = false;
      debugPrint('StereoAudioService: Error playing stereo audio file: $e');
    }
  }

  /// Stop current stereo audio playback
  Future<void> stop() async {
    if (!_isInitialized) return;

    try {
      await _audioPlayer!.stop();
      _isPlaying = false;
      _currentStereoAudioPath = null;
      debugPrint('StereoAudioService: Stereo audio playback stopped');
    } catch (e) {
      debugPrint('StereoAudioService: Error stopping stereo audio: $e');
    }
  }

  /// Check if stereo audio is currently playing
  bool get isPlaying => _isPlaying;

  /// Get current stereo audio path
  String? get currentStereoAudioPath => _currentStereoAudioPath;

  /// Get FFmpeg version information
  Future<String?> getFFmpegVersion() async {
    try {
      final session = await FFmpegKit.execute('-version');
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getLogs();
        final versionInfo = logs.map((log) => log.getMessage()).join('\n');
        debugPrint('StereoAudioService: FFmpeg version info: $versionInfo');
        return versionInfo;
      } else {
        debugPrint('StereoAudioService: Failed to get FFmpeg version');
        return null;
      }
    } catch (e) {
      debugPrint('StereoAudioService: Error getting FFmpeg version: $e');
      return null;
    }
  }

  /// Test FFmpeg functionality
  Future<bool> testFFmpegFunctionality() async {
    try {
      debugPrint('StereoAudioService: Testing FFmpeg functionality...');

      // Test with a simple command
      final session = await FFmpegKit.execute(
          '-f lavfi -i testsrc=duration=1:size=320x240:rate=1 -t 1 -f null -');
      final returnCode = await session.getReturnCode();

      final isWorking = ReturnCode.isSuccess(returnCode);
      debugPrint(
          'StereoAudioService: FFmpeg test result: ${isWorking ? "SUCCESS" : "FAILED"}');

      return isWorking;
    } catch (e) {
      debugPrint('StereoAudioService: FFmpeg test error: $e');
      return false;
    }
  }

  /// Clean up temporary audio files
  ///
  /// [filePaths] - List of file paths to clean up
  Future<void> cleanupTempFiles(List<String> filePaths) async {
    try {
      for (final filePath in filePaths) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          debugPrint('StereoAudioService: Cleaned up temp file: $filePath');
        }
      }
    } catch (e) {
      debugPrint('StereoAudioService: Error cleaning up temp files: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _audioPlayer?.stop();
    _audioPlayer = null;
    _isInitialized = false;
    _isPlaying = false;
    _currentStereoAudioPath = null;
    debugPrint('StereoAudioService: Disposed');
  }
}
