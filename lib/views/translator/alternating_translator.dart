import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../services/config_service.dart' as config_service;
import '../../services/permission_service.dart';
import '../../services/bluetooth_service.dart';
import '../../services/audio_profile_service.dart';
import '../../services/google_stt_service.dart';
import '../../services/tts_service.dart';

class AlternatingTranslator extends StatefulWidget {
  const AlternatingTranslator({super.key});

  @override
  State<AlternatingTranslator> createState() => _AlternatingTranslatorState();
}

class _AlternatingTranslatorState extends State<AlternatingTranslator>
    with TickerProviderStateMixin {
  // Services
  final config_service.ConfigService _configService =
      config_service.ConfigService.instance;
  final PermissionService _permissionService = PermissionService.instance;
  final BluetoothService _bluetoothService = BluetoothService();
  final AudioProfileService _audioProfileService = AudioProfileService();
  final GoogleSttService _googleSttService = GoogleSttService();
  final TTSService _ttsService = TTSService.instance;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _switchController;

  // Animations
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  late Animation<double> _switchAnimation;

  // Languages
  List<config_service.Language> _supportedLanguages = [];

  // Audio profiles and languages
  Map<AudioProfile, config_service.Language> _profileLanguages = {};
  AudioProfile _currentProfile = AudioProfile.phoneMicBluetoothSpeaker;

  // Recording and processing state
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isInitialized = false;
  bool _isBluetoothConnected = false;
  String _connectedDeviceName = 'No device';

  // Audio paths
  String? _currentRecordingPath;

  // Profile colors
  final Map<AudioProfile, Color> _profileColors = {
    AudioProfile.phoneMicBluetoothSpeaker: const Color(0xFF4CAF50), // Green
    AudioProfile.bluetoothMicPhoneSpeaker: const Color(0xFF2196F3), // Blue
  };

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeServices();
  }

  void _initializeAnimations() {
    // Pulse animation for recording button
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Wave animation for recording indicator
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _waveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.linear),
    );

    // Switch animation for profile transition
    _switchController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _switchAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _switchController, curve: Curves.easeInOut),
    );
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

      // Initialize audio profile service
      final profileInitialized = await _audioProfileService.initialize();
      if (!profileInitialized) {
        _showError('Failed to initialize audio profiles');
        return;
      }

      // Initialize Google STT
      final sttInitialized = await _googleSttService.initialize();
      if (!sttInitialized) {
        _showError('Google STT not configured');
        return;
      }

      // Initialize TTS
      await _ttsService.initialize();

      // Check Bluetooth connection
      await _checkBluetoothConnection();

      // Load supported languages
      final configLanguages = await _configService.getSupportedLanguages();
      if (configLanguages.isEmpty) {
        throw Exception('No supported languages found');
      }

      setState(() {
        _supportedLanguages = configLanguages;
        // Set default languages for each profile
        _profileLanguages = {
          AudioProfile.phoneMicBluetoothSpeaker: configLanguages.firstWhere(
            (lang) => lang.code == 'en',
            orElse: () => configLanguages.first,
          ),
          AudioProfile.bluetoothMicPhoneSpeaker: configLanguages.firstWhere(
            (lang) => lang.code == 'es',
            orElse: () => configLanguages.length > 1
                ? configLanguages[1]
                : configLanguages.first,
          ),
        };
        _isInitialized = true;
      });

      debugPrint('AlternatingTranslator: Services initialized successfully');
    } catch (e) {
      debugPrint('AlternatingTranslator: Initialization error: $e');
      _showError('Failed to initialize translator: $e');
    }
  }

  Future<void> _checkBluetoothConnection() async {
    try {
      await _bluetoothService.initialize();
      final deviceInfo = await _bluetoothService.checkConnection();

      setState(() {
        _isBluetoothConnected = deviceInfo.isConnected;
        _connectedDeviceName = deviceInfo.deviceName;
      });

      if (!_isBluetoothConnected && mounted) {
        _showBluetoothPrompt();
      }
    } catch (e) {
      debugPrint('AlternatingTranslator: Error checking Bluetooth: $e');
      setState(() {
        _isBluetoothConnected = false;
        _connectedDeviceName = 'Error checking device';
      });
    }
  }

  void _showBluetoothPrompt() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1D1E33),
          title: const Text('Bluetooth Required',
              style: TextStyle(color: Colors.white)),
          content: const Text(
              'Please connect a stereo Bluetooth headset to use this feature.',
              style: TextStyle(color: Colors.white70)),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.redAccent)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Check Connection',
                  style: TextStyle(color: Colors.blueAccent)),
              onPressed: () async {
                Navigator.of(context).pop();
                await _checkBluetoothConnection();
              },
            ),
          ],
        );
      },
    );
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
      if (!_isBluetoothConnected) {
        _showBluetoothPrompt();
        return;
      }

      if (await _audioRecorder.hasPermission()) {
        // Generate file path for recording
        final Directory appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _currentRecordingPath =
            '${appDir.path}/alternating_recording_$timestamp.wav';

        debugPrint(
            'AlternatingTranslator: Recording to: $_currentRecordingPath');

        // Start recording (mono)
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
          ),
          path: _currentRecordingPath!,
        );

        setState(() {
          _isRecording = true;
        });

        _pulseController.repeat(reverse: true);
        _waveController.repeat();

        debugPrint('AlternatingTranslator: Recording started');
      } else {
        _showError('Microphone permission denied');
      }
    } catch (e) {
      debugPrint('AlternatingTranslator: Error starting recording: $e');
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
        debugPrint('AlternatingTranslator: Recording stopped, processing...');
        await _processAudio(audioPath);
      } else {
        _showError('No audio recorded');
      }
    } catch (e) {
      debugPrint('AlternatingTranslator: Error stopping recording: $e');
      _showError('Failed to stop recording: $e');
    }
  }

  Future<void> _processAudio(String audioPath) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      debugPrint('AlternatingTranslator: Processing audio from: $audioPath');

      // Read audio file
      final File audioFile = File(audioPath);
      final Uint8List audioBytes = await audioFile.readAsBytes();

      // Get current profile language
      final currentLanguage = _profileLanguages[_currentProfile]!;
      final languageCode = _getGoogleLanguageCode(currentLanguage.code);

      debugPrint(
          'AlternatingTranslator: Transcribing in ${currentLanguage.name}');

      // Transcribe with Google STT
      final result = await _googleSttService.transcribeWithDiarization(
        audioBytes: audioBytes,
        languageCode: languageCode,
        minSpeakers: 1,
        maxSpeakers: 2,
      );

      if (result != null && result.segments.isNotEmpty) {
        final transcript = result.segments.map((s) => s.text).join(' ');
        debugPrint('AlternatingTranslator: Transcribed: $transcript');

        // Translate to the other profile's language
        final otherProfile =
            _currentProfile == AudioProfile.phoneMicBluetoothSpeaker
                ? AudioProfile.bluetoothMicPhoneSpeaker
                : AudioProfile.phoneMicBluetoothSpeaker;

        final targetLanguage = _profileLanguages[otherProfile]!;
        final targetLanguageCode = _getGoogleLanguageCode(targetLanguage.code);

        debugPrint(
            'AlternatingTranslator: Translating to ${targetLanguage.name}');

        // For now, we'll use the same text (you can integrate with translation service)
        final translatedText = transcript; // TODO: Add actual translation

        // Play TTS on the appropriate output
        await _playTts(translatedText, targetLanguageCode);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Transcribed: $transcript'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        _showError('No speech detected');
      }

      // Clean up audio file
      await audioFile.delete();
    } catch (e) {
      debugPrint('AlternatingTranslator: Error processing audio: $e');
      _showError('Failed to process audio: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _playTts(String text, String languageCode) async {
    try {
      debugPrint('AlternatingTranslator: Playing TTS: $text');
      await _ttsService.speak(text: text, languageCode: languageCode);
    } catch (e) {
      debugPrint('AlternatingTranslator: Error playing TTS: $e');
      _showError('Failed to play translation');
    }
  }

  Future<void> _toggleAudioProfile() async {
    try {
      debugPrint('AlternatingTranslator: Toggling audio profile');

      // Start switch animation
      _switchController.forward();

      // Toggle profile
      final success = await _audioProfileService.toggleAudioProfile();

      if (success) {
        setState(() {
          _currentProfile = _audioProfileService.currentProfile;
        });

        debugPrint(
            'AlternatingTranslator: Switched to ${_audioProfileService.currentProfileDescription}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Switched to: ${_audioProfileService.currentProfileDescription}'),
              backgroundColor: _profileColors[_currentProfile],
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        _showError('Failed to switch audio profile');
      }

      // Reset animation
      await Future.delayed(const Duration(milliseconds: 500));
      _switchController.reset();
    } catch (e) {
      debugPrint('AlternatingTranslator: Error toggling profile: $e');
      _showError('Failed to switch audio profile');
      _switchController.reset();
    }
  }

  String _getGoogleLanguageCode(String code) {
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
      'bn': 'bn-IN',
    };
    return languageMap[code] ?? 'en-US';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _switchController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _audioProfileService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E21),
        appBar: AppBar(
          title: const Text('Alternating Translator'),
          backgroundColor: const Color(0xFF1D1E33),
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF00D9FF),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        title: const Text('Alternating Translator'),
        backgroundColor: const Color(0xFF1D1E33),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth),
            onPressed: _checkBluetoothConnection,
            tooltip: 'Check Bluetooth',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBluetoothStatusCard(),
                const SizedBox(height: 24),
                _buildCurrentProfileCard(),
                const SizedBox(height: 24),
                _buildProfileLanguageSelector(
                    AudioProfile.phoneMicBluetoothSpeaker),
                const SizedBox(height: 16),
                _buildProfileLanguageSelector(
                    AudioProfile.bluetoothMicPhoneSpeaker),
                const SizedBox(height: 32),
                _buildRecordingSection(),
                const SizedBox(height: 32),
                _buildSwitchButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBluetoothStatusCard() {
    return Card(
      color: const Color(0xFF2A2B40),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isBluetoothConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: _isBluetoothConnected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  _isBluetoothConnected ? 'Connected' : 'Not Connected',
                  style: TextStyle(
                    color: _isBluetoothConnected
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Device: $_connectedDeviceName',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentProfileCard() {
    final currentColor = _profileColors[_currentProfile]!;

    return Card(
      color: const Color(0xFF2A2B40),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _currentProfile == AudioProfile.phoneMicBluetoothSpeaker
                      ? Icons.phone_android
                      : Icons.headset,
                  color: currentColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Current Profile',
                  style: TextStyle(
                    color: currentColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _audioProfileService.currentProfileDescription,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Input: ${_audioProfileService.currentInputSource}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            Text(
              'Output: ${_audioProfileService.currentOutputDestination}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileLanguageSelector(AudioProfile profile) {
    final selectedLanguage = _profileLanguages[profile];
    final profileColor = _profileColors[profile]!;
    final isCurrentProfile = profile == _currentProfile;

    return Card(
      color: const Color(0xFF2A2B40),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrentProfile ? profileColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  profile == AudioProfile.phoneMicBluetoothSpeaker
                      ? Icons.phone_android
                      : Icons.headset,
                  color: profileColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  profile == AudioProfile.phoneMicBluetoothSpeaker
                      ? 'Profile A: Phone → TWS'
                      : 'Profile B: TWS → Phone',
                  style: TextStyle(
                    color: profileColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isCurrentProfile) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: profileColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1D1E33),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: profileColor.withOpacity(0.3), width: 1),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<config_service.Language>(
                  value: selectedLanguage,
                  dropdownColor: const Color(0xFF1D1E33),
                  isExpanded: true,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  icon: Icon(Icons.arrow_drop_down, color: profileColor),
                  items: _supportedLanguages
                      .map((config_service.Language language) {
                    return DropdownMenuItem<config_service.Language>(
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
                  onChanged: (config_service.Language? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _profileLanguages[profile] = newValue;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingSection() {
    return Column(
      children: [
        if (_isRecording || _isProcessing) ...[
          AnimatedBuilder(
            animation: _waveAnimation,
            builder: (context, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => Container(
                    width: 8 * _waveAnimation.value,
                    height: 8 * _waveAnimation.value,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording
                          ? _profileColors[_currentProfile]
                          : Colors.grey,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            _isRecording ? 'Recording...' : 'Processing...',
            style: TextStyle(
              color: _profileColors[_currentProfile],
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 24),
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
                              _profileColors[_currentProfile]!.withOpacity(0.7),
                              _profileColors[_currentProfile]!
                            ]
                          : [const Color(0xFF00D9FF), const Color(0xFF0091EA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording
                                ? _profileColors[_currentProfile]
                                : const Color(0xFF00D9FF))!
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
    );
  }

  Widget _buildSwitchButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Switch Audio Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _switchAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (_switchAnimation.value * 0.1),
              child: ElevatedButton.icon(
                onPressed: _toggleAudioProfile,
                icon: const Icon(Icons.swap_horiz, color: Colors.white),
                label: const Text(
                  'Switch Profile',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D9FF),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Toggle between Phone↔Bluetooth audio routing',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
