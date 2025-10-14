import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/config_service.dart' as config_service;
import '../../services/google_stt_service.dart';
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
  final GoogleSttService _googleSttService = GoogleSttService.instance;
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

      // Initialize Google STT service
      final sttInitialized = await _googleSttService.initialize();
      if (!sttInitialized) {
        throw Exception('Failed to initialize Google Speech-to-Text');
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
        // Generate a proper file path for recording
        final Directory appDir = await getApplicationDocumentsDirectory();
        final String filePath =
            '${appDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

        debugPrint('OnScreenTranslator: Recording to: $filePath');

        // Start recording
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: filePath,
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

      // Collect language codes in speaker order (Speaker 0's language first, then Speaker 1's)
      final List<String> orderedLanguages = [];
      for (int i = 0; i < _numberOfSpeakers; i++) {
        final language = _speakerLanguages[i];
        if (language != null) {
          final googleLangCode = _getGoogleLanguageCode(language.code);
          if (!orderedLanguages.contains(googleLangCode)) {
            orderedLanguages.add(googleLangCode);
          }
        }
      }

      final String primaryLanguage =
          orderedLanguages.isNotEmpty ? orderedLanguages.first : 'en-US';
      final List<String>? alternativeLanguages =
          orderedLanguages.length > 1 ? orderedLanguages.sublist(1) : null;

      debugPrint(
          'OnScreenTranslator: Speaker 0 language: ${_speakerLanguages[0]?.code}');
      debugPrint(
          'OnScreenTranslator: Speaker 1 language: ${_speakerLanguages[1]?.code}');
      debugPrint(
          'OnScreenTranslator: Using languages: Primary=$primaryLanguage, Alternatives=$alternativeLanguages');

      // Transcribe with speaker diarization and multi-language support
      final result = await _googleSttService.transcribeWithDiarization(
        audioBytes: audioBytes,
        languageCode: primaryLanguage,
        alternativeLanguages: alternativeLanguages,
        minSpeakers: _numberOfSpeakers,
        maxSpeakers: _numberOfSpeakers,
      );

      if (result == null) {
        throw Exception('Failed to transcribe audio');
      }

      debugPrint(
          'OnScreenTranslator: Transcription complete: ${result.segments.length} segments, ${result.speakerCount} speakers');

      // Process each segment - Google STT already transcribed in correct language
      for (final segment in result.segments) {
        // Google STT with multi-language support already provides text in the detected language
        // No additional translation needed as each speaker speaks in their configured language

        // Add message to the list
        setState(() {
          _messages.add(TranscriptMessage(
            originalText: segment.text,
            translatedText:
                segment.text, // Already in correct language from Google STT
            speakerTag: segment.speakerTag,
            timestamp: DateTime.now(),
            startTime: segment.startTime,
            endTime: segment.endTime,
            detectedLanguage:
                _speakerLanguages[segment.speakerTag]?.code ?? 'en',
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
      debugPrint('OnScreenTranslator: Reading audio file from: $path');

      if (path.isEmpty) {
        debugPrint('OnScreenTranslator: Audio path is empty');
        return null;
      }

      // Read the audio file using dart:io
      final File audioFile = File(path);

      if (!await audioFile.exists()) {
        debugPrint('OnScreenTranslator: Audio file does not exist: $path');
        return null;
      }

      final Uint8List audioBytes = await audioFile.readAsBytes();
      debugPrint(
          'OnScreenTranslator: Read ${audioBytes.length} bytes from audio file');

      // Clean up the file after reading
      await audioFile.delete();
      debugPrint('OnScreenTranslator: Deleted temporary audio file');

      return audioBytes;
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
          const SizedBox(height: 32),

          // Number of speakers selector (commented out - fixed to 2 speakers)
          // _buildNumberOfSpeakersSelector(),
          // const SizedBox(height: 24),

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

  // Number of speakers selector (COMMENTED OUT - Fixed to 2 speakers)
  /*
  Widget _buildNumberOfSpeakersSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF00D9FF).withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.people, color: Color(0xFF00D9FF), size: 24),
              SizedBox(width: 12),
              Text(
                'Number of Speakers',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(5, (index) {
              final speakerCount = index + 2; // 2-6 speakers
              final isSelected = _numberOfSpeakers == speakerCount;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index < 4 ? 8 : 0),
                  child: GestureDetector(
                    onTap: () {
                      // Number selection disabled - fixed to 2 speakers
                    },
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF00D9FF)
                            : const Color(0xFF0A0E21),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF00D9FF)
                              : Colors.white24,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$speakerCount',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white54,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
  */

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
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(
                    right: index < _numberOfSpeakers - 1 ? 8 : 0),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: speakerColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: speakerColor.withOpacity(0.3), width: 1),
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
