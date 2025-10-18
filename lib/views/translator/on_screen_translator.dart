import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/config_service.dart' as config_service;
import '../../services/sherpa_whisper_service.dart';
import '../../services/permission_service.dart';
import '../../services/tts_service.dart';

class OnScreenTranslator extends StatefulWidget {
  const OnScreenTranslator({super.key});

  @override
  State<OnScreenTranslator> createState() => _OnScreenTranslatorState();
}

class _OnScreenTranslatorState extends State<OnScreenTranslator>
    with TickerProviderStateMixin {
  // Services
  final config_service.ConfigService _configService =
      config_service.ConfigService.instance;
  final SherpaWhisperService _sherpaWhisperService = SherpaWhisperService();
  final PermissionService _permissionService = PermissionService.instance;
  final TTSService _ttsService = TTSService();
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;

  // Animations
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  // Languages
  List<Language> _supportedLanguages = [];

  // Speaker-specific languages (fixed to 2 speakers)
  Map<int, Language> _speakerLanguages = {};
  final int _numberOfSpeakers = 2; // Fixed to 2 speakers
  bool _showSpeakerSetup = true; // Show setup UI before recording

  // Recording state
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isInitialized = false;

  // Enhanced diarization results with speaker information
  List<TranscriptMessage> _messages = [];

  // Real-time transcription results
  String _transcribedText = '';
  double _confidence = 0.0;
  String _detectedLanguage = 'en';
  int _currentSpeakerId = 0;

  // Scroll controller for messages
  late ScrollController _scrollController;

  // Stream subscriptions for cleanup
  StreamSubscription<SherpaWhisperResult>? _transcriptionSubscription;
  StreamSubscription<List<SpeakerSegment>>? _diarizationSubscription;

  // Speaker colors for UI
  final List<Color> _speakerColors = [
    const Color(0xFF6200EA), // Purple
    const Color(0xFF00B8D4), // Cyan
    const Color(0xFFFF6F00), // Orange
    const Color(0xFF2E7D32), // Green
    const Color(0xFFD50000), // Red
    const Color(0xFF6A1B9A), // Deep Purple
  ];

  // Speaker tracking
  final Map<int, String> _speakerNames = {};
  final Map<int, double> _speakerConfidences = {};

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
    _scrollController = ScrollController();
  }

  void _initializeAnimations() {
    // Pulse animation for mic button
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Wave animation for recording indicator
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_waveController);
  }

  Future<void> _initializeServices() async {
    try {
      // Request microphone permission
      final hasPermission =
          await _permissionService.requestMicrophonePermission();
      if (!hasPermission) {
        _showError('Microphone permission is required');
        return;
      }

      // Load supported languages
      final configLanguages = await _configService.getSupportedLanguages();
      if (configLanguages.isEmpty) {
        throw Exception('No supported languages found');
      }

      // Convert to local Language model
      final languages = configLanguages
          .map((lang) => Language(
                code: lang.code,
                name: lang.name,
                nativeName: lang.nativeName,
              ))
          .toList();

      // Initialize Sherpa-ONNX Whisper service with speaker diarization
      final sherpaInitialized = await _sherpaWhisperService.initialize();
      if (!sherpaInitialized) {
        throw Exception('Failed to initialize Sherpa-ONNX Whisper service');
      }

      // Initialize TTS service
      await _ttsService.initialize();

      // Initialize default speaker languages
      final defaultEnglish = languages.firstWhere(
        (lang) => lang.code == 'en',
        orElse: () => languages.first,
      );

      setState(() {
        _supportedLanguages = languages;
        // Set default languages for speakers
        _speakerLanguages = {
          0: defaultEnglish, // Speaker 1 (index 0)
          1: defaultEnglish, // Speaker 2 (index 1)
        };
        _isInitialized = true;
      });

      // Initialize speaker names
      _speakerNames[0] = 'Speaker 1';
      _speakerNames[1] = 'Speaker 2';

      debugPrint(
          'OnScreenTranslator: Services initialized successfully with speaker diarization');
    } catch (e) {
      debugPrint('OnScreenTranslator: Initialization error: $e');
      _showError('Failed to initialize translator: $e');
    }
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
      if (_sherpaWhisperService.isRecovering) {
        _showError('Service is recovering from a crash. Please wait a moment.');
        return;
      }

      if (await _audioRecorder.hasPermission()) {
        debugPrint(
            'OnScreenTranslator: Starting transcription with speaker diarization');

        // Start Sherpa-ONNX real-time transcription with speaker diarization
        await _sherpaWhisperService.startRealtimeTranscription();

        // Listen to transcription results
        _transcriptionSubscription =
            _sherpaWhisperService.transcriptionStream.listen((result) {
          setState(() {
            _transcribedText = result.text;
            _confidence = result.confidence;
            _detectedLanguage = result.language;
            _currentSpeakerId = result.speakerId;
          });

          // Add message to list if we have meaningful text
          if (result.text.trim().isNotEmpty && result.text.length > 2) {
            _addTranscriptMessage(result);
          }
        });

        // Listen to speaker diarization results
        _diarizationSubscription =
            _sherpaWhisperService.diarizationStream.listen((segments) {
          debugPrint(
              'OnScreenTranslator: Received ${segments.length} speaker segments');

          // Update speaker confidences
          for (final segment in segments) {
            _speakerConfidences[segment.speakerId] = segment.confidence;
          }

          // Update speaker names if needed
          for (final segment in segments) {
            if (!_speakerNames.containsKey(segment.speakerId)) {
              _speakerNames[segment.speakerId] =
                  'Speaker ${segment.speakerId + 1}';
            }
          }

          setState(() {});
        });

        // Start audio recording for real-time processing
        await _startAudioRecording();

        setState(() {
          _isRecording = true;
        });

        _pulseController.repeat(reverse: true);
        _waveController.repeat();

        debugPrint(
            'OnScreenTranslator: Transcription with speaker diarization started');
      } else {
        _showError('Microphone permission denied');
      }
    } catch (e) {
      debugPrint('OnScreenTranslator: Error starting recording: $e');
      _showError('Failed to start recording: $e');
    }
  }

  /// Add transcript message with speaker information
  void _addTranscriptMessage(SherpaWhisperResult result) {
    final message = TranscriptMessage(
      originalText: result.text,
      translatedText:
          result.text, // For now, no translation - just transcription
      speakerTag: result.speakerId,
      timestamp: DateTime.now(),
      startTime: result.startTime.toDouble(),
      endTime: result.endTime.toDouble(),
      detectedLanguage: result.language,
    );

    setState(() {
      _messages.insert(0, message); // Add to top of list

      // Limit messages to prevent memory issues
      if (_messages.length > 100) {
        _messages = _messages.take(100).toList();
      }
    });

    // Auto-scroll to top
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Start audio recording for real-time processing
  Future<void> _startAudioRecording() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String filePath =
          '${appDir.path}/realtime_recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      debugPrint('OnScreenTranslator: Starting audio recording: $filePath');

      // Start recording with streaming
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: filePath,
      );

      // Start processing audio chunks in real-time
      _processAudioChunks(filePath);
    } catch (e) {
      debugPrint('OnScreenTranslator: Error starting audio recording: $e');
      rethrow;
    }
  }

  /// Process audio chunks in real-time
  void _processAudioChunks(String audioPath) {
    debugPrint(
        'OnScreenTranslator: Starting audio chunk processing for: $audioPath');

    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isRecording) {
        debugPrint('OnScreenTranslator: Recording stopped, canceling timer');
        timer.cancel();
        return;
      }

      try {
        // Read current audio file
        final file = File(audioPath);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint('OnScreenTranslator: Audio file size: $fileSize bytes');

          if (fileSize > 1024) {
            final audioBytes = await file.readAsBytes();
            debugPrint(
                'OnScreenTranslator: Processing audio chunk: ${audioBytes.length} bytes');

            // Process chunk with Sherpa-ONNX (includes transcription and diarization)
            await _sherpaWhisperService.processAudioChunk(audioBytes);
          } else {
            debugPrint(
                'OnScreenTranslator: Audio file too small ($fileSize bytes), skipping');
          }
        } else {
          debugPrint(
              'OnScreenTranslator: Audio file does not exist: $audioPath');
        }
      } catch (e) {
        debugPrint('OnScreenTranslator: Error processing audio chunk: $e');
      }
    });
  }

  Future<void> _stopRecording() async {
    try {
      debugPrint(
          'OnScreenTranslator: Stopping transcription with speaker diarization');

      // Stop audio recording first
      final String? audioPath = await _audioRecorder.stop();
      debugPrint(
          'OnScreenTranslator: Audio recording stopped, path: $audioPath');

      // Stop Sherpa-ONNX real-time transcription
      await _sherpaWhisperService.stopRealtimeTranscription();

      // Cancel stream subscriptions
      await _transcriptionSubscription?.cancel();
      await _diarizationSubscription?.cancel();
      _transcriptionSubscription = null;
      _diarizationSubscription = null;

      setState(() {
        _isRecording = false;
        _transcribedText = '';
        _currentSpeakerId = 0;
      });

      _pulseController.stop();
      _pulseController.reset();
      _waveController.stop();

      debugPrint(
          'OnScreenTranslator: Transcription with speaker diarization stopped');
    } catch (e) {
      debugPrint('OnScreenTranslator: Error stopping recording: $e');
      _showError('Failed to stop recording: $e');
    }
  }

  Future<void> _playMessage(TranscriptMessage message) async {
    try {
      // Use the detected language for TTS playback
      await _ttsService.speak(
        text: message.translatedText,
        languageCode: message.detectedLanguage,
      );
    } catch (e) {
      debugPrint('OnScreenTranslator: Error playing message: $e');
      _showError('Failed to play audio');
    }
  }

  void _clearMessages() {
    setState(() {
      _messages.clear();
    });
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

  Color _getSpeakerColor(int speakerTag) {
    return _speakerColors[speakerTag % _speakerColors.length];
  }

  String _getSpeakerName(int speakerId) {
    return _speakerNames[speakerId] ?? 'Speaker ${speakerId + 1}';
  }

  double _getSpeakerConfidence(int speakerId) {
    return _speakerConfidences[speakerId] ?? 0.0;
  }

  @override
  void dispose() {
    // Stop any ongoing recording and transcription before disposing
    if (_isRecording) {
      _stopRecording();
    }

    _pulseController.dispose();
    _waveController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _ttsService.dispose();
    _sherpaWhisperService.cleanup();
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
          _buildRealtimeTranscriptionDisplay(),
          Expanded(child: _buildMessagesList()),
          _buildRecordingControls(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1D1E33),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'On-Screen Translator',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        if (_messages.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: _clearMessages,
            tooltip: 'Clear all messages',
          ),
      ],
    );
  }

  Widget _buildSpeakerSetupScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Text(
            'Speaker Language Setup',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configure the language for each speaker in the conversation',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),

          // Speaker diarization info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1E33),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00D9FF).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.people,
                  color: Color(0xFF00D9FF),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Speaker Diarization',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Automatically identifies and separates 2 speakers',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _sherpaWhisperService.isDiarizationAvailable
                      ? Icons.check_circle
                      : Icons.warning,
                  color: _sherpaWhisperService.isDiarizationAvailable
                      ? Colors.green
                      : Colors.orange,
                  size: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Speaker language selectors (2 speakers only)
          ...List.generate(_numberOfSpeakers, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildSpeakerLanguageCard(index),
            );
          }),

          const SizedBox(height: 32),

          // Start button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _startConversation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00D9FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow, color: Colors.white, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'Start Conversation',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerLanguageCard(int speakerIndex) {
    final speakerColor = _getSpeakerColor(speakerIndex);
    final selectedLanguage =
        _speakerLanguages[speakerIndex] ?? _supportedLanguages.first;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: speakerColor.withOpacity(0.5), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: speakerColor,
                child: Text(
                  'S${speakerIndex + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Speaker ${speakerIndex + 1}',
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
            'Select Language:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E21),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: speakerColor.withOpacity(0.3), width: 1),
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

  Widget _buildRealtimeTranscriptionDisplay() {
    if (!_isRecording || _transcribedText.isEmpty) {
      return const SizedBox.shrink();
    }

    final speakerColor = _getSpeakerColor(_currentSpeakerId);
    final speakerName = _getSpeakerName(_currentSpeakerId);
    final speakerConfidence = _getSpeakerConfidence(_currentSpeakerId);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: speakerColor.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: speakerColor,
                child: Text(
                  'S${_currentSpeakerId + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                speakerName,
                style: TextStyle(
                  color: speakerColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.mic,
                color: speakerColor,
                size: 16,
              ),
              const Spacer(),
              Text(
                '${(_confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _transcribedText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          if (_detectedLanguage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Language: $_detectedLanguage',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Speaker Confidence: ${(speakerConfidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: speakerColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
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
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ...List.generate(_numberOfSpeakers, (index) {
            final speakerColor = _getSpeakerColor(index);
            final language = _speakerLanguages[index];
            final confidence = _getSpeakerConfidence(index);
            final isActive = _currentSpeakerId == index && _isRecording;

            return Expanded(
              child: Container(
                margin: EdgeInsets.only(
                    right: index < _numberOfSpeakers - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? speakerColor.withOpacity(0.2)
                      : speakerColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isActive
                          ? speakerColor
                          : speakerColor.withOpacity(0.3),
                      width: isActive ? 2 : 1),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: speakerColor,
                      child: Text(
                        'S${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      language?.code.toUpperCase() ?? 'EN',
                      style: TextStyle(
                        color: speakerColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (confidence > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${(confidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: speakerColor,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings, size: 20),
            color: const Color(0xFF00D9FF),
            onPressed: () {
              setState(() {
                _showSpeakerSetup = true;
              });
            },
            tooltip: 'Change speaker settings',
          ),
        ],
      ),
    );
  }

  void _startConversation() {
    setState(() {
      _showSpeakerSetup = false;
    });
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty && !_isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic_none,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Tap the microphone to start recording',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Conversations will be transcribed with\nspeaker identification',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            if (_sherpaWhisperService.isRecovering)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Recovering from crash...',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else if (_sherpaWhisperService.isDiarizationAvailable)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Speaker Diarization Active',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length + (_isProcessing ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isProcessing) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D9FF)),
              ),
            ),
          );
        }

        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(TranscriptMessage message) {
    final speakerColor = _getSpeakerColor(message.speakerTag);
    final speakerName = _getSpeakerName(message.speakerTag);
    final speakerConfidence = _getSpeakerConfidence(message.speakerTag);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1D1E33),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: speakerColor.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Speaker header with enhanced information
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: speakerColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: speakerColor,
                    child: Text(
                      'S${message.speakerTag + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    speakerName,
                    style: TextStyle(
                      color: speakerColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: speakerColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message.detectedLanguage.toUpperCase(),
                      style: TextStyle(
                        color: speakerColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (speakerConfidence > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: speakerColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(speakerConfidence * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: speakerColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.volume_up, size: 20),
                    color: speakerColor,
                    onPressed: () => _playMessage(message),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Message content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.originalText != message.translatedText) ...[
                    Text(
                      message.originalText,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    message.translatedText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      if (message.startTime > 0 && message.endTime > 0)
                        Text(
                          '${message.startTime.toStringAsFixed(1)}s - ${message.endTime.toStringAsFixed(1)}s',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingControls() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isRecording || _isProcessing) ...[
              AnimatedBuilder(
                animation: _waveAnimation,
                builder: (context, child) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final height = 20.0 +
                          30.0 *
                              (1.0 -
                                  ((index - 2).abs() / 2.0) *
                                      (1.0 - _waveAnimation.value));
                      return Container(
                        width: 4,
                        height: height,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00D9FF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_currentSpeakerId >= 0 && _isRecording) ...[
                    CircleAvatar(
                      radius: 8,
                      backgroundColor: _getSpeakerColor(_currentSpeakerId),
                      child: Text(
                        'S${_currentSpeakerId + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _isRecording ? 'Recording...' : 'Processing...',
                    style: const TextStyle(
                      color: Color(0xFF00D9FF),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            GestureDetector(
              onTap: (_isProcessing || _sherpaWhisperService.isRecovering)
                  ? null
                  : _toggleRecording,
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
                                  const Color(0xFFFF1744),
                                  const Color(0xFFD50000)
                                ]
                              : [
                                  const Color(0xFF00D9FF),
                                  const Color(0xFF0091EA)
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording
                                    ? const Color(0xFFFF1744)
                                    : const Color(0xFF00D9FF))
                                .withOpacity(0.5),
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
              _sherpaWhisperService.isRecovering
                  ? 'Service is recovering...'
                  : (_isRecording
                      ? 'Tap to stop recording'
                      : 'Tap to start recording'),
              style: TextStyle(
                color: _sherpaWhisperService.isRecovering
                    ? Colors.orange
                    : Colors.white54,
                fontSize: 14,
                fontWeight: _sherpaWhisperService.isRecovering
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            if (_sherpaWhisperService.isRecovering) ...[
              const SizedBox(height: 8),
              Text(
                'Crash count: ${_sherpaWhisperService.crashCount}',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ] else if (_sherpaWhisperService.isDiarizationAvailable) ...[
              const SizedBox(height: 8),
              Text(
                'Speaker diarization active',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Enhanced transcript message with speaker information
class TranscriptMessage {
  final String originalText;
  final String translatedText;
  final int speakerTag;
  final DateTime timestamp;
  final double startTime;
  final double endTime;
  final String detectedLanguage;

  TranscriptMessage({
    required this.originalText,
    required this.translatedText,
    required this.speakerTag,
    required this.timestamp,
    required this.startTime,
    required this.endTime,
    required this.detectedLanguage,
  });
}

/// Language model (should match the existing Language class)
class Language {
  final String code;
  final String name;
  final String nativeName;

  Language({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  factory Language.fromJson(Map<String, dynamic> json) {
    return Language(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      nativeName: json['nativeName'] ?? json['name'] ?? '',
    );
  }
}
