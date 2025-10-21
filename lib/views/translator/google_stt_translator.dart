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
import '../../services/google_stt_service.dart';
import '../../services/translation_service.dart';

/// Google STT Translation - Records 2 speakers, performs on-device diarization,
/// and separates audio into individual speaker files for playback
class GoogleSTTTranslator extends StatefulWidget {
  const GoogleSTTTranslator({super.key});

  @override
  State<GoogleSTTTranslator> createState() => _GoogleSTTTranslatorState();
}

class _GoogleSTTTranslatorState extends State<GoogleSTTTranslator>
    with TickerProviderStateMixin {
  // Services
  final ConfigService _configService = ConfigService.instance;
  final PermissionService _permissionService = PermissionService.instance;
  final GoogleSttService _googleSttService = GoogleSttService();
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
  bool _isStartingSession = false;

  // Audio paths
  String? _recordedAudioPath;
  String? _speaker1AudioPath;
  String? _speaker2AudioPath;

  // Speaker segments from diarization
  List<SpeakerSegment> _speakerSegments = [];

  // Transcription results
  Map<int, String> _transcriptions = {}; // speakerId -> transcribed text
  Map<int, String> _translations = {}; // speakerId -> translated text

  // Playback state
  bool _isPlayingSpeaker1 = false;
  bool _isPlayingSpeaker2 = false;

  // Translation toggle state
  Map<int, bool> _showTranslation = {}; // speakerId -> show translation

  // Processing progress
  double _processingProgress = 0.0;
  String _processingStatus = '';

  // Speaker names and colors
  final List<String> _speakerNames = ['Speaker 1', 'Speaker 2'];
  final List<Color> _speakerColors = [
    const Color(0xFF00D9FF), // Cyan
    const Color(0xFFE91E63), // Pink
  ];

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupAudioPlayers();
    _initializeAnimations();
  }

  Future<void> _initializeServices() async {
    try {
      await _googleSttService.initialize();
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
        _showTranslation = {
          0: false, // Show original transcription by default
          1: false,
        };
        _isInitialized = true;
      });

      debugPrint('GoogleSTTTranslator: Services initialized successfully');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Initialization error: $e');
      _showErrorDialog('Failed to initialize translator: $e');
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

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  Future<void> _startRecordingSession() async {
    // Validate speaker configuration
    if (_speakerLanguages.isEmpty || _speakerLanguages.length < 2) {
      _showErrorDialog('Please configure languages for both speakers first.');
      return;
    }

    // Check if both speakers have valid languages
    if (_speakerLanguages[0] == null || _speakerLanguages[1] == null) {
      _showErrorDialog('Please select languages for both speakers.');
      return;
    }

    // Set loading state
    setState(() {
      _isStartingSession = true;
    });

    // Add a small delay to show the loading state
    await Future.delayed(const Duration(milliseconds: 300));

    // Transition to main recording screen
    setState(() {
      _showSpeakerSetup = false;
      _isStartingSession = false;
    });

    debugPrint(
        'GoogleSTTTranslator: Successfully transitioned to recording screen');
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
      final hasPermission =
          await _permissionService.requestMicrophonePermission();
      if (!hasPermission) {
        _showErrorDialog('Microphone permission is required for recording.');
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordedAudioPath = '${directory.path}/recording_$timestamp.wav';

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
        _transcriptions.clear();
        _translations.clear();
        _showTranslation = {
          0: false,
          1: false,
        };
      });

      _pulseController.repeat(reverse: true);
      _waveController.repeat();

      debugPrint('GoogleSTTTranslator: Recording started');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Recording error: $e');
      _showErrorDialog('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      _pulseController.stop();
      _waveController.stop();

      debugPrint(
          'GoogleSTTTranslator: Recording stopped, starting processing...');
      await _processAudio();
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Stop recording error: $e');
      _showErrorDialog('Failed to stop recording: $e');
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
    }
  }

  Future<void> _processAudio() async {
    if (_recordedAudioPath == null) return;

    try {
      setState(() {
        _processingProgress = 0.1;
        _processingStatus = 'Reading audio file...';
      });

      // Read audio file
      final audioFile = File(_recordedAudioPath!);
      final audioBytes = await audioFile.readAsBytes();

      setState(() {
        _processingProgress = 0.3;
        _processingStatus = 'Performing on-device speaker diarization...';
      });

      // Step 2: Perform enhanced speaker diarization (on-device)
      await _performEnhancedSpeakerDiarization(audioBytes);

      setState(() {
        _processingProgress = 0.7;
        _processingStatus = 'Separating speakers...';
      });

      // Step 3: Separate audio by speakers
      await _separateAudioBySpeaker();

      setState(() {
        _processingProgress = 0.8;
        _processingStatus = 'Transcribing audio...';
      });

      // Step 4: Transcribe separated audio using Google STT
      await _transcribeSeparatedAudio();

      setState(() {
        _processingProgress = 1.0;
        _processingStatus = 'Complete!';
        _isProcessing = false;
      });

      debugPrint('GoogleSTTTranslator: Processing completed successfully');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Processing error: $e');
      _showErrorDialog('Audio processing failed: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Enhanced speaker diarization with multiple audio features (on-device)
  Future<void> _performEnhancedSpeakerDiarization(Uint8List audioBytes) async {
    try {
      debugPrint(
          'GoogleSTTTranslator: Performing enhanced speaker diarization...');

      // Convert audio bytes to Float32List for analysis
      final Float32List audioData = _convertBytesToFloat32List(audioBytes);

      // Step 1: Voice Activity Detection (VAD) - Remove silence
      setState(() {
        _processingProgress = 0.15;
        _processingStatus = 'Detecting voice activity...';
      });

      final List<VoiceSegment> voiceSegments = _detectVoiceActivity(audioData);
      debugPrint(
          'GoogleSTTTranslator: Found ${voiceSegments.length} voice segments');

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
          'GoogleSTTTranslator: Extracted features from ${allFeatures.length} segments');

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
          'GoogleSTTTranslator: Created ${mergedSegments.length} final segments');

      // Print segment details for debugging
      for (int i = 0; i < math.min(5, mergedSegments.length); i++) {
        final seg = mergedSegments[i];
        debugPrint(
            '  Segment $i: Speaker ${seg.speakerId}, ${seg.startTime.toStringAsFixed(2)}s - ${seg.endTime.toStringAsFixed(2)}s, confidence: ${seg.confidence.toStringAsFixed(2)}');
      }
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Error in speaker diarization: $e');
      rethrow;
    }
  }

  Future<void> _separateAudioBySpeaker() async {
    if (_recordedAudioPath == null || _speakerSegments.isEmpty) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Create separate audio files for each speaker
      _speaker1AudioPath = '${directory.path}/speaker1_$timestamp.wav';
      _speaker2AudioPath = '${directory.path}/speaker2_$timestamp.wav';

      // Read original audio file
      final originalFile = File(_recordedAudioPath!);
      final originalBytes = await originalFile.readAsBytes();

      // Convert to Float32List for processing
      final Float32List audioData = _convertBytesToFloat32List(originalBytes);

      // Create speaker-specific audio files
      await _createSpeakerAudioFile(audioData, _speaker1AudioPath!, 0);
      await _createSpeakerAudioFile(audioData, _speaker2AudioPath!, 1);

      debugPrint('GoogleSTTTranslator: Audio separation completed');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Audio separation error: $e');
      rethrow;
    }
  }

  Future<void> _createSpeakerAudioFile(
      Float32List audioData, String outputPath, int speakerId) async {
    // Find all segments for this speaker
    final speakerSegments =
        _speakerSegments.where((seg) => seg.speakerId == speakerId).toList();

    if (speakerSegments.isEmpty) {
      // Create empty file if no segments for this speaker
      await File(outputPath).writeAsBytes(_createEmptyWavFile());
      return;
    }

    // Calculate total duration and create output buffer
    final double totalDuration = speakerSegments
        .map((s) => s.endTime - s.startTime)
        .reduce((a, b) => a + b);
    final int totalSamples = (totalDuration * 16000).round();
    final Float32List outputData = Float32List(totalSamples);

    int outputIndex = 0;
    for (final segment in speakerSegments) {
      final int startSample = (segment.startTime * 16000).round();
      final int endSample = (segment.endTime * 16000).round();
      final int segmentLength = endSample - startSample;

      if (startSample < audioData.length && endSample <= audioData.length) {
        for (int i = 0; i < segmentLength && outputIndex < totalSamples; i++) {
          outputData[outputIndex++] = audioData[startSample + i];
        }
      }
    }

    // Convert back to bytes and write WAV file
    final Uint8List outputBytes = _convertFloat32ListToBytes(outputData);
    await File(outputPath).writeAsBytes(outputBytes);
  }

  Future<void> _transcribeSeparatedAudio() async {
    try {
      debugPrint(
          'GoogleSTTTranslator: Starting transcription of separated audio...');

      // Transcribe Speaker 1 audio
      if (_speaker1AudioPath != null &&
          await File(_speaker1AudioPath!).exists()) {
        final speaker1Language = _speakerLanguages[0];
        final speaker1LanguageCode =
            _mapLanguageToGoogleCode(speaker1Language?.code ?? 'en');

        debugPrint(
            'GoogleSTTTranslator: Transcribing Speaker 1 in language: $speaker1LanguageCode');

        final audioBytes = await File(_speaker1AudioPath!).readAsBytes();
        final result1 = await _googleSttService.transcribeWithDiarization(
          audioBytes: audioBytes,
          languageCode: speaker1LanguageCode,
          minSpeakers: 1,
          maxSpeakers: 1,
        );

        if (result1 != null) {
          debugPrint(
              'GoogleSTTTranslator: Speaker 1 result - fullTranscript: "${result1.fullTranscript}"');
          debugPrint(
              'GoogleSTTTranslator: Speaker 1 result - segments: ${result1.segments.length}');
          if (result1.segments.isNotEmpty) {
            debugPrint(
                'GoogleSTTTranslator: Speaker 1 segments: ${result1.segments.map((s) => s.text).toList()}');
          }

          // Use fullTranscript if available, otherwise combine segments
          if (result1.fullTranscript.isNotEmpty) {
            _transcriptions[0] = result1.fullTranscript;
            debugPrint(
                'GoogleSTTTranslator: Stored Speaker 1 fullTranscript: "${result1.fullTranscript}"');
          } else if (result1.segments.isNotEmpty) {
            _transcriptions[0] = result1.segments.map((s) => s.text).join(' ');
            debugPrint(
                'GoogleSTTTranslator: Stored Speaker 1 from segments: "${_transcriptions[0]}"');
          }
        }
      }

      // Transcribe Speaker 2 audio
      if (_speaker2AudioPath != null &&
          await File(_speaker2AudioPath!).exists()) {
        final speaker2Language = _speakerLanguages[1];
        final speaker2LanguageCode =
            _mapLanguageToGoogleCode(speaker2Language?.code ?? 'en');

        debugPrint(
            'GoogleSTTTranslator: Transcribing Speaker 2 in language: $speaker2LanguageCode');

        final audioBytes = await File(_speaker2AudioPath!).readAsBytes();
        final result2 = await _googleSttService.transcribeWithDiarization(
          audioBytes: audioBytes,
          languageCode: speaker2LanguageCode,
          minSpeakers: 1,
          maxSpeakers: 1,
        );

        if (result2 != null) {
          debugPrint(
              'GoogleSTTTranslator: Speaker 2 result - fullTranscript: "${result2.fullTranscript}"');
          debugPrint(
              'GoogleSTTTranslator: Speaker 2 result - segments: ${result2.segments.length}');
          if (result2.segments.isNotEmpty) {
            debugPrint(
                'GoogleSTTTranslator: Speaker 2 segments: ${result2.segments.map((s) => s.text).toList()}');
          }

          // Use fullTranscript if available, otherwise combine segments
          if (result2.fullTranscript.isNotEmpty) {
            _transcriptions[1] = result2.fullTranscript;
            debugPrint(
                'GoogleSTTTranslator: Stored Speaker 2 fullTranscript: "${result2.fullTranscript}"');
          } else if (result2.segments.isNotEmpty) {
            _transcriptions[1] = result2.segments.map((s) => s.text).join(' ');
            debugPrint(
                'GoogleSTTTranslator: Stored Speaker 2 from segments: "${_transcriptions[1]}"');
          }
        }
      }

      debugPrint('GoogleSTTTranslator: Transcription completed');
      debugPrint('  Speaker 0: ${_transcriptions[0] ?? "No transcription"}');
      debugPrint('  Speaker 1: ${_transcriptions[1] ?? "No transcription"}');
      debugPrint(
          'GoogleSTTTranslator: Total transcriptions: ${_transcriptions.length}');
      debugPrint(
          'GoogleSTTTranslator: Transcription keys: ${_transcriptions.keys.toList()}');

      // Start translation after transcription is complete
      await _translateTranscriptions();
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Transcription error: $e');
      throw Exception('Failed to transcribe audio: $e');
    }
  }

  /// Translate transcriptions between speakers
  Future<void> _translateTranscriptions() async {
    try {
      debugPrint('GoogleSTTTranslator: Starting translation process...');

      // Get speaker languages
      final speaker1Language = _speakerLanguages[0];
      final speaker2Language = _speakerLanguages[1];

      if (speaker1Language == null || speaker2Language == null) {
        debugPrint('GoogleSTTTranslator: Speaker languages not configured');
        return;
      }

      final speaker1LangCode = speaker1Language.code;
      final speaker2LangCode = speaker2Language.code;

      debugPrint('GoogleSTTTranslator: Speaker 1 language: $speaker1LangCode');
      debugPrint('GoogleSTTTranslator: Speaker 2 language: $speaker2LangCode');

      // Check if translation is needed
      if (!TranslationService.isTranslationNeeded(
          speaker1LangCode, speaker2LangCode)) {
        debugPrint(
            'GoogleSTTTranslator: No translation needed - same language');
        return;
      }

      // Translate Speaker 1's text to Speaker 2's language
      if (_transcriptions[0] != null && _transcriptions[0]!.isNotEmpty) {
        debugPrint(
            'GoogleSTTTranslator: Translating Speaker 1 text to $speaker2LangCode...');
        final result1 = await TranslationService.translateText(
          sourceLanguage: speaker1LangCode,
          targetLanguage: speaker2LangCode,
          content: _transcriptions[0]!,
        );

        if (result1 != null && result1.translatedText.isNotEmpty) {
          _translations[0] = result1.translatedText;
          debugPrint(
              'GoogleSTTTranslator: Speaker 1 translation: "${result1.translatedText}"');
        } else {
          debugPrint('GoogleSTTTranslator: Speaker 1 translation failed');
        }
      }

      // Translate Speaker 2's text to Speaker 1's language
      if (_transcriptions[1] != null && _transcriptions[1]!.isNotEmpty) {
        debugPrint(
            'GoogleSTTTranslator: Translating Speaker 2 text to $speaker1LangCode...');
        final result2 = await TranslationService.translateText(
          sourceLanguage: speaker2LangCode,
          targetLanguage: speaker1LangCode,
          content: _transcriptions[1]!,
        );

        if (result2 != null && result2.translatedText.isNotEmpty) {
          _translations[1] = result2.translatedText;
          debugPrint(
              'GoogleSTTTranslator: Speaker 2 translation: "${result2.translatedText}"');
        } else {
          debugPrint('GoogleSTTTranslator: Speaker 2 translation failed');
        }
      }

      debugPrint('GoogleSTTTranslator: Translation process completed');
      debugPrint(
          '  Speaker 1 translation: ${_translations[0] ?? "No translation"}');
      debugPrint(
          '  Speaker 2 translation: ${_translations[1] ?? "No translation"}');

      // Update UI to show translations are available
      if (mounted) {
        setState(() {
          // Trigger UI update to show translation toggle buttons
        });
      }
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Translation error: $e');
      // Don't throw - translation failure shouldn't break the app
    }
  }

  Future<void> _playSpeaker1Audio() async {
    try {
      if (_speaker1AudioPath == null ||
          !await File(_speaker1AudioPath!).exists()) {
        _showErrorDialog('Audio file for Speaker 1 not found.');
        return;
      }

      if (_isPlayingSpeaker1) {
        await _speaker1Player.stop();
      } else {
        await _speaker1Player.play(DeviceFileSource(_speaker1AudioPath!));
      }
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Speaker 1 playback error: $e');
      _showErrorDialog('Failed to play Speaker 1 audio: $e');
    }
  }

  Future<void> _playSpeaker2Audio() async {
    try {
      if (_speaker2AudioPath == null ||
          !await File(_speaker2AudioPath!).exists()) {
        _showErrorDialog('Audio file for Speaker 2 not found.');
        return;
      }

      if (_isPlayingSpeaker2) {
        await _speaker2Player.stop();
      } else {
        await _speaker2Player.play(DeviceFileSource(_speaker2AudioPath!));
      }
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Speaker 2 playback error: $e');
      _showErrorDialog('Failed to play Speaker 2 audio: $e');
    }
  }

  void _toggleTranslation(int speakerId) {
    setState(() {
      _showTranslation[speakerId] = !(_showTranslation[speakerId] ?? false);
    });
    debugPrint(
        'GoogleSTTTranslator: Toggled translation for Speaker $speakerId: ${_showTranslation[speakerId]}');
  }

  // On-device diarization methods (copied from Native STT Translation)
  Float32List _convertBytesToFloat32List(Uint8List bytes) {
    // Skip WAV header (44 bytes) and convert 16-bit PCM to float
    final int dataStart = 44;
    final int dataLength = bytes.length - dataStart;
    final Float32List samples = Float32List(dataLength ~/ 2);

    for (int i = 0; i < samples.length; i++) {
      final int byteIndex = dataStart + (i * 2);
      if (byteIndex + 1 < bytes.length) {
        // Convert 16-bit signed integer to float (-1.0 to 1.0)
        final int sample = (bytes[byteIndex] | (bytes[byteIndex + 1] << 8));
        if (sample > 32767) {
          samples[i] = (sample - 65536) / 32768.0;
        } else {
          samples[i] = sample / 32768.0;
        }
      }
    }

    return samples;
  }

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
        'GoogleSTTTranslator: K-means converged after $iteration iterations');
    return labels;
  }

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

  double _euclideanDistance(List<double> a, List<double> b) {
    double sum = 0.0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

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

  Uint8List _createEmptyWavFile() {
    // Create a minimal WAV file with silence
    final int sampleRate = 16000;
    final int numChannels = 1;
    final int bitsPerSample = 16;
    final int dataSize = 0;
    final int fileSize = 36 + dataSize;

    final List<int> header = [
      // RIFF header
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      ..._intToBytes(fileSize, 4),
      0x57, 0x41, 0x56, 0x45, // "WAVE"

      // fmt chunk
      0x66, 0x6D, 0x74, 0x20, // "fmt "
      ..._intToBytes(16, 4), // fmt chunk size
      ..._intToBytes(1, 2), // audio format (PCM)
      ..._intToBytes(numChannels, 2),
      ..._intToBytes(sampleRate, 4),
      ..._intToBytes(
          sampleRate * numChannels * bitsPerSample ~/ 8, 4), // byte rate
      ..._intToBytes(numChannels * bitsPerSample ~/ 8, 2), // block align
      ..._intToBytes(bitsPerSample, 2),

      // data chunk
      0x64, 0x61, 0x74, 0x61, // "data"
      ..._intToBytes(dataSize, 4),
    ];

    return Uint8List.fromList(header);
  }

  Uint8List _convertFloat32ListToBytes(Float32List samples) {
    final int sampleRate = 16000;
    final int numChannels = 1;
    final int bitsPerSample = 16;
    final int dataSize = samples.length * 2;
    final int fileSize = 36 + dataSize;

    final List<int> header = [
      // RIFF header
      0x52, 0x49, 0x46, 0x46, // "RIFF"
      ..._intToBytes(fileSize, 4),
      0x57, 0x41, 0x56, 0x45, // "WAVE"

      // fmt chunk
      0x66, 0x6D, 0x74, 0x20, // "fmt "
      ..._intToBytes(16, 4), // fmt chunk size
      ..._intToBytes(1, 2), // audio format (PCM)
      ..._intToBytes(numChannels, 2),
      ..._intToBytes(sampleRate, 4),
      ..._intToBytes(
          sampleRate * numChannels * bitsPerSample ~/ 8, 4), // byte rate
      ..._intToBytes(numChannels * bitsPerSample ~/ 8, 2), // block align
      ..._intToBytes(bitsPerSample, 2),

      // data chunk
      0x64, 0x61, 0x74, 0x61, // "data"
      ..._intToBytes(dataSize, 4),
    ];

    // Convert float samples to 16-bit PCM
    final List<int> audioData = [];
    for (final sample in samples) {
      final int intSample = (sample * 32767).round().clamp(-32768, 32767);
      audioData.addAll(_intToBytes(intSample, 2));
    }

    return Uint8List.fromList([...header, ...audioData]);
  }

  List<int> _intToBytes(int value, int numBytes) {
    return List.generate(numBytes, (i) => (value >> (i * 8)) & 0xFF);
  }

  String _mapLanguageToGoogleCode(String languageCode) {
    // Map our language codes to Google STT format
    final Map<String, String> languageMap = {
      'en': 'en-US',
      'es': 'es-ES',
      'fr': 'fr-FR',
      'de': 'de-DE',
      'it': 'it-IT',
      'pt': 'pt-PT',
      'ru': 'ru-RU',
      'ja': 'ja-JP',
      'ko': 'ko-KR',
      'zh': 'zh-CN',
      'ar': 'ar-SA',
      'hi': 'hi-IN',
      'bn': 'bn-IN', // Bengali - will use default model
      'ur': 'ur-PK', // Urdu - will use default model
      'ms': 'ms-MY', // Malay - will use default model
    };

    final mappedCode = languageMap[languageCode.toLowerCase()] ?? 'en-US';
    debugPrint(
        'GoogleSTTTranslator: Mapped language code: $languageCode -> $mappedCode');
    return mappedCode;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1E33),
        title: const Text(
          'Error',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'OK',
              style: TextStyle(color: Color(0xFF00D9FF)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
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
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E27),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D9FF)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: _buildAppBar(),
      body:
          _showSpeakerSetup ? _buildSpeakerSetupScreen() : _buildMainContent(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1D1E33),
      elevation: 0,
      title: const Text(
        'Google STT Translation',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        if (!_showSpeakerSetup)
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 30),
          ...List.generate(_numberOfSpeakers, (index) {
            return _buildSpeakerConfig(index);
          }),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: _isStartingSession ? null : _startRecordingSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isStartingSession
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Starting...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'Start Recording',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerConfig(int speakerIndex) {
    final speakerColor = _speakerColors[speakerIndex % _speakerColors.length];
    final currentLanguage = _speakerLanguages[speakerIndex];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: speakerColor.withValues(alpha: 0.3),
          width: 2,
        ),
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
                child: Icon(
                  Icons.person,
                  color: speakerColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _speakerNames[speakerIndex],
                style: TextStyle(
                  color: speakerColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Language>(
            value: currentLanguage,
            decoration: InputDecoration(
              labelText: 'Select Language',
              labelStyle: const TextStyle(color: Colors.white70),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: speakerColor.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: speakerColor.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: speakerColor),
              ),
            ),
            dropdownColor: const Color(0xFF1D1E33),
            style: const TextStyle(color: Colors.white),
            items: _supportedLanguages.map((language) {
              return DropdownMenuItem<Language>(
                value: language,
                child: Text(language.name),
              );
            }).toList(),
            onChanged: (Language? newLanguage) {
              if (newLanguage != null) {
                setState(() {
                  _speakerLanguages[speakerIndex] = newLanguage;
                });
                debugPrint(
                    'GoogleSTTTranslator: Speaker $speakerIndex language changed to: ${newLanguage.name}');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        _buildSpeakerInfoBar(),
        Expanded(
          child: _isProcessing
              ? _buildProcessingView()
              : (_speaker1AudioPath != null && _speaker2AudioPath != null)
                  ? _buildResultsView()
                  : _buildIdleView(),
        ),
        _buildRecordingControls(),
      ],
    );
  }

  Widget _buildSpeakerInfoBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1D1E33),
      child: Row(
        children: List.generate(_numberOfSpeakers, (index) {
          final speakerColor = _speakerColors[index % _speakerColors.length];
          final language = _speakerLanguages[index];
          return Expanded(
            child: Container(
              margin:
                  EdgeInsets.only(right: index < _numberOfSpeakers - 1 ? 8 : 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: speakerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: speakerColor.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.person,
                    color: speakerColor,
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _speakerNames[index],
                    style: TextStyle(
                      color: speakerColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    language?.name ?? 'Unknown',
                    style: TextStyle(
                      color: speakerColor.withValues(alpha: 0.8),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
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
              strokeWidth: 4,
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

  Widget _buildIdleView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF00D9FF).withValues(alpha: 0.3),
                    const Color(0xFF00D9FF).withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.mic,
                color: Color(0xFF00D9FF),
                size: 60,
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'Ready to Record',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap the microphone button below to start recording a conversation between two speakers.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
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
            'Found ${_speakerSegments.length} speaker segments',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
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
    final translation = _translations[speakerIndex];
    final showTranslation = _showTranslation[speakerIndex] ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPlaying ? speakerColor : speakerColor.withValues(alpha: 0.3),
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
          // Playback controls
          GestureDetector(
            onTap: onTap,
            child: Row(
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
          ),

          // Message bubble with transcription/translation
          if (transcription != null && transcription.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildMessageBubble(
              speakerIndex: speakerIndex,
              speakerColor: speakerColor,
              transcription: transcription,
              translation: translation,
              showTranslation: showTranslation,
            ),
          ] else ...[
            // Debug: Show when transcription is missing
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Debug: No transcription for Speaker $speakerIndex\nTranscription: ${transcription ?? "null"}\nLength: ${transcription?.length ?? 0}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Get the target language name for translation display
  String _getTargetLanguageName(int speakerIndex) {
    // If this is Speaker 1, the target language is Speaker 2's language
    // If this is Speaker 2, the target language is Speaker 1's language
    final targetSpeakerIndex = speakerIndex == 0 ? 1 : 0;
    return _speakerLanguages[targetSpeakerIndex]?.name ?? 'Unknown';
  }

  Widget _buildMessageBubble({
    required int speakerIndex,
    required Color speakerColor,
    required String transcription,
    String? translation,
    required bool showTranslation,
  }) {
    final displayText =
        showTranslation && translation != null && translation.isNotEmpty
            ? translation
            : transcription;
    final isTranslated =
        showTranslation && translation != null && translation.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: speakerColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: speakerColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle button
          Row(
            children: [
              Icon(
                isTranslated ? Icons.translate : Icons.subtitles,
                color: speakerColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isTranslated ? 'Translation:' : 'Transcription:',
                style: TextStyle(
                  color: speakerColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Translation toggle button
              if (translation != null && translation.isNotEmpty)
                GestureDetector(
                  onTap: () => _toggleTranslation(speakerIndex),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: speakerColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: speakerColor.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isTranslated ? Icons.subtitles : Icons.translate,
                          color: speakerColor,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isTranslated ? 'Original' : 'Translate',
                          style: TextStyle(
                            color: speakerColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Text content
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              displayText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
          // Language indicator
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.language,
                color: speakerColor.withValues(alpha: 0.7),
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                isTranslated
                    ? 'Translated to ${_getTargetLanguageName(speakerIndex)}'
                    : 'Original: ${_speakerLanguages[speakerIndex]?.name ?? 'Unknown'}',
                style: TextStyle(
                  color: speakerColor.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
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
          ..._speakerSegments.take(10).map((segment) {
            final speakerName = _speakerNames[segment.speakerId] ??
                'Speaker ${segment.speakerId + 1}';
            final speakerColor =
                _speakerColors[segment.speakerId % _speakerColors.length];

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: speakerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: speakerColor.withValues(alpha: 0.3)),
              ),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          speakerName,
                          style: TextStyle(
                            color: speakerColor,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${segment.startTime.toStringAsFixed(1)}s - ${segment.endTime.toStringAsFixed(1)}s (${(segment.endTime - segment.startTime).toStringAsFixed(1)}s)',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(segment.confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: speakerColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_speakerSegments.length > 10)
            Text(
              '... and ${_speakerSegments.length - 10} more segments',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF1D1E33),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
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
                        color:
                            _isRecording ? Colors.red : const Color(0xFF00D9FF),
                        boxShadow: _isRecording
                            ? [
                                BoxShadow(
                                  color: Colors.red.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ]
                            : [],
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
          ],
        ),
      ),
    );
  }
}

/// Model for speaker segment from diarization
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
