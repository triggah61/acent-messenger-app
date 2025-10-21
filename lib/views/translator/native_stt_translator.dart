import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../services/config_service.dart';
import '../../services/permission_service.dart';
import '../../services/multilang_whisper_service.dart';

/// Native STT Translation - Records 2 speakers, performs diarization,
/// and separates audio into individual speaker files for playback
class NativeSTTTranslator extends StatefulWidget {
  const NativeSTTTranslator({super.key});

  @override
  State<NativeSTTTranslator> createState() => _NativeSTTTranslatorState();
}

class _NativeSTTTranslatorState extends State<NativeSTTTranslator>
    with TickerProviderStateMixin {
  // Services
  final ConfigService _configService = ConfigService.instance;
  final PermissionService _permissionService = PermissionService.instance;
  final MultiLangWhisperService _whisperService = MultiLangWhisperService();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _speaker1Player = AudioPlayer();
  final AudioPlayer _speaker2Player = AudioPlayer();

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;

  // Animations
  late Animation<double> _pulseAnimation;

  // Languages
  List<Language> _supportedLanguages = [];

  // Speaker-specific languages (fixed to 2 speakers)
  Map<int, Language> _speakerLanguages = {};
  final int _numberOfSpeakers = 2;
  bool _showSpeakerSetup = true;

  // Recording state
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isInitialized = false;

  // Audio file paths
  String? _recordedAudioPath;
  String? _speaker1AudioPath;
  String? _speaker2AudioPath;

  // Speaker segments from diarization
  List<SpeakerSegment> _speakerSegments = [];

  // Transcription results
  Map<int, String> _transcriptions = {}; // speakerId -> transcribed text

  // Playback state
  bool _isPlayingSpeaker1 = false;
  bool _isPlayingSpeaker2 = false;

  // Processing progress
  double _processingProgress = 0.0;
  String _processingStatus = '';

  // Speaker names
  Map<int, String> _speakerNames = {
    0: 'Speaker 1',
    1: 'Speaker 2',
  };

  // Speaker colors
  final List<Color> _speakerColors = [
    const Color(0xFF00D9FF), // Cyan for Speaker 1
    const Color(0xFFE91E63), // Pink for Speaker 2
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
    _setupAudioPlayers();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeServices() async {
    try {
      // Request microphone permission
      await _permissionService.requestMicrophonePermission();

      // Initialize Whisper STT service
      final whisperInitialized = await _whisperService.initialize();
      if (!whisperInitialized) {
        debugPrint(
            'NativeSTTTranslator: Whisper initialization failed - transcription will be unavailable');
      }

      // Load languages from backend
      final languages = await _configService.getSupportedLanguages();

      final defaultEnglish = languages.firstWhere(
        (lang) => lang.code == 'en',
        orElse: () => languages.first,
      );

      setState(() {
        _supportedLanguages = languages;
        _speakerLanguages = {
          0: defaultEnglish,
          1: defaultEnglish,
        };
        _isInitialized = true;
      });

      debugPrint('NativeSTTTranslator: Services initialized successfully');
    } catch (e) {
      debugPrint('NativeSTTTranslator: Initialization error: $e');
      _showError('Failed to initialize translator: $e');
    }
  }

  void _setupAudioPlayers() {
    // Setup player state listeners
    _speaker1Player.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlayingSpeaker1 = state == PlayerState.playing;
      });
    });

    _speaker2Player.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlayingSpeaker2 = state == PlayerState.playing;
      });
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        // Generate file path for recording
        final Directory appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _recordedAudioPath =
            '${appDir.path}/native_stt_recording_$timestamp.wav';

        debugPrint('NativeSTTTranslator: Recording to: $_recordedAudioPath');

        // Start recording (mono, 16kHz for optimal processing)
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: _recordedAudioPath!,
        );

        setState(() {
          _isRecording = true;
          // Clear previous results
          _speaker1AudioPath = null;
          _speaker2AudioPath = null;
          _speakerSegments = [];
        });

        _pulseController.repeat(reverse: true);
        _waveController.repeat();

        debugPrint('NativeSTTTranslator: Recording started');
      } else {
        _showError('Microphone permission denied');
      }
    } catch (e) {
      debugPrint('NativeSTTTranslator: Error starting recording: $e');
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final String? audioPath = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      _pulseController.stop();
      _pulseController.reset();
      _waveController.stop();

      if (audioPath != null) {
        debugPrint('NativeSTTTranslator: Recording stopped, processing...');
        await _processAudio(audioPath);
      } else {
        _showError('No audio recorded');
      }
    } catch (e) {
      debugPrint('NativeSTTTranslator: Error stopping recording: $e');
      _showError('Failed to stop recording: $e');
    }
  }

  Future<void> _processAudio(String audioPath) async {
    setState(() {
      _isProcessing = true;
      _processingProgress = 0.0;
      _processingStatus = 'Loading audio file...';
    });

    try {
      // Step 1: Load audio file
      final audioFile = File(audioPath);
      final audioBytes = await audioFile.readAsBytes();
      debugPrint(
          'NativeSTTTranslator: Audio file loaded (${audioBytes.length} bytes)');

      setState(() {
        _processingProgress = 0.1;
        _processingStatus = 'Extracting audio features...';
      });

      // Step 2: Perform enhanced speaker diarization
      await _performEnhancedSpeakerDiarization(audioBytes);

      setState(() {
        _processingProgress = 0.7;
        _processingStatus = 'Separating speakers...';
      });

      // Step 3: Separate audio by speaker
      await _separateAudioBySpeaker(audioPath);

      setState(() {
        _processingProgress = 0.75;
        _processingStatus = 'Transcribing audio...';
      });

      // Step 4: Transcribe separated audio files
      await _transcribeSeparatedAudio();

      setState(() {
        _processingProgress = 1.0;
        _processingStatus = 'Processing complete!';
      });

      // Wait a moment before hiding the progress
      await Future.delayed(const Duration(seconds: 1));

      setState(() {
        _isProcessing = false;
      });

      _showSuccess(
          'Audio separated and transcribed successfully! ${_speakerSegments.length} segments found.');
    } catch (e) {
      debugPrint('NativeSTTTranslator: Error processing audio: $e');
      setState(() {
        _isProcessing = false;
      });
      _showError('Failed to process audio: $e');
    }
  }

  /// Enhanced speaker diarization with multiple audio features
  Future<void> _performEnhancedSpeakerDiarization(Uint8List audioBytes) async {
    try {
      debugPrint(
          'NativeSTTTranslator: Performing enhanced speaker diarization...');

      // Convert audio bytes to Float32List for analysis
      final Float32List audioData = _convertBytesToFloat32List(audioBytes);

      // Step 1: Voice Activity Detection (VAD) - Remove silence
      setState(() {
        _processingProgress = 0.15;
        _processingStatus = 'Detecting voice activity...';
      });

      final List<VoiceSegment> voiceSegments = _detectVoiceActivity(audioData);
      debugPrint(
          'NativeSTTTranslator: Found ${voiceSegments.length} voice segments');

      if (voiceSegments.isEmpty) {
        throw Exception('No voice activity detected in recording');
      }

      // Step 2: Extract features from voice segments
      setState(() {
        _processingProgress = 0.25;
        _processingStatus = 'Extracting voice features...';
      });

      final List<VoiceFeatures> allFeatures = [];
      for (final segment in voiceSegments) {
        final features = _extractVoiceFeatures(
            audioData, segment.startSample, segment.endSample);
        features.startTime = segment.startTime;
        features.endTime = segment.endTime;
        allFeatures.add(features);
      }

      debugPrint(
          'NativeSTTTranslator: Extracted features from ${allFeatures.length} segments');

      // Step 3: Cluster features into 2 speakers using k-means
      setState(() {
        _processingProgress = 0.45;
        _processingStatus = 'Identifying speakers...';
      });

      final List<int> speakerLabels = _clusterSpeakers(allFeatures, 2);

      // Step 4: Create speaker segments with proper timing
      setState(() {
        _processingProgress = 0.60;
        _processingStatus = 'Creating speaker segments...';
      });

      final List<SpeakerSegment> segments = [];
      for (int i = 0; i < allFeatures.length; i++) {
        segments.add(SpeakerSegment(
          speakerId: speakerLabels[i],
          startTime: allFeatures[i].startTime,
          endTime: allFeatures[i].endTime,
          confidence:
              _calculateSegmentConfidence(allFeatures, i, speakerLabels),
        ));
      }

      // Step 5: Merge consecutive segments from same speaker
      final List<SpeakerSegment> mergedSegments =
          _mergeConsecutiveSegments(segments);

      setState(() {
        _speakerSegments = mergedSegments;
      });

      debugPrint(
          'NativeSTTTranslator: Created ${mergedSegments.length} final segments');

      // Print segment details for debugging
      for (int i = 0; i < math.min(5, mergedSegments.length); i++) {
        final seg = mergedSegments[i];
        debugPrint(
            '  Segment $i: Speaker ${seg.speakerId}, ${seg.startTime.toStringAsFixed(2)}s - ${seg.endTime.toStringAsFixed(2)}s, confidence: ${seg.confidence.toStringAsFixed(2)}');
      }
    } catch (e) {
      debugPrint('NativeSTTTranslator: Error in speaker diarization: $e');
      rethrow;
    }
  }

  /// Voice Activity Detection - Identifies segments with actual speech
  List<VoiceSegment> _detectVoiceActivity(Float32List audioData) {
    const int windowSize = 400; // 25ms at 16kHz
    const double energyThreshold =
        0.01; // Minimum energy to be considered voice
    const int minSilenceDuration = 8000; // 0.5 seconds of silence
    const int minVoiceDuration = 4800; // 0.3 seconds minimum voice

    final List<VoiceSegment> segments = [];
    bool inVoice = false;
    int voiceStart = 0;
    int silenceCounter = 0;

    for (int i = 0; i < audioData.length; i += windowSize) {
      final int endIdx = math.min(i + windowSize, audioData.length);
      final chunk = Float32List.sublistView(audioData, i, endIdx);

      // Calculate energy for this window
      double energy = 0.0;
      for (final sample in chunk) {
        energy += sample * sample;
      }
      energy = energy / chunk.length;

      if (energy > energyThreshold) {
        // Voice detected
        if (!inVoice) {
          voiceStart = i;
          inVoice = true;
        }
        silenceCounter = 0;
      } else {
        // Silence detected
        if (inVoice) {
          silenceCounter += windowSize;
          if (silenceCounter >= minSilenceDuration) {
            // End of voice segment
            final voiceEnd = i - silenceCounter;
            if (voiceEnd - voiceStart >= minVoiceDuration) {
              segments.add(VoiceSegment(
                startSample: voiceStart,
                endSample: voiceEnd,
                startTime: voiceStart / 16000.0,
                endTime: voiceEnd / 16000.0,
              ));
            }
            inVoice = false;
            silenceCounter = 0;
          }
        }
      }
    }

    // Handle final segment
    if (inVoice && audioData.length - voiceStart >= minVoiceDuration) {
      segments.add(VoiceSegment(
        startSample: voiceStart,
        endSample: audioData.length,
        startTime: voiceStart / 16000.0,
        endTime: audioData.length / 16000.0,
      ));
    }

    return segments;
  }

  /// Extract comprehensive voice features from audio segment
  VoiceFeatures _extractVoiceFeatures(
      Float32List audioData, int startSample, int endSample) {
    final chunk = Float32List.sublistView(
        audioData, startSample, math.min(endSample, audioData.length));

    // 1. Energy (RMS)
    double energy = 0.0;
    for (final sample in chunk) {
      energy += sample * sample;
    }
    energy = math.sqrt(energy / chunk.length);

    // 2. Zero-Crossing Rate (pitch approximation)
    int zeroCrossings = 0;
    for (int i = 1; i < chunk.length; i++) {
      if ((chunk[i] >= 0) != (chunk[i - 1] >= 0)) {
        zeroCrossings++;
      }
    }
    final double zcr = zeroCrossings / chunk.length;

    // 3. Spectral Centroid (brightness of sound)
    final double spectralCentroid = _calculateSpectralCentroid(chunk);

    // 4. Spectral Rolloff (frequency below which 85% of energy is contained)
    final double spectralRolloff = _calculateSpectralRolloff(chunk);

    // 5. Pitch variation (standard deviation of fundamental frequency)
    final double pitchVariation = _calculatePitchVariation(chunk);

    // 6. Energy variation (dynamic range)
    final double energyVariation = _calculateEnergyVariation(chunk);

    return VoiceFeatures(
      energy: energy,
      zeroCrossingRate: zcr,
      spectralCentroid: spectralCentroid,
      spectralRolloff: spectralRolloff,
      pitchVariation: pitchVariation,
      energyVariation: energyVariation,
      startTime: startSample / 16000.0,
      endTime: endSample / 16000.0,
    );
  }

  /// Calculate spectral centroid (brightness)
  double _calculateSpectralCentroid(Float32List chunk) {
    if (chunk.isEmpty) return 0.0;

    // Simple approximation using short-time energy in different frequency bands
    final int bandSize = chunk.length ~/ 4;
    double weightedSum = 0.0;
    double totalEnergy = 0.0;

    for (int band = 0; band < 4; band++) {
      final start = band * bandSize;
      final end = math.min((band + 1) * bandSize, chunk.length);
      double bandEnergy = 0.0;

      for (int i = start; i < end; i++) {
        bandEnergy += chunk[i] * chunk[i];
      }

      weightedSum += bandEnergy * (band + 1);
      totalEnergy += bandEnergy;
    }

    return totalEnergy > 0 ? weightedSum / totalEnergy : 0.0;
  }

  /// Calculate spectral rolloff
  double _calculateSpectralRolloff(Float32List chunk) {
    if (chunk.isEmpty) return 0.0;

    // Calculate cumulative energy
    double totalEnergy = 0.0;
    for (final sample in chunk) {
      totalEnergy += sample * sample;
    }

    final threshold = totalEnergy * 0.85;
    double cumulativeEnergy = 0.0;
    int rolloffIndex = 0;

    for (int i = 0; i < chunk.length; i++) {
      cumulativeEnergy += chunk[i] * chunk[i];
      if (cumulativeEnergy >= threshold) {
        rolloffIndex = i;
        break;
      }
    }

    return rolloffIndex / chunk.length.toDouble();
  }

  /// Calculate pitch variation
  double _calculatePitchVariation(Float32List chunk) {
    if (chunk.length < 100) return 0.0;

    // Calculate short-time ZCR for pitch variation
    const int windowSize = 400;
    final List<double> zcrValues = [];

    for (int i = 0; i < chunk.length - windowSize; i += windowSize ~/ 2) {
      int zeroCrossings = 0;
      for (int j = i + 1; j < i + windowSize && j < chunk.length; j++) {
        if ((chunk[j] >= 0) != (chunk[j - 1] >= 0)) {
          zeroCrossings++;
        }
      }
      zcrValues.add(zeroCrossings / windowSize.toDouble());
    }

    if (zcrValues.isEmpty) return 0.0;

    // Calculate standard deviation
    final mean = zcrValues.reduce((a, b) => a + b) / zcrValues.length;
    double variance = 0.0;
    for (final value in zcrValues) {
      variance += (value - mean) * (value - mean);
    }

    return math.sqrt(variance / zcrValues.length);
  }

  /// Calculate energy variation
  double _calculateEnergyVariation(Float32List chunk) {
    if (chunk.length < 100) return 0.0;

    // Calculate short-time energy variation
    const int windowSize = 400;
    final List<double> energyValues = [];

    for (int i = 0; i < chunk.length - windowSize; i += windowSize ~/ 2) {
      double energy = 0.0;
      for (int j = i; j < i + windowSize && j < chunk.length; j++) {
        energy += chunk[j] * chunk[j];
      }
      energyValues.add(energy / windowSize);
    }

    if (energyValues.isEmpty) return 0.0;

    // Calculate standard deviation
    final mean = energyValues.reduce((a, b) => a + b) / energyValues.length;
    double variance = 0.0;
    for (final value in energyValues) {
      variance += (value - mean) * (value - mean);
    }

    return math.sqrt(variance / energyValues.length);
  }

  /// Cluster features into K speakers using k-means algorithm
  List<int> _clusterSpeakers(List<VoiceFeatures> features, int k) {
    if (features.length < k) {
      // Not enough segments, assign alternating labels
      return List.generate(features.length, (i) => i % k);
    }

    // Normalize features
    final normalized = _normalizeFeatures(features);

    // Initialize centroids: pick first k features as initial centroids
    final List<List<double>> centroids = [];
    final int step = math.max(1, features.length ~/ k);
    for (int i = 0; i < k; i++) {
      final idx = math.min(i * step, features.length - 1);
      centroids.add(List<double>.from(normalized[idx]));
    }

    // K-means iterations
    List<int> labels = List<int>.filled(features.length, 0);
    const int maxIterations = 20;
    bool changed = true;
    int iteration = 0;

    while (changed && iteration < maxIterations) {
      changed = false;
      iteration++;

      // Assignment step: assign each point to nearest centroid
      for (int i = 0; i < normalized.length; i++) {
        double minDist = double.infinity;
        int bestCluster = 0;

        for (int j = 0; j < k; j++) {
          final dist = _euclideanDistance(normalized[i], centroids[j]);
          if (dist < minDist) {
            minDist = dist;
            bestCluster = j;
          }
        }

        if (labels[i] != bestCluster) {
          labels[i] = bestCluster;
          changed = true;
        }
      }

      // Update step: recalculate centroids
      for (int j = 0; j < k; j++) {
        final clusterPoints = <List<double>>[];
        for (int i = 0; i < normalized.length; i++) {
          if (labels[i] == j) {
            clusterPoints.add(normalized[i]);
          }
        }

        if (clusterPoints.isNotEmpty) {
          final int dims = normalized[0].length;
          centroids[j] = List<double>.filled(dims, 0.0);
          for (final point in clusterPoints) {
            for (int d = 0; d < dims; d++) {
              centroids[j][d] += point[d];
            }
          }
          for (int d = 0; d < dims; d++) {
            centroids[j][d] /= clusterPoints.length;
          }
        }
      }

      setState(() {
        _processingProgress = 0.45 + (iteration / maxIterations) * 0.10;
      });
    }

    debugPrint(
        'NativeSTTTranslator: K-means converged after $iteration iterations');
    return labels;
  }

  /// Normalize features to [0, 1] range
  List<List<double>> _normalizeFeatures(List<VoiceFeatures> features) {
    final List<List<double>> raw = features
        .map((f) => [
              f.energy,
              f.zeroCrossingRate,
              f.spectralCentroid,
              f.spectralRolloff,
              f.pitchVariation,
              f.energyVariation,
            ])
        .toList();

    final int dims = raw[0].length;
    final List<double> minVals = List<double>.filled(dims, double.infinity);
    final List<double> maxVals =
        List<double>.filled(dims, double.negativeInfinity);

    // Find min and max for each dimension
    for (final point in raw) {
      for (int d = 0; d < dims; d++) {
        if (point[d] < minVals[d]) minVals[d] = point[d];
        if (point[d] > maxVals[d]) maxVals[d] = point[d];
      }
    }

    // Normalize
    final List<List<double>> normalized = [];
    for (final point in raw) {
      final List<double> normalizedPoint = [];
      for (int d = 0; d < dims; d++) {
        final range = maxVals[d] - minVals[d];
        if (range > 0) {
          normalizedPoint.add((point[d] - minVals[d]) / range);
        } else {
          normalizedPoint.add(0.5); // Default if no variation
        }
      }
      normalized.add(normalizedPoint);
    }

    return normalized;
  }

  /// Calculate Euclidean distance between two feature vectors
  double _euclideanDistance(List<double> a, List<double> b) {
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  /// Calculate confidence score for a segment
  double _calculateSegmentConfidence(
      List<VoiceFeatures> allFeatures, int index, List<int> labels) {
    if (allFeatures.length < 2) return 0.9;

    // Calculate within-cluster distance vs between-cluster distance
    final currentLabel = labels[index];
    final currentFeatures = [
      allFeatures[index].energy,
      allFeatures[index].zeroCrossingRate,
      allFeatures[index].spectralCentroid,
      allFeatures[index].spectralRolloff,
      allFeatures[index].pitchVariation,
      allFeatures[index].energyVariation,
    ];

    // Find average distance to same cluster
    double sameClusterDist = 0.0;
    int sameCount = 0;
    // Find average distance to different cluster
    double diffClusterDist = 0.0;
    int diffCount = 0;

    for (int i = 0; i < allFeatures.length; i++) {
      if (i == index) continue;

      final otherFeatures = [
        allFeatures[i].energy,
        allFeatures[i].zeroCrossingRate,
        allFeatures[i].spectralCentroid,
        allFeatures[i].spectralRolloff,
        allFeatures[i].pitchVariation,
        allFeatures[i].energyVariation,
      ];

      final dist = _euclideanDistance(currentFeatures, otherFeatures);

      if (labels[i] == currentLabel) {
        sameClusterDist += dist;
        sameCount++;
      } else {
        diffClusterDist += dist;
        diffCount++;
      }
    }

    if (sameCount > 0) sameClusterDist /= sameCount;
    if (diffCount > 0) diffClusterDist /= diffCount;

    // Confidence is higher when different cluster is far and same cluster is close
    if (diffClusterDist > 0) {
      final confidence = (diffClusterDist - sameClusterDist) / diffClusterDist;
      return confidence.clamp(0.5, 0.99);
    }

    return 0.85;
  }

  /// Merge consecutive segments from the same speaker
  List<SpeakerSegment> _mergeConsecutiveSegments(
      List<SpeakerSegment> segments) {
    if (segments.isEmpty) return [];

    final List<SpeakerSegment> merged = [];
    SpeakerSegment current = segments[0];

    for (int i = 1; i < segments.length; i++) {
      final next = segments[i];

      // Merge if same speaker and gap is small (< 0.3 seconds)
      if (next.speakerId == current.speakerId &&
          (next.startTime - current.endTime) < 0.3) {
        current = SpeakerSegment(
          speakerId: current.speakerId,
          startTime: current.startTime,
          endTime: next.endTime,
          confidence: (current.confidence + next.confidence) / 2,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);

    return merged;
  }

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

  Future<void> _separateAudioBySpeaker(String originalAudioPath) async {
    try {
      debugPrint('NativeSTTTranslator: Separating audio by speaker...');

      // Read original audio file
      final originalFile = File(originalAudioPath);
      final originalBytes = await originalFile.readAsBytes();

      // Convert to Float32List for processing
      final Float32List audioSamples =
          _convertBytesToFloat32List(originalBytes);

      // Separate by speaker
      final List<int> speaker1Samples = [];
      final List<int> speaker2Samples = [];

      for (final segment in _speakerSegments) {
        final int startSample = (segment.startTime * 16000).round();
        final int endSample =
            (segment.endTime * 16000).round().clamp(0, audioSamples.length);

        for (int i = startSample; i < endSample; i++) {
          if (i < audioSamples.length) {
            // Convert back to int16
            final int16Value =
                (audioSamples[i] * 32767).round().clamp(-32768, 32767);
            final int byte1 = int16Value & 0xFF;
            final int byte2 = (int16Value >> 8) & 0xFF;

            if (segment.speakerId == 0) {
              speaker1Samples.add(byte1);
              speaker1Samples.add(byte2);
            } else {
              speaker2Samples.add(byte1);
              speaker2Samples.add(byte2);
            }
          }
        }

        // Update progress
        setState(() {
          _processingProgress = 0.7 +
              (_speakerSegments.indexOf(segment) / _speakerSegments.length) *
                  0.3;
        });
      }

      // Create separate audio files for each speaker
      final Directory appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Speaker 1 audio file
      if (speaker1Samples.isNotEmpty) {
        _speaker1AudioPath = '${appDir.path}/speaker1_$timestamp.wav';
        final speaker1File = File(_speaker1AudioPath!);
        final speaker1WavHeader = _createWavHeader(speaker1Samples.length);
        await speaker1File
            .writeAsBytes([...speaker1WavHeader, ...speaker1Samples]);
        debugPrint(
            'NativeSTTTranslator: Speaker 1 audio saved (${speaker1Samples.length} bytes)');
      }

      // Speaker 2 audio file
      if (speaker2Samples.isNotEmpty) {
        _speaker2AudioPath = '${appDir.path}/speaker2_$timestamp.wav';
        final speaker2File = File(_speaker2AudioPath!);
        final speaker2WavHeader = _createWavHeader(speaker2Samples.length);
        await speaker2File
            .writeAsBytes([...speaker2WavHeader, ...speaker2Samples]);
        debugPrint(
            'NativeSTTTranslator: Speaker 2 audio saved (${speaker2Samples.length} bytes)');
      }

      setState(() {});
    } catch (e) {
      debugPrint('NativeSTTTranslator: Error separating audio: $e');
      rethrow;
    }
  }

  List<int> _createWavHeader(int dataSize) {
    // Create a simple WAV header for 16kHz, mono, 16-bit PCM
    final List<int> header = List<int>.filled(44, 0);

    // RIFF header
    header[0] = 0x52; // 'R'
    header[1] = 0x49; // 'I'
    header[2] = 0x46; // 'F'
    header[3] = 0x46; // 'F'

    // File size - 8
    final int fileSize = dataSize + 36;
    header[4] = fileSize & 0xFF;
    header[5] = (fileSize >> 8) & 0xFF;
    header[6] = (fileSize >> 16) & 0xFF;
    header[7] = (fileSize >> 24) & 0xFF;

    // WAVE header
    header[8] = 0x57; // 'W'
    header[9] = 0x41; // 'A'
    header[10] = 0x56; // 'V'
    header[11] = 0x45; // 'E'

    // fmt chunk
    header[12] = 0x66; // 'f'
    header[13] = 0x6D; // 'm'
    header[14] = 0x74; // 't'
    header[15] = 0x20; // ' '

    // fmt chunk size (16)
    header[16] = 16;
    header[17] = 0;
    header[18] = 0;
    header[19] = 0;

    // Audio format (1 = PCM)
    header[20] = 1;
    header[21] = 0;

    // Number of channels (1 = mono)
    header[22] = 1;
    header[23] = 0;

    // Sample rate (16000 Hz)
    header[24] = 0x80; // 16000 & 0xFF
    header[25] = 0x3E; // (16000 >> 8) & 0xFF
    header[26] = 0x00;
    header[27] = 0x00;

    // Byte rate (sample rate * channels * bits per sample / 8)
    final int byteRate = 16000 * 1 * 16 ~/ 8;
    header[28] = byteRate & 0xFF;
    header[29] = (byteRate >> 8) & 0xFF;
    header[30] = (byteRate >> 16) & 0xFF;
    header[31] = (byteRate >> 24) & 0xFF;

    // Block align (channels * bits per sample / 8)
    header[32] = 2;
    header[33] = 0;

    // Bits per sample (16)
    header[34] = 16;
    header[35] = 0;

    // data chunk
    header[36] = 0x64; // 'd'
    header[37] = 0x61; // 'a'
    header[38] = 0x74; // 't'
    header[39] = 0x61; // 'a'

    // Data size
    header[40] = dataSize & 0xFF;
    header[41] = (dataSize >> 8) & 0xFF;
    header[42] = (dataSize >> 16) & 0xFF;
    header[43] = (dataSize >> 24) & 0xFF;

    return header;
  }

  /// Transcribe separated audio files using Whisper STT
  Future<void> _transcribeSeparatedAudio() async {
    if (!_whisperService.isInitialized) {
      debugPrint(
          'NativeSTTTranslator: Whisper service not initialized, skipping transcription');
      return;
    }

    try {
      debugPrint(
          'NativeSTTTranslator: Starting transcription for separated audio files...');

      // Clear previous transcriptions
      _transcriptions.clear();

      // Transcribe both speakers concurrently
      final transcriptionTasks = <Future<void>>[];

      // Transcribe Speaker 1
      if (_speaker1AudioPath != null &&
          await File(_speaker1AudioPath!).exists()) {
        final language1 = _speakerLanguages[0];
        if (language1 != null) {
          debugPrint('🎯 NativeSTTTranslator: Speaker 1 Language Details:');
          debugPrint('   - Name: ${language1.name}');
          debugPrint('   - Native Name: ${language1.nativeName}');
          debugPrint('   - Code: "${language1.code}"');
          debugPrint('   - Audio Path: $_speaker1AudioPath');
          transcriptionTasks.add(
              _transcribeSpeakerAudio(0, _speaker1AudioPath!, language1.code));
        }
      }

      // Transcribe Speaker 2
      if (_speaker2AudioPath != null &&
          await File(_speaker2AudioPath!).exists()) {
        final language2 = _speakerLanguages[1];
        if (language2 != null) {
          debugPrint('🎯 NativeSTTTranslator: Speaker 2 Language Details:');
          debugPrint('   - Name: ${language2.name}');
          debugPrint('   - Native Name: ${language2.nativeName}');
          debugPrint('   - Code: "${language2.code}"');
          debugPrint('   - Audio Path: $_speaker2AudioPath');
          transcriptionTasks.add(
              _transcribeSpeakerAudio(1, _speaker2AudioPath!, language2.code));
        }
      }

      // Wait for all transcriptions to complete
      if (transcriptionTasks.isNotEmpty) {
        await Future.wait(transcriptionTasks);
        debugPrint(
            'NativeSTTTranslator: All transcriptions completed successfully');
      } else {
        debugPrint('NativeSTTTranslator: No audio files to transcribe');
      }

      setState(() {});
    } catch (e) {
      debugPrint('NativeSTTTranslator: Error in transcription: $e');
      // Don't throw - transcription is optional, audio separation still succeeded
    }
  }

  /// Transcribe audio for a specific speaker
  Future<void> _transcribeSpeakerAudio(
      int speakerId, String audioPath, String languageCode) async {
    try {
      debugPrint(
          'NativeSTTTranslator: Transcribing Speaker ${speakerId + 1} audio...');

      final transcription =
          await _whisperService.transcribeAudio(audioPath, languageCode);

      if (transcription.isNotEmpty) {
        _transcriptions[speakerId] = transcription;
        debugPrint(
            'NativeSTTTranslator: Speaker ${speakerId + 1} transcription: "$transcription"');
      } else {
        debugPrint(
            'NativeSTTTranslator: No transcription generated for Speaker ${speakerId + 1}');
      }
    } catch (e) {
      debugPrint(
          'NativeSTTTranslator: Error transcribing Speaker ${speakerId + 1}: $e');
      // Don't throw - allow other speaker transcription to continue
    }
  }

  Future<void> _playSpeaker1Audio() async {
    try {
      if (_speaker1AudioPath == null) return;

      if (_isPlayingSpeaker1) {
        await _speaker1Player.pause();
      } else {
        await _speaker1Player.play(DeviceFileSource(_speaker1AudioPath!));
      }
    } catch (e) {
      debugPrint('NativeSTTTranslator: Error playing speaker 1 audio: $e');
      _showError('Failed to play audio: $e');
    }
  }

  Future<void> _playSpeaker2Audio() async {
    try {
      if (_speaker2AudioPath == null) return;

      if (_isPlayingSpeaker2) {
        await _speaker2Player.pause();
      } else {
        await _speaker2Player.play(DeviceFileSource(_speaker2AudioPath!));
      }
    } catch (e) {
      debugPrint('NativeSTTTranslator: Error playing speaker 2 audio: $e');
      _showError('Failed to play audio: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    if (_isRecording) {
      _stopRecording();
    }

    _pulseController.dispose();
    _waveController.dispose();
    _audioRecorder.dispose();
    _speaker1Player.dispose();
    _speaker2Player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D9FF)),
          ),
        ),
      );
    }

    // Show speaker setup screen if not configured
    if (_showSpeakerSetup) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        appBar: _buildAppBar(),
        body: _buildSpeakerSetupScreen(),
      );
    }

    // Show main translator screen
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSpeakerInfoBar(),
          Expanded(child: _buildMainContent()),
          _buildRecordingControls(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Native STT Translation'),
      backgroundColor: const Color(0xFF1D1E33),
      actions: [
        if (!_showSpeakerSetup)
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              setState(() {
                _showSpeakerSetup = true;
              });
            },
          ),
      ],
    );
  }

  Widget _buildSpeakerSetupScreen() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Icon(
              Icons.people,
              size: 80,
              color: Color(0xFF00D9FF),
            ),
            const SizedBox(height: 20),
            const Text(
              'Configure Speakers',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Set up languages for 2 speakers.\nThe system will automatically separate their voices using advanced AI.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ..._buildSpeakerConfigurations(),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _showSpeakerSetup = false;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D9FF),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Start Recording',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSpeakerConfigurations() {
    return List.generate(_numberOfSpeakers, (index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: _buildSpeakerConfig(index),
      );
    });
  }

  Widget _buildSpeakerConfig(int speakerIndex) {
    final speakerColor = _speakerColors[speakerIndex % _speakerColors.length];
    final selectedLanguage =
        _speakerLanguages[speakerIndex] ?? _supportedLanguages.first;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: speakerColor.withValues(alpha: 0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: speakerColor.withValues(alpha: 0.2),
                ),
                child: Icon(Icons.person, color: speakerColor, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                _speakerNames[speakerIndex] ?? 'Speaker ${speakerIndex + 1}',
                style: TextStyle(
                  color: speakerColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Language:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E21),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: speakerColor.withValues(alpha: 0.3), width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Language>(
                value: selectedLanguage,
                dropdownColor: const Color(0xFF1D1E33),
                isExpanded: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                icon: Icon(Icons.arrow_drop_down, color: speakerColor),
                items: _supportedLanguages.map((Language language) {
                  return DropdownMenuItem<Language>(
                    value: language,
                    child: Row(
                      children: [
                        Text(language.nativeName),
                        const SizedBox(width: 8),
                        Text(
                          '(${language.name})',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (Language? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _speakerLanguages[speakerIndex] = newValue;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerInfoBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSpeakerInfo(0),
          Container(width: 2, height: 40, color: Colors.white24),
          _buildSpeakerInfo(1),
        ],
      ),
    );
  }

  Widget _buildSpeakerInfo(int speakerIndex) {
    final speakerColor = _speakerColors[speakerIndex % _speakerColors.length];
    final language = _speakerLanguages[speakerIndex];

    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: speakerColor.withValues(alpha: 0.2),
          ),
          child: Icon(Icons.person, color: speakerColor, size: 18),
        ),
        const SizedBox(height: 4),
        Text(
          _speakerNames[speakerIndex] ?? 'Speaker ${speakerIndex + 1}',
          style: TextStyle(
            color: speakerColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (language != null)
          Text(
            language.nativeName,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
      ],
    );
  }

  Widget _buildMainContent() {
    if (_isProcessing) {
      return _buildProcessingView();
    } else if (_speaker1AudioPath != null && _speaker2AudioPath != null) {
      return _buildResultsView();
    } else {
      return _buildIdleView();
    }
  }

  Widget _buildProcessingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D9FF)),
              strokeWidth: 5,
            ),
            const SizedBox(height: 30),
            Text(
              _processingStatus,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: _processingProgress,
              backgroundColor: Colors.white24,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF00D9FF)),
            ),
            const SizedBox(height: 10),
            Text(
              '${(_processingProgress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Icon(
            Icons.check_circle,
            size: 60,
            color: Colors.green,
          ),
          const SizedBox(height: 16),
          const Text(
            'Audio Separated Successfully!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${_speakerSegments.length} segments found',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          _buildPlaybackButton(
            speakerIndex: 0,
            isPlaying: _isPlayingSpeaker1,
            onTap: _playSpeaker1Audio,
          ),
          const SizedBox(height: 20),
          _buildPlaybackButton(
            speakerIndex: 1,
            isPlaying: _isPlayingSpeaker2,
            onTap: _playSpeaker2Audio,
          ),
          const SizedBox(height: 40),
          _buildSegmentsList(),
        ],
      ),
    );
  }

  Widget _buildPlaybackButton({
    required int speakerIndex,
    required bool isPlaying,
    required VoidCallback onTap,
  }) {
    final speakerColor = _speakerColors[speakerIndex % _speakerColors.length];
    final transcription = _transcriptions[speakerIndex];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isPlaying ? speakerColor : speakerColor.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: isPlaying
              ? [
                  BoxShadow(
                    color: speakerColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: speakerColor.withValues(alpha: 0.2),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: speakerColor,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _speakerNames[speakerIndex] ??
                            'Speaker ${speakerIndex + 1}',
                        style: TextStyle(
                          color: speakerColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isPlaying ? 'Playing...' : 'Tap to play',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.volume_up,
                  color: isPlaying ? speakerColor : Colors.white54,
                  size: 24,
                ),
              ],
            ),
            // Show transcription if available
            if (transcription != null && transcription.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: speakerColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: speakerColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.subtitles,
                          color: speakerColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Transcription:',
                          style: TextStyle(
                            color: speakerColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      transcription,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentsList() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Speaker Segments',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ..._speakerSegments.map((segment) {
            final speakerColor =
                _speakerColors[segment.speakerId % _speakerColors.length];
            final duration = segment.endTime - segment.startTime;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: speakerColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${_speakerNames[segment.speakerId]}: ${segment.startTime.toStringAsFixed(1)}s - ${segment.endTime.toStringAsFixed(1)}s (${duration.toStringAsFixed(1)}s) - ${(segment.confidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildIdleView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic_none,
              size: 100,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 20),
            Text(
              'Ready to Record',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap the microphone button below to start recording.\n\nThe system will automatically identify and separate the 2 speakers using advanced AI.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _isProcessing ? null : _toggleRecording,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isRecording ? _pulseAnimation.value : 1.0,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isRecording
                              ? [
                                  const Color(0xFFE91E63),
                                  const Color(0xFFE91E63)
                                      .withValues(alpha: 0.6),
                                ]
                              : [
                                  const Color(0xFF00D9FF),
                                  const Color(0xFF00D9FF)
                                      .withValues(alpha: 0.6),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording
                                    ? const Color(0xFFE91E63)
                                    : const Color(0xFF00D9FF))
                                .withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isRecording ? 'Tap to stop recording' : 'Tap to start recording',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple speaker segment data class
class SpeakerSegment {
  final int speakerId;
  final double startTime;
  final double endTime;
  final double confidence;

  SpeakerSegment({
    required this.speakerId,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });
}

/// Voice segment from VAD
class VoiceSegment {
  final int startSample;
  final int endSample;
  final double startTime;
  final double endTime;

  VoiceSegment({
    required this.startSample,
    required this.endSample,
    required this.startTime,
    required this.endTime,
  });
}

/// Voice features for speaker identification
class VoiceFeatures {
  final double energy;
  final double zeroCrossingRate;
  final double spectralCentroid;
  final double spectralRolloff;
  final double pitchVariation;
  final double energyVariation;
  double startTime;
  double endTime;

  VoiceFeatures({
    required this.energy,
    required this.zeroCrossingRate,
    required this.spectralCentroid,
    required this.spectralRolloff,
    required this.pitchVariation,
    required this.energyVariation,
    this.startTime = 0.0,
    this.endTime = 0.0,
  });
}
