import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Service for separating and managing stereo audio channels
class AudioChannelService {
  static final AudioChannelService _instance = AudioChannelService._internal();
  factory AudioChannelService() => _instance;
  AudioChannelService._internal();

  /// Separate stereo WAV file into left and right channel mono files
  Future<ChannelFiles?> separateStereoChannels(String stereoFilePath) async {
    try {
      debugPrint(
          'AudioChannelService: Separating stereo channels from: $stereoFilePath');

      final File stereoFile = File(stereoFilePath);
      if (!await stereoFile.exists()) {
        debugPrint('AudioChannelService: Stereo file does not exist');
        return null;
      }

      // Read the stereo WAV file
      final Uint8List stereoData = await stereoFile.readAsBytes();

      // Parse WAV header
      final wavInfo = _parseWavHeader(stereoData);
      if (wavInfo == null) {
        debugPrint('AudioChannelService: Invalid WAV file format');
        return null;
      }

      debugPrint(
          'AudioChannelService: WAV Info - Channels: ${wavInfo.numChannels}, Sample Rate: ${wavInfo.sampleRate}, Bits: ${wavInfo.bitsPerSample}');

      if (wavInfo.numChannels != 2) {
        debugPrint(
            'AudioChannelService: Not a stereo file (channels: ${wavInfo.numChannels})');
        return null;
      }

      // Extract audio data (skip header)
      final audioData = stereoData.sublist(wavInfo.dataOffset);

      // Separate channels
      final leftChannel = _extractChannel(audioData, 0, wavInfo.bitsPerSample);
      final rightChannel = _extractChannel(audioData, 1, wavInfo.bitsPerSample);

      // Create WAV files for each channel
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final leftFilePath = '${directory.path}/left_mono_$timestamp.wav';
      final rightFilePath = '${directory.path}/right_mono_$timestamp.wav';

      // Write left channel
      final leftWavData = _createMonoWavFile(
          leftChannel, wavInfo.sampleRate, wavInfo.bitsPerSample);
      await File(leftFilePath).writeAsBytes(leftWavData);

      // Write right channel
      final rightWavData = _createMonoWavFile(
          rightChannel, wavInfo.sampleRate, wavInfo.bitsPerSample);
      await File(rightFilePath).writeAsBytes(rightWavData);

      debugPrint('AudioChannelService: Channels separated successfully');
      debugPrint('Left: $leftFilePath');
      debugPrint('Right: $rightFilePath');

      return ChannelFiles(
        leftChannelPath: leftFilePath,
        rightChannelPath: rightFilePath,
      );
    } catch (e) {
      debugPrint('AudioChannelService: Error separating channels: $e');
      return null;
    }
  }

  /// Parse WAV file header
  WavInfo? _parseWavHeader(Uint8List data) {
    try {
      // Check RIFF header
      final riff = String.fromCharCodes(data.sublist(0, 4));
      if (riff != 'RIFF') return null;

      // Check WAVE format
      final wave = String.fromCharCodes(data.sublist(8, 12));
      if (wave != 'WAVE') return null;

      // Find fmt chunk
      int offset = 12;
      while (offset < data.length - 8) {
        final chunkId = String.fromCharCodes(data.sublist(offset, offset + 4));
        final chunkSize = _readInt32(data, offset + 4);

        if (chunkId == 'fmt ') {
          final numChannels = _readInt16(data, offset + 8 + 2);
          final sampleRate = _readInt32(data, offset + 8 + 4);
          final bitsPerSample = _readInt16(data, offset + 8 + 14);

          // Find data chunk
          int dataOffset = offset + 8 + chunkSize;
          while (dataOffset < data.length - 8) {
            final dataChunkId =
                String.fromCharCodes(data.sublist(dataOffset, dataOffset + 4));
            if (dataChunkId == 'data') {
              return WavInfo(
                numChannels: numChannels,
                sampleRate: sampleRate,
                bitsPerSample: bitsPerSample,
                dataOffset: dataOffset + 8,
              );
            }
            final dataChunkSize = _readInt32(data, dataOffset + 4);
            dataOffset += 8 + dataChunkSize;
          }
        }
        offset += 8 + chunkSize;
      }
      return null;
    } catch (e) {
      debugPrint('AudioChannelService: Error parsing WAV header: $e');
      return null;
    }
  }

  /// Extract a specific channel from stereo data
  Uint8List _extractChannel(
      Uint8List stereoData, int channelIndex, int bitsPerSample) {
    final bytesPerSample = bitsPerSample ~/ 8;
    final frameSize = bytesPerSample * 2; // 2 channels
    final numFrames = stereoData.length ~/ frameSize;

    final monoData = Uint8List(numFrames * bytesPerSample);

    for (int i = 0; i < numFrames; i++) {
      final sourceOffset = i * frameSize + (channelIndex * bytesPerSample);
      final destOffset = i * bytesPerSample;

      for (int b = 0; b < bytesPerSample; b++) {
        if (sourceOffset + b < stereoData.length) {
          monoData[destOffset + b] = stereoData[sourceOffset + b];
        }
      }
    }

    return monoData;
  }

  /// Create a mono WAV file from PCM data
  Uint8List _createMonoWavFile(
      Uint8List pcmData, int sampleRate, int bitsPerSample) {
    final bytesPerSample = bitsPerSample ~/ 8;
    final byteRate = sampleRate * bytesPerSample;
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;

    final header = Uint8List(44);

    // RIFF header
    header.setAll(0, 'RIFF'.codeUnits);
    _writeInt32(header, 4, fileSize);
    header.setAll(8, 'WAVE'.codeUnits);

    // fmt chunk
    header.setAll(12, 'fmt '.codeUnits);
    _writeInt32(header, 16, 16); // fmt chunk size
    _writeInt16(header, 20, 1); // PCM format
    _writeInt16(header, 22, 1); // Mono (1 channel)
    _writeInt32(header, 24, sampleRate);
    _writeInt32(header, 28, byteRate);
    _writeInt16(header, 32, bytesPerSample);
    _writeInt16(header, 34, bitsPerSample);

    // data chunk
    header.setAll(36, 'data'.codeUnits);
    _writeInt32(header, 40, dataSize);

    // Combine header and data
    final wavFile = Uint8List(44 + dataSize);
    wavFile.setAll(0, header);
    wavFile.setAll(44, pcmData);

    return wavFile;
  }

  int _readInt16(Uint8List data, int offset) {
    return data[offset] | (data[offset + 1] << 8);
  }

  int _readInt32(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  void _writeInt16(Uint8List data, int offset, int value) {
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
  }

  void _writeInt32(Uint8List data, int offset, int value) {
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
    data[offset + 2] = (value >> 16) & 0xFF;
    data[offset + 3] = (value >> 24) & 0xFF;
  }
}

/// WAV file information
class WavInfo {
  final int numChannels;
  final int sampleRate;
  final int bitsPerSample;
  final int dataOffset;

  WavInfo({
    required this.numChannels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
  });
}

/// Channel file paths
class ChannelFiles {
  final String leftChannelPath;
  final String rightChannelPath;

  ChannelFiles({
    required this.leftChannelPath,
    required this.rightChannelPath,
  });
}
