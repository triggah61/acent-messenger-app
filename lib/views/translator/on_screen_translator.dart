import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math' as math;

import '../../services/config_service.dart';
import '../../services/speech_service.dart';
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
  final ConfigService _configService = ConfigService.instance;
  final SpeechService _speechService = SpeechService.instance;
  final PermissionService _permissionService = PermissionService.instance;
  final TTSService _ttsService = TTSService.instance;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _fadeController;
  late AnimationController _scaleController;

  // Animations
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // Languages
  List<Language> _supportedLanguages = [];
  Language? _sourceLanguage;
  Language? _targetLanguage;

  // Recording state
  String _recognizedText = '';
  String _translatedText = '';

  // Translation state
  bool _isTranslating = false;
  bool _hasTranslation = false;

  // UI state
  bool _isLoading = true;

  // Continuous STT and Slot-based processing
  String _transcribedText = ''; // Continuously accumulated text
  Timer? _silentDetectorTimer; // 3-second silent detection timer
  bool _isMuted = false; // User mute/unmute control
  bool _isTTSPlaying = false; // Auto-mute during TTS playback
  bool _isContinuousListening = false; // Continuous listening state
  static const Duration _silentTimeout = Duration(seconds: 3);

  // Auto-scroll controller for text display
  late ScrollController _textScrollController;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
    _textScrollController = ScrollController();
  }

  void _initializeAnimations() {
    // Pulse animation for mic button
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Wave animation for sound visualization
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _waveAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(_waveController);

    // Fade animation for text appearance
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    ));

    // Scale animation for language cards
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));
  }

  Future<void> _initializeServices() async {
    try {
      // Load supported languages from backend config
      print('OnScreenTranslator: Loading supported languages from backend...');
      final languages = await _configService.getSupportedLanguages();
      print(
          'OnScreenTranslator: Loaded ${languages.length} languages from backend');

      // Debug log the languages
      for (final lang in languages) {
        print(
            'OnScreenTranslator: Language - ${lang.code}: ${lang.name} (${lang.nativeName})');
      }

      // Initialize TTS service
      print('OnScreenTranslator: Initializing TTS service...');
      await _ttsService.initialize();
      print('OnScreenTranslator: TTS service initialized successfully');

      if (languages.isEmpty) {
        print(
            'OnScreenTranslator: No languages received from backend, this is an error!');
        throw Exception('No supported languages received from backend');
      }

      setState(() {
        _supportedLanguages = languages;

        // Set default languages
        _sourceLanguage = _supportedLanguages.firstWhere(
          (lang) => lang.code == 'en',
          orElse: () => _supportedLanguages.first,
        );
        _targetLanguage = _supportedLanguages.firstWhere(
          (lang) => lang.code == 'ko',
          orElse: () => _supportedLanguages.length > 1
              ? _supportedLanguages[1]
              : _supportedLanguages.first,
        );

        print(
            'OnScreenTranslator: Default source language: ${_sourceLanguage?.code}');
        print(
            'OnScreenTranslator: Default target language: ${_targetLanguage?.code}');

        _isLoading = false;
      });

      // Start scale animation
      _scaleController.forward();

      // Don't start listening automatically - wait for user to press Start button
      print(
          'OnScreenTranslator: Services initialized. Ready for user to start listening.');
    } catch (e) {
      print('OnScreenTranslator: Error loading languages: $e');
      setState(() {
        _isLoading = false;
        // Still need some fallback languages for the app to work
        _supportedLanguages = [
          Language(code: 'en', name: 'English', nativeName: 'English'),
          Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
          Language(code: 'es', name: 'Spanish', nativeName: 'Español'),
          Language(code: 'fr', name: 'French', nativeName: 'Français'),
          Language(code: 'de', name: 'German', nativeName: 'Deutsch'),
        ];
        _sourceLanguage = _supportedLanguages.first;
        _targetLanguage = _supportedLanguages.length > 1
            ? _supportedLanguages[1]
            : _supportedLanguages.first;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _fadeController.dispose();
    _scaleController.dispose();
    _textScrollController.dispose();

    // Clean up continuous listening
    _stopContinuousListening();

    // Stop any ongoing TTS playback
    _ttsService.stop();

    // Cancel silent detector timer
    _silentDetectorTimer?.cancel();

    super.dispose();
  }

  Future<void> _performTranslation(String text) async {
    if (text.isEmpty || _sourceLanguage == null || _targetLanguage == null) {
      setState(() {
        _translatedText = '';
        _hasTranslation = false;
      });
      return;
    }

    // Check if translation is needed
    if (!TranslationService.isTranslationNeeded(
        _sourceLanguage!.code, _targetLanguage!.code)) {
      setState(() {
        _translatedText = text;
        _hasTranslation = true;
      });
      _fadeController.forward();
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    try {
      print('OnScreenTranslator: Starting translation...');
      print(
          'Source: ${_sourceLanguage!.code}, Target: ${_targetLanguage!.code}');
      print('Content: $text');

      final result = await TranslationService.translateText(
        sourceLanguage: _sourceLanguage!.code,
        targetLanguage: _targetLanguage!.code,
        content: text,
      );

      setState(() {
        _isTranslating = false;
        if (result != null) {
          _translatedText = result.translatedText;
          _hasTranslation = true;
          print(
              'OnScreenTranslator: Translation successful: ${result.translatedText}');
        } else {
          _translatedText = 'Translation failed. Please try again.';
          _hasTranslation = false;
          print('OnScreenTranslator: Translation failed');
        }
      });

      _fadeController.forward();

      // Auto-scroll to show translation result
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isTranslating = false;
        _translatedText = 'Translation error: $e';
        _hasTranslation = false;
      });
      print('OnScreenTranslator: Translation error: $e');
    }
  }

  void _swapLanguages() {
    HapticFeedback.selectionClick();

    setState(() {
      final temp = _sourceLanguage;
      _sourceLanguage = _targetLanguage;
      _targetLanguage = temp;

      // Clear texts when swapping
      _recognizedText = '';
      _translatedText = '';
    });

    _fadeController.reset();
  }

  void _clearText() {
    HapticFeedback.selectionClick();

    setState(() {
      _recognizedText = '';
      _translatedText = '';
    });

    _fadeController.reset();
  }

  void _playSourceText() async {
    HapticFeedback.lightImpact();

    if (_recognizedText.isEmpty || _sourceLanguage == null) {
      print(
          'OnScreenTranslator: Cannot play source text - empty text or no language');
      return;
    }

    // Check if TTS is available
    final isAvailable = await _ttsService.isAvailable();
    if (!isAvailable) {
      print(
          'OnScreenTranslator: TTS service not available, trying to reinitialize...');
      try {
        await _ttsService.initialize();
      } catch (e) {
        print('OnScreenTranslator: Failed to reinitialize TTS: $e');
        _showError('Audio service unavailable. Please restart the app.');
        return;
      }
    }

    try {
      print(
          'OnScreenTranslator: Playing source text in ${_sourceLanguage!.code}');

      // Auto-mute STT during TTS playback
      _setTTSPlaying(true);

      final success = await _ttsService.speak(
        text: _recognizedText,
        languageCode: _sourceLanguage!.code,
      );

      // Auto-unmute STT after TTS playback
      _setTTSPlaying(false);

      if (!success) {
        print('OnScreenTranslator: Failed to play source text');
        _showError('Failed to play audio. Please try again.');
      }
    } catch (e) {
      print('OnScreenTranslator: Error playing source text: $e');
      _showError('Audio playback error: $e');
      // Ensure STT is unmuted even if TTS fails
      _setTTSPlaying(false);
    }
  }

  void _playTranslatedText() async {
    HapticFeedback.lightImpact();

    if (_translatedText.isEmpty ||
        _targetLanguage == null ||
        !_hasTranslation) {
      print(
          'OnScreenTranslator: Cannot play translated text - empty text or no language');
      return;
    }

    // Check if TTS is available
    final isAvailable = await _ttsService.isAvailable();
    if (!isAvailable) {
      print(
          'OnScreenTranslator: TTS service not available, trying to reinitialize...');
      try {
        await _ttsService.initialize();
      } catch (e) {
        print('OnScreenTranslator: Failed to reinitialize TTS: $e');
        _showError('Audio service unavailable. Please restart the app.');
        return;
      }
    }

    try {
      print(
          'OnScreenTranslator: Playing translated text in ${_targetLanguage!.code}');

      // Auto-mute STT during TTS playback
      _setTTSPlaying(true);

      final success = await _ttsService.speak(
        text: _translatedText,
        languageCode: _targetLanguage!.code,
      );

      // Auto-unmute STT after TTS playback
      _setTTSPlaying(false);

      if (!success) {
        print('OnScreenTranslator: Failed to play translated text');
        _showError('Failed to play audio. Please try again.');
      }
    } catch (e) {
      print('OnScreenTranslator: Error playing translated text: $e');
      _showError('Audio playback error: $e');
      // Ensure STT is unmuted even if TTS fails
      _setTTSPlaying(false);
    }
  }

  // ==================== CONTINUOUS STT AND SLOT-BASED PROCESSING ====================

  /// Start continuous listening when screen opens
  Future<void> _startContinuousListening() async {
    if (_isContinuousListening) return;

    print('OnScreenTranslator: Starting continuous listening...');

    try {
      await _speechService.initialize();

      // Set up speech recognition callbacks
      _speechService.setOnResult((text) {
        _onSpeechResult(text);
      });

      _speechService.setOnPartialResult((text) {
        _onSpeechPartialResult(text);
      });

      // Start continuous listening
      await _speechService.startListening();

      setState(() {
        _isContinuousListening = true;
      });

      // Start animations
      _pulseController.repeat(reverse: true);
      _waveController.repeat();

      // Start the first slot
      _startNewSlot();

      print('OnScreenTranslator: Continuous listening started successfully');
    } catch (e) {
      print('OnScreenTranslator: Failed to start continuous listening: $e');
      _showError('Failed to start continuous listening: $e');
    }
  }

  /// Stop continuous listening when screen closes
  void _stopContinuousListening() {
    if (!_isContinuousListening) return;

    print('OnScreenTranslator: Stopping continuous listening...');

    _speechService.stopListening();
    _silentDetectorTimer?.cancel();

    setState(() {
      _isContinuousListening = false;
      _transcribedText = '';
    });

    print('OnScreenTranslator: Continuous listening stopped');
  }

  /// Start a new slot - reset transcribedText and prepare for new speech
  void _startNewSlot() {
    print('OnScreenTranslator: Starting new slot...');

    setState(() {
      _transcribedText = '';
      _recognizedText = '';
      // Don't clear translated text immediately - let it stay until new translation
      _isTranslating = false;
    });

    // Cancel any existing silent detector timer
    _silentDetectorTimer?.cancel();

    // Ensure continuous listening is still active
    if (_isContinuousListening && !_isMuted && !_isTTSPlaying) {
      _ensureContinuousListening();
    }

    print('OnScreenTranslator: New slot started');
  }

  /// Ensure continuous listening is active
  void _ensureContinuousListening() async {
    try {
      // Check if speech service is still listening
      final isListening = _speechService.isListening;
      if (!isListening) {
        print('OnScreenTranslator: Speech service stopped, restarting...');
        await _speechService.startListening();
        print('OnScreenTranslator: Speech service restarted successfully');
      }
    } catch (e) {
      print('OnScreenTranslator: Error ensuring continuous listening: $e');
      // Try to restart continuous listening
      try {
        await _startContinuousListening();
      } catch (restartError) {
        print(
            'OnScreenTranslator: Failed to restart continuous listening: $restartError');
      }
    }
  }

  /// Handle final speech recognition result
  void _onSpeechResult(String text) {
    if (_isMuted || _isTTSPlaying) return;

    print('OnScreenTranslator: Speech result: "$text"');

    if (text.trim().isNotEmpty) {
      setState(() {
        _transcribedText = text.trim();
        _recognizedText = text.trim();
        // Clear previous translation when new speech is detected
        _translatedText = '';
        _hasTranslation = false;
      });

      // Auto-scroll to show new text
      _scrollToBottom();

      // Reset silent detector timer
      _resetSilentDetectorTimer();
    }
  }

  /// Handle partial speech recognition result
  void _onSpeechPartialResult(String text) {
    if (_isMuted || _isTTSPlaying) return;

    if (text.trim().isNotEmpty) {
      setState(() {
        _transcribedText = text.trim();
        _recognizedText = text.trim();
        // Clear previous translation when new speech is detected
        _translatedText = '';
        _hasTranslation = false;
      });

      // Auto-scroll to show new text
      _scrollToBottom();

      // Reset silent detector timer on new text
      _resetSilentDetectorTimer();
    }
  }

  /// Reset the silent detector timer
  void _resetSilentDetectorTimer() {
    _silentDetectorTimer?.cancel();

    if (_transcribedText.isNotEmpty) {
      _silentDetectorTimer = Timer(_silentTimeout, () {
        print('OnScreenTranslator: Silent timeout reached, processing slot...');
        _processCurrentSlot();
      });

      print('OnScreenTranslator: Silent detector timer reset (3 seconds)');
    }
  }

  /// Process the current slot - send transcribedText for translation
  void _processCurrentSlot() async {
    if (_transcribedText.isEmpty || _isTranslating) return;

    print('OnScreenTranslator: Processing slot with text: "$_transcribedText"');

    setState(() {
      _isTranslating = true;
    });

    try {
      await _performTranslation(_transcribedText);
      print(
          'OnScreenTranslator: Slot processing completed, starting new slot...');
    } catch (e) {
      print('OnScreenTranslator: Error processing slot: $e');
      _showError('Translation failed: $e');
    } finally {
      setState(() {
        _isTranslating = false;
      });

      // Start new slot after processing is complete
      _startNewSlot();
    }
  }

  /// Toggle mute/unmute for user control
  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });

    if (_isMuted) {
      print('OnScreenTranslator: User muted STT');
      _silentDetectorTimer?.cancel();
    } else {
      print('OnScreenTranslator: User unmuted STT');
      // Ensure continuous listening is active when unmuting
      if (_isContinuousListening && !_isTTSPlaying) {
        _ensureContinuousListening();
      }
      if (_transcribedText.isNotEmpty) {
        _resetSilentDetectorTimer();
      }
    }

    HapticFeedback.lightImpact();
  }

  /// Auto-mute during TTS playback
  void _setTTSPlaying(bool isPlaying) {
    setState(() {
      _isTTSPlaying = isPlaying;
    });

    if (isPlaying) {
      print('OnScreenTranslator: Auto-muting STT during TTS playback');
      _silentDetectorTimer?.cancel();
    } else {
      print('OnScreenTranslator: Auto-unmuting STT after TTS playback');
      // Ensure continuous listening is active after TTS playback
      if (_isContinuousListening && !_isMuted) {
        _ensureContinuousListening();
      }
      if (_transcribedText.isNotEmpty && !_isMuted) {
        _resetSilentDetectorTimer();
      }
    }
  }

  /// Auto-scroll to bottom of text display
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_textScrollController.hasClients) {
        _textScrollController.animateTo(
          _textScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Handle Start button press - begin continuous listening
  Future<void> _handleStartListening() async {
    try {
      // Check microphone permission first
      final hasPermission =
          await _permissionService.requestMicrophonePermission();
      if (!hasPermission) {
        _showError('Microphone permission is required to start listening');
        return;
      }

      // Start continuous listening
      await _startContinuousListening();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listening started! Speak to begin translation.'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('OnScreenTranslator: Error starting listening: $e');
      _showError('Failed to start listening: $e');
    }
  }

  /// Handle Stop button press - stop continuous listening
  Future<void> _handleStopListening() async {
    try {
      _stopContinuousListening();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listening stopped.'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      print('OnScreenTranslator: Error stopping listening: $e');
      _showError('Failed to stop listening: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF667eea),
                Color(0xFF764ba2),
              ],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildLanguageSelectionCard(),
                      const SizedBox(height: 30),
                      _buildMicrophoneSection(),
                      const SizedBox(height: 30),
                      _buildTextDisplaySection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'On-screen Translator',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: _clearText,
            icon: const Icon(Icons.clear_all, color: Colors.white70, size: 24),
            tooltip: 'Clear all text',
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelectionCard() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            // Source Language - Left Side
            Expanded(
              child: _buildCompactLanguageCard(
                label: 'From',
                value: _sourceLanguage,
                onChanged: (language) {
                  setState(() {
                    _sourceLanguage = language;
                  });
                },
                icon: Icons.mic,
                color: const Color(0xFF667eea),
              ),
            ),

            // Swap Button - Center
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GestureDetector(
                onTap: _swapLanguages,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF667eea).withOpacity(0.8),
                        const Color(0xFF764ba2).withOpacity(0.8),
                      ],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667eea).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.swap_horiz,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),

            // Target Language - Right Side
            Expanded(
              child: _buildCompactLanguageCard(
                label: 'To',
                value: _targetLanguage,
                onChanged: (language) {
                  setState(() {
                    _targetLanguage = language;
                  });
                },
                icon: Icons.volume_up,
                color: const Color(0xFF764ba2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLanguageCard({
    required String label,
    required Language? value,
    required Function(Language?) onChanged,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        // Label with icon
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Language dropdown
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Language>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down, color: color, size: 18),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              items: _supportedLanguages.map((language) {
                return DropdownMenuItem<Language>(
                  value: language,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        language.nativeName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        language.name,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: onChanged,
              dropdownColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMicrophoneSection() {
    return Column(
      children: [
        // Status Display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isContinuousListening
                    ? (_isMuted ? Icons.mic_off : Icons.mic)
                    : Icons.play_circle_outline,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                _isContinuousListening
                    ? (_isMuted
                        ? 'Muted'
                        : (_isTTSPlaying ? 'TTS Playing' : 'Listening...'))
                    : 'Ready to Start',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Start/Stop Button with Sound Waves
        Stack(
          alignment: Alignment.center,
          children: [
            // Sound waves animation (only when listening)
            if (_isContinuousListening && !_isMuted && !_isTTSPlaying)
              ...List.generate(3, (index) {
                return AnimatedBuilder(
                  animation: _waveAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 120 + (index * 40),
                      height: 120 + (index * 40),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(
                            0.3 *
                                math
                                    .sin(_waveAnimation.value + index * 0.5)
                                    .abs(),
                          ),
                          width: 2,
                        ),
                      ),
                    );
                  },
                );
              }),

            // Start/Stop Button
            GestureDetector(
              onTap: _isContinuousListening
                  ? _handleStopListening
                  : _handleStartListening,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale:
                        (_isContinuousListening && !_isMuted && !_isTTSPlaying)
                            ? _pulseAnimation.value
                            : 1.0,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _isContinuousListening
                              ? (_isMuted
                                  ? [
                                      Colors.orange.shade400,
                                      Colors.orange.shade600
                                    ]
                                  : _isTTSPlaying
                                      ? [
                                          Colors.blue.shade400,
                                          Colors.blue.shade600
                                        ]
                                      : [
                                          Colors.green.shade400,
                                          Colors.green.shade600
                                        ])
                              : [Colors.blue.shade400, Colors.blue.shade600],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isContinuousListening
                                    ? (_isMuted
                                        ? Colors.orange
                                        : _isTTSPlaying
                                            ? Colors.blue
                                            : Colors.green)
                                    : Colors.blue)
                                .withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isContinuousListening
                            ? (_isMuted
                                ? Icons.mic_off
                                : _isTTSPlaying
                                    ? Icons.volume_up
                                    : Icons.stop)
                            : Icons.play_arrow,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Instructions
        Text(
          _isContinuousListening
              ? (_isMuted
                  ? 'Tap unmute to resume listening'
                  : _isTTSPlaying
                      ? 'TTS is playing...'
                      : _isTranslating
                          ? 'Translating...'
                          : 'Speaking... (auto-translates after 3s silence)')
              : 'Tap the play button to start listening',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 16,
          ),
        ),

        const SizedBox(height: 20),

        // Action Buttons (only show when listening)
        if (_isContinuousListening)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute/Unmute Button
              _buildActionButton(
                icon: _isMuted ? Icons.volume_off : Icons.volume_up,
                label: _isMuted ? 'Unmute' : 'Mute',
                onTap: _toggleMute,
                isActive: _isMuted,
              ),

              // Play Source Text Button
              _buildActionButton(
                icon: Icons.play_arrow,
                label: 'Play Source',
                onTap: _playSourceText,
                isActive: _recognizedText.isNotEmpty,
              ),

              // Play Translated Text Button
              _buildActionButton(
                icon: Icons.play_arrow,
                label: 'Play Translation',
                onTap: _playTranslatedText,
                isActive: _hasTranslation,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextDisplaySection() {
    return SingleChildScrollView(
      controller: _textScrollController,
      child: Column(
        children: [
          // Source Text Card
          if (_recognizedText.isNotEmpty)
            FadeTransition(
              opacity: _fadeAnimation,
              child: _buildTextCard(
                title: 'Recognized Text',
                text: _recognizedText,
                language: _sourceLanguage,
                onPlay: _playSourceText,
                color: const Color(0xFF667eea),
              ),
            ),

          if (_recognizedText.isNotEmpty &&
              (_translatedText.isNotEmpty || _isTranslating))
            const SizedBox(height: 20),

          // Translated Text Card
          if (_translatedText.isNotEmpty || _isTranslating)
            FadeTransition(
              opacity: _fadeAnimation,
              child: _buildTextCard(
                title: 'Translation',
                text: _isTranslating ? 'Translating...' : _translatedText,
                language: _targetLanguage,
                onPlay: _hasTranslation ? () => _playTranslatedText() : () {},
                color: const Color(0xFF764ba2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextCard({
    required String title,
    required String text,
    required Language? language,
    required VoidCallback onPlay,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              if (language != null)
                Text(
                  language.nativeName,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onPlay,
                icon: Icon(Icons.play_circle_outline, color: color),
                tooltip: 'Play audio',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
