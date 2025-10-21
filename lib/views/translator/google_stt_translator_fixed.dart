import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../services/config_service.dart';
import '../../services/permission_service.dart';
import '../../services/google_stt_service.dart';

/// Google STT Translation - Records 2 speakers, performs diarization using Google STT,
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
  final GoogleSttService _googleSttService = GoogleSttService.instance;
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

      // Initialize Google STT service
      final googleSttInitialized = await _googleSttService.initialize();
      if (!googleSttInitialized) {
        debugPrint(
            'GoogleSTTTranslator: Google STT initialization failed - transcription will be unavailable');
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
            '${appDir.path}/google_stt_recording_$timestamp.wav';

        debugPrint('GoogleSTTTranslator: Recording to: $_recordedAudioPath');

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
          _transcriptions.clear();
        });

        _pulseController.repeat(reverse: true);
        _waveController.repeat();

        debugPrint('GoogleSTTTranslator: Recording started');
      } else {
        _showErrorDialog('Microphone permission is required for recording.');
      }
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
        _processingStatus = 'Performing speaker diarization...';
      });

      // Get primary language (use Speaker 1's language as primary)
      final primaryLanguage = _speakerLanguages[0];
      final primaryLanguageCode =
          _mapLanguageToGoogleCode(primaryLanguage?.code ?? 'en');

      // Get alternative languages (Speaker 2's language)
      final alternativeLanguage = _speakerLanguages[1];
      final alternativeLanguageCode =
          _mapLanguageToGoogleCode(alternativeLanguage?.code ?? 'en');

      // Perform Google STT with diarization
      final diarizationResult =
          await _googleSttService.transcribeWithDiarization(
        audioBytes: audioBytes,
        languageCode: primaryLanguageCode,
        alternativeLanguages: [alternativeLanguageCode],
        minSpeakers: 2,
        maxSpeakers: 2,
      );

      if (diarizationResult == null || diarizationResult.segments.isEmpty) {
        throw Exception('No speech detected or diarization failed');
      }

      setState(() {
        _processingProgress = 0.6;
        _processingStatus = 'Separating audio by speakers...';
      });

      // Convert Google STT segments to our format
      _speakerSegments = diarizationResult.segments.map((segment) {
        return SpeakerSegment(
          speakerId: segment.speakerTag,
          startTime: segment.startTime,
          endTime: segment.endTime,
          confidence: segment.confidence,
        );
      }).toList();

      // Separate audio by speakers
      await _separateAudioBySpeaker();

      setState(() {
        _processingProgress = 0.8;
        _processingStatus = 'Transcribing audio...';
      });

      // Transcribe separated audio
      await _transcribeSeparatedAudio();

      setState(() {
        _processingProgress = 1.0;
        _processingStatus = 'Processing complete!';
      });

      // Show success message
      _showSuccessDialog();

      setState(() {
        _isProcessing = false;
        _showSpeakerSetup = false;
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

  Future<void> _separateAudioBySpeaker() async {
    if (_recordedAudioPath == null || _speakerSegments.isEmpty) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Create separate audio files for each speaker
      _speaker1AudioPath =
          '${directory.path}/google_stt_speaker1_$timestamp.wav';
      _speaker2AudioPath =
          '${directory.path}/google_stt_speaker2_$timestamp.wav';

      // Read original audio
      final audioFile = File(_recordedAudioPath!);
      final audioBytes = await audioFile.readAsBytes();

      // Skip WAV header (44 bytes)
      final audioData = audioBytes.sublist(44);
      final sampleRate = 16000;
      final bytesPerSample = 2; // 16-bit audio

      // Create audio data for each speaker
      final speaker1Audio = <int>[];
      final speaker2Audio = <int>[];

      // Add WAV headers
      speaker1Audio.addAll(_createWavHeader(0));
      speaker2Audio.addAll(_createWavHeader(0));

      // Process each segment
      for (final segment in _speakerSegments) {
        final startByte =
            (segment.startTime * sampleRate * bytesPerSample).round();
        final endByte = (segment.endTime * sampleRate * bytesPerSample).round();
        final segmentLength = endByte - startByte;

        if (startByte >= 0 &&
            endByte <= audioData.length &&
            segmentLength > 0) {
          final segmentData = audioData.sublist(startByte, endByte);

          if (segment.speakerId == 0) {
            speaker1Audio.addAll(segmentData);
          } else if (segment.speakerId == 1) {
            speaker2Audio.addAll(segmentData);
          }
        }
      }

      // Update WAV headers with actual data length
      final speaker1DataLength = speaker1Audio.length - 44;
      final speaker2DataLength = speaker2Audio.length - 44;

      // Update file size in headers
      _updateWavHeader(speaker1Audio, speaker1DataLength);
      _updateWavHeader(speaker2Audio, speaker2DataLength);

      // Write separated audio files
      await File(_speaker1AudioPath!).writeAsBytes(speaker1Audio);
      await File(_speaker2AudioPath!).writeAsBytes(speaker2Audio);

      debugPrint('GoogleSTTTranslator: Audio separated successfully');
      debugPrint('  Speaker 1: ${speaker1DataLength} bytes');
      debugPrint('  Speaker 2: ${speaker2DataLength} bytes');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Audio separation error: $e');
      throw Exception('Failed to separate audio: $e');
    }
  }

  Future<void> _transcribeSeparatedAudio() async {
    try {
      // For Google STT, we need to transcribe each separated audio file
      // to get the actual text for each speaker

      // Transcribe Speaker 1 audio
      if (_speaker1AudioPath != null &&
          await File(_speaker1AudioPath!).exists()) {
        final speaker1Language = _speakerLanguages[0];
        final speaker1LanguageCode =
            _mapLanguageToGoogleCode(speaker1Language?.code ?? 'en');

        final audioBytes = await File(_speaker1AudioPath!).readAsBytes();
        final result1 = await _googleSttService.transcribeWithDiarization(
          audioBytes: audioBytes,
          languageCode: speaker1LanguageCode,
          minSpeakers: 1,
          maxSpeakers: 1,
        );

        if (result1 != null && result1.fullTranscript.isNotEmpty) {
          _transcriptions[0] = result1.fullTranscript;
        }
      }

      // Transcribe Speaker 2 audio
      if (_speaker2AudioPath != null &&
          await File(_speaker2AudioPath!).exists()) {
        final speaker2Language = _speakerLanguages[1];
        final speaker2LanguageCode =
            _mapLanguageToGoogleCode(speaker2Language?.code ?? 'en');

        final audioBytes = await File(_speaker2AudioPath!).readAsBytes();
        final result2 = await _googleSttService.transcribeWithDiarization(
          audioBytes: audioBytes,
          languageCode: speaker2LanguageCode,
          minSpeakers: 1,
          maxSpeakers: 1,
        );

        if (result2 != null && result2.fullTranscript.isNotEmpty) {
          _transcriptions[1] = result2.fullTranscript;
        }
      }

      debugPrint('GoogleSTTTranslator: Transcription completed');
      debugPrint('  Speaker 0: ${_transcriptions[0] ?? "No transcription"}');
      debugPrint('  Speaker 1: ${_transcriptions[1] ?? "No transcription"}');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Transcription error: $e');
      throw Exception('Failed to transcribe audio: $e');
    }
  }

  List<int> _createWavHeader(int dataLength) {
    final header = <int>[];

    // RIFF header
    header.addAll('RIFF'.codeUnits);
    header.addAll(_int32ToBytes(dataLength + 36)); // File size - 8
    header.addAll('WAVE'.codeUnits);

    // fmt chunk
    header.addAll('fmt '.codeUnits);
    header.addAll(_int32ToBytes(16)); // fmt chunk size
    header.addAll(_int16ToBytes(1)); // Audio format (PCM)
    header.addAll(_int16ToBytes(1)); // Number of channels (mono)
    header.addAll(_int32ToBytes(16000)); // Sample rate
    header.addAll(_int32ToBytes(32000)); // Byte rate
    header.addAll(_int16ToBytes(2)); // Block align
    header.addAll(_int16ToBytes(16)); // Bits per sample

    // data chunk
    header.addAll('data'.codeUnits);
    header.addAll(_int32ToBytes(dataLength)); // Data size

    return header;
  }

  void _updateWavHeader(List<int> audioData, int dataLength) {
    if (audioData.length < 44) return;

    // Update file size (position 4-7)
    final fileSize = dataLength + 36;
    final fileSizeBytes = _int32ToBytes(fileSize);
    for (int i = 0; i < 4; i++) {
      audioData[4 + i] = fileSizeBytes[i];
    }

    // Update data size (position 40-43)
    final dataSizeBytes = _int32ToBytes(dataLength);
    for (int i = 0; i < 4; i++) {
      audioData[40 + i] = dataSizeBytes[i];
    }
  }

  List<int> _int16ToBytes(int value) {
    return [value & 0xFF, (value >> 8) & 0xFF];
  }

  List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF
    ];
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
      'bn': 'bn-IN',
      'ur': 'ur-PK',
      'ms': 'ms-MY',
    };

    return languageMap[languageCode.toLowerCase()] ?? 'en-US';
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

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1E33),
        title: const Text(
          'Success!',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Audio has been processed successfully. You can now play back each speaker\'s audio separately.',
          style: TextStyle(color: Colors.white70),
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
      title: const Text('Google STT Translation'),
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
            const Text(
              'Configure Speakers',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Select languages for each speaker. Google STT will automatically detect and separate their voices.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),

            // Speaker 1 Configuration
            _buildSpeakerConfig(0),
            const SizedBox(height: 20),

            // Speaker 2 Configuration
            _buildSpeakerConfig(1),
            const SizedBox(height: 40),

            // Start Recording Button
            ElevatedButton(
              onPressed: _isRecording ? null : _startRecording,
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
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeakerConfig(int speakerId) {
    final speakerName = _speakerNames[speakerId] ?? 'Speaker ${speakerId + 1}';
    final speakerColor = _speakerColors[speakerId % _speakerColors.length];
    final selectedLanguage = _speakerLanguages[speakerId];

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
                  color: speakerColor,
                ),
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                speakerName,
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
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<Language>(
            value: selectedLanguage,
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0A0E21),
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
                  _speakerLanguages[speakerId] = newLanguage;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerInfoBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSpeakerInfo(0),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildSpeakerInfo(1),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerInfo(int speakerId) {
    final speakerColor = _speakerColors[speakerId % _speakerColors.length];
    final language = _speakerLanguages[speakerId];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: speakerColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: speakerColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: speakerColor,
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _speakerNames[speakerId] ?? 'Speaker ${speakerId + 1}',
            style: TextStyle(
              color: speakerColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            language?.name ?? 'Unknown',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
        ],
      ),
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
                    child: Text(
                      '$speakerName: ${segment.startTime.toStringAsFixed(1)}s - ${segment.endTime.toStringAsFixed(1)}s (${(segment.confidence * 100).toStringAsFixed(0)}%)',
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
          if (_speakerSegments.length > 10)
            Text(
              '... and ${_speakerSegments.length - 10} more segments',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
        ],
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
