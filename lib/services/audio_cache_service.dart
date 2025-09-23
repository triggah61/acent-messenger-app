import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

/// Service for caching audio files to avoid regenerating the same TTS audio
class AudioCacheService {
  static final AudioCacheService _instance = AudioCacheService._internal();
  factory AudioCacheService() => _instance;
  AudioCacheService._internal();

  static AudioCacheService get instance => _instance;

  Directory? _cacheDirectory;
  static const String _cacheFolderName = 'tts_cache';
  static const int _maxCacheSize = 100; // Maximum number of cached files
  static const int _maxFileAge = 7; // Days

  /// Initialize the cache service
  Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDirectory = Directory('${appDir.path}/$_cacheFolderName');

      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
        print('AudioCacheService: Created cache directory');
      }

      print('AudioCacheService: Initialized successfully');
    } catch (e) {
      print('AudioCacheService: Initialization failed: $e');
    }
  }

  /// Generate a unique cache key for text and language combination
  String _generateCacheKey(String text, String languageCode, String? voiceId) {
    final input =
        '${text.toLowerCase().trim()}_${languageCode}_${voiceId ?? 'default'}';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Get the cache file path for a given key
  String _getCacheFilePath(String cacheKey) {
    return '${_cacheDirectory!.path}/$cacheKey.mp3';
  }

  /// Check if audio is cached for the given text and language
  Future<bool> isCached(String text, String languageCode,
      {String? voiceId}) async {
    if (_cacheDirectory == null) return false;

    try {
      final cacheKey = _generateCacheKey(text, languageCode, voiceId);
      final filePath = _getCacheFilePath(cacheKey);
      final file = File(filePath);

      if (await file.exists()) {
        // Check if file is not too old
        final stat = await file.stat();
        final age = DateTime.now().difference(stat.modified).inDays;

        if (age <= _maxFileAge) {
          print('AudioCacheService: Cache hit for "$text" in $languageCode');
          return true;
        } else {
          print(
              'AudioCacheService: Cache expired for "$text" in $languageCode');
          await file.delete(); // Remove expired file
          return false;
        }
      }

      return false;
    } catch (e) {
      print('AudioCacheService: Error checking cache: $e');
      return false;
    }
  }

  /// Get cached audio file path
  Future<String?> getCachedAudioPath(String text, String languageCode,
      {String? voiceId}) async {
    if (_cacheDirectory == null) return null;

    try {
      final cacheKey = _generateCacheKey(text, languageCode, voiceId);
      final filePath = _getCacheFilePath(cacheKey);
      final file = File(filePath);

      if (await file.exists()) {
        final stat = await file.stat();
        final age = DateTime.now().difference(stat.modified).inDays;

        if (age <= _maxFileAge) {
          print('AudioCacheService: Returning cached audio: $filePath');
          return filePath;
        } else {
          await file.delete(); // Remove expired file
        }
      }

      return null;
    } catch (e) {
      print('AudioCacheService: Error getting cached audio: $e');
      return null;
    }
  }

  /// Cache audio data for the given text and language
  Future<bool> cacheAudio(String text, String languageCode, List<int> audioData,
      {String? voiceId}) async {
    if (_cacheDirectory == null) return false;

    try {
      // Clean up old cache files if needed
      await _cleanupCache();

      final cacheKey = _generateCacheKey(text, languageCode, voiceId);
      final filePath = _getCacheFilePath(cacheKey);
      final file = File(filePath);

      await file.writeAsBytes(audioData);
      print(
          'AudioCacheService: Cached audio for "$text" in $languageCode (${audioData.length} bytes)');

      return true;
    } catch (e) {
      print('AudioCacheService: Error caching audio: $e');
      return false;
    }
  }

  /// Clean up old cache files
  Future<void> _cleanupCache() async {
    if (_cacheDirectory == null) return;

    try {
      final files = await _cacheDirectory!.list().toList();

      if (files.length <= _maxCacheSize) return;

      // Sort files by modification time (oldest first)
      final sortedFiles = <FileSystemEntity>[];
      for (final file in files) {
        if (file is File && file.path.endsWith('.mp3')) {
          sortedFiles.add(file);
        }
      }

      sortedFiles.sort((a, b) {
        final aStat = (a as File).statSync();
        final bStat = (b as File).statSync();
        return aStat.modified.compareTo(bStat.modified);
      });

      // Remove oldest files if we exceed the limit
      final filesToDelete =
          sortedFiles.length - _maxCacheSize + 10; // Remove 10 extra for buffer
      for (int i = 0; i < filesToDelete && i < sortedFiles.length; i++) {
        await (sortedFiles[i] as File).delete();
        print(
            'AudioCacheService: Removed old cache file: ${sortedFiles[i].path}');
      }

      // Also remove files older than max age
      final cutoffDate = DateTime.now().subtract(Duration(days: _maxFileAge));
      for (final file in sortedFiles) {
        if (file is File) {
          final stat = await file.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await file.delete();
            print(
                'AudioCacheService: Removed expired cache file: ${file.path}');
          }
        }
      }
    } catch (e) {
      print('AudioCacheService: Error cleaning up cache: $e');
    }
  }

  /// Clear all cached audio files
  Future<void> clearCache() async {
    if (_cacheDirectory == null) return;

    try {
      final files = await _cacheDirectory!.list().toList();
      int deletedCount = 0;

      for (final file in files) {
        if (file is File && file.path.endsWith('.mp3')) {
          await file.delete();
          deletedCount++;
        }
      }

      print('AudioCacheService: Cleared $deletedCount cached audio files');
    } catch (e) {
      print('AudioCacheService: Error clearing cache: $e');
    }
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    if (_cacheDirectory == null) {
      return {'error': 'Cache not initialized'};
    }

    try {
      final files = await _cacheDirectory!.list().toList();
      int fileCount = 0;
      int totalSize = 0;

      for (final file in files) {
        if (file is File && file.path.endsWith('.mp3')) {
          fileCount++;
          final stat = await file.stat();
          totalSize += stat.size;
        }
      }

      return {
        'fileCount': fileCount,
        'totalSizeBytes': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'maxFiles': _maxCacheSize,
        'maxAgeDays': _maxFileAge,
      };
    } catch (e) {
      return {'error': 'Failed to get cache stats: $e'};
    }
  }

  /// Dispose the cache service
  Future<void> dispose() async {
    // Cache directory will persist, no need to dispose
    print('AudioCacheService: Disposed');
  }
}
