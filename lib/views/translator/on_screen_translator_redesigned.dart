import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/config_service.dart' as config_service;
import '../../services/google_stt_service.dart';
import '../../services/permission_service.dart';
import '../../services/translation_service.dart';
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
  final GoogleSttService _googleSttService = GoogleSttService.instance;
  final PermissionService _permissionService = PermissionService.instance;
  final TtsService _ttsService = TtsService();
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;

  // Animations
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  // Languages
  List<config_service.Language> _supportedLanguages = [];
  config_service.Language? _targetLanguage;

  // Recording state
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isInitialized = false;

  // Diarization results
  List<TranscriptMessage> _messages = [];

  // Scroll controller for messages
  late ScrollController _scrollController;

  // Speaker colors for UI
  final List<Color> _speakerColors = [
    const Color(0xFF6200EA), // Purple
    const Color(0xFF00B8D4), // Cyan
    const Color(0xFFFF6F00), // Orange
    const Color(0xFF2E7D32), // Green
    const Color(0xFFD50000), // Red
    const Color(0xFF6A1B9A), // Deep Purple
  ];

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
      final languages = await _configService.getSupportedLanguages();
      if (languages.isEmpty) {
        throw Exception('No supported languages found');
      }

      // Initialize Google STT service
      final sttInitialized = await _googleSttService.initialize();
      if (!sttInitialized) {
        throw Exception('Failed to initialize Google Speech-to-Text');
      }

      // Initialize TTS service
      await _ttsService.initialize();

      setState(() {
        _supportedLanguages = languages;
        _targetLanguage = languages.firstWhere(
          (lang) => lang.code == 'en',
          orElse: () => languages.first,
        );
        _isInitialized = true;
      });

      debugPrint('OnScreenTranslator: Services initialized successfully');
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
      if (await _audioRecorder.hasPermission()) {
        // Start recording
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final audioPath = '${directory.path}/recording_$timestamp.wav';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: audioPath,
        );

        setState(() {
          _isRecording = true;
        });

        _pulseController.repeat(reverse: true);
        _waveController.repeat();

        debugPrint('OnScreenTranslator: Recording started');
      } else {
        _showError('Microphone permission denied');
      }
    } catch (e) {
      debugPrint('OnScreenTranslator: Error starting recording: $e');
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      // Stop recording and get the audio path
      final String? audioPath = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      _pulseController.stop();
      _pulseController.reset();
      _waveController.stop();

      if (audioPath != null) {
        debugPrint(
            'OnScreenTranslator: Recording stopped, processing audio...');
        await _processAudio(audioPath);
      } else {
        _showError('No audio recorded');
      }
    } catch (e) {
      debugPrint('OnScreenTranslator: Error stopping recording: $e');
      _showError('Failed to stop recording: $e');
    }
  }

  Future<void> _processAudio(String audioPath) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Read the audio file
      final audioBytes = await _readAudioFile(audioPath);
      if (audioBytes == null) {
        throw Exception('Failed to read audio file');
      }

      debugPrint(
          'OnScreenTranslator: Audio file size: ${audioBytes.length} bytes');

      // Get target language code
      final targetLangCode = _targetLanguage?.code ?? 'en';
      final languageCode = _getGoogleLanguageCode(targetLangCode);

      // Transcribe with speaker diarization
      final result = await _googleSttService.transcribeWithDiarization(
        audioBytes: audioBytes,
        languageCode: languageCode,
        minSpeakers: 2,
        maxSpeakers: 6,
      );

      if (result == null) {
        throw Exception('Failed to transcribe audio');
      }

      debugPrint(
          'OnScreenTranslator: Transcription complete: ${result.segments.length} segments, ${result.speakerCount} speakers');

      // Process each segment and translate if needed
      for (final segment in result.segments) {
        String translatedText = segment.text;

        // Translate to target language if needed
        if (targetLangCode != 'en') {
          // Detect source language and translate
          final translationResult = await TranslationService.translateText(
            sourceLanguage: 'en', // Assume English source
            targetLanguage: targetLangCode,
            content: segment.text,
          );

          if (translationResult != null) {
            translatedText = translationResult.translatedText;
          }
        }

        // Add message to the list
        setState(() {
          _messages.add(TranscriptMessage(
            originalText: segment.text,
            translatedText: translatedText,
            speakerTag: segment.speakerTag,
            timestamp: DateTime.now(),
            startTime: segment.startTime,
            endTime: segment.endTime,
          ));
        });

        // Auto-scroll to bottom
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('OnScreenTranslator: Error processing audio: $e');
      _showError('Failed to process audio: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<Uint8List?> _readAudioFile(String path) async {
    try {
      // For now, we'll implement a simple file reader
      // In production, you'd use proper file reading
      // This is a placeholder that needs platform-specific implementation
      debugPrint('OnScreenTranslator: Reading audio file from: $path');

      // TODO: Implement proper audio file reading
      // For web: use File API
      // For mobile: use dart:io File

      return null; // Placeholder
    } catch (e) {
      debugPrint('OnScreenTranslator: Error reading audio file: $e');
      return null;
    }
  }

  String _getGoogleLanguageCode(String code) {
    // Map common language codes to Google STT language codes
    const Map<String, String> languageMap = {
      'en': 'en-US',
      'es': 'es-ES',
      'fr': 'fr-FR',
      'de': 'de-DE',
      'it': 'it-IT',
      'pt': 'pt-PT',
      'ru': 'ru-RU',
      'zh': 'zh-CN',
      'ja': 'ja-JP',
      'ko': 'ko-KR',
      'ar': 'ar-SA',
      'hi': 'hi-IN',
      'ms': 'ms-MY',
    };

    return languageMap[code] ?? 'en-US';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _playMessage(TranscriptMessage message) async {
    try {
      final targetLangCode = _targetLanguage?.code ?? 'en';

      await _ttsService.speak(
        message.translatedText,
        targetLangCode,
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

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _ttsService.dispose();
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

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildLanguageSelector(),
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

  Widget _buildLanguageSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      margin: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.translate, color: Color(0xFF00D9FF), size: 24),
          const SizedBox(width: 12),
          const Text(
            'Translate to:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<config_service.Language>(
                value: _targetLanguage,
                dropdownColor: const Color(0xFF1D1E33),
                style: const TextStyle(color: Colors.white, fontSize: 16),
                icon:
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF00D9FF)),
                items:
                    _supportedLanguages.map((config_service.Language language) {
                  return DropdownMenuItem<config_service.Language>(
                    value: language,
                    child: Text(language.nativeName),
                  );
                }).toList(),
                onChanged: (config_service.Language? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _targetLanguage = newValue;
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
            // Speaker header
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
                    'Speaker ${message.speakerTag + 1}',
                    style: TextStyle(
                      color: speakerColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
              Text(
                _isRecording ? 'Recording...' : 'Processing...',
                style: const TextStyle(
                  color: Color(0xFF00D9FF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
            ],
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

/// Model for a transcript message with speaker information
class TranscriptMessage {
  final String originalText;
  final String translatedText;
  final int speakerTag;
  final DateTime timestamp;
  final double startTime;
  final double endTime;

  TranscriptMessage({
    required this.originalText,
    required this.translatedText,
    required this.speakerTag,
    required this.timestamp,
    required this.startTime,
    required this.endTime,
  });
}
