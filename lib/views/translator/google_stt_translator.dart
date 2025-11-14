import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:noise_meter/noise_meter.dart';

import '../../services/config_service.dart';
// Audio route is handled via a platform channel call to avoid build-time issues
import '../../services/permission_service.dart';
import '../../services/translation_service.dart';
import '../../services/tts_service.dart';
import '../../services/enhanced_tts_service_robust.dart';
import '../../services/native_audio_recorder_service.dart';
import '../../services/stt_provider.dart';
import '../../services/google_stt_provider.dart';
import '../../services/soniox_realtime_service.dart';
import '../../services/streaming_audio_recorder_service.dart';

/// Google STT Translation - Records 2 speakers, performs on-device diarization,
/// and separates audio into individual speaker files for playback
class GoogleSTTTranslator extends StatefulWidget {
  final SttProvider? provider;
  const GoogleSTTTranslator({super.key, this.provider});

  @override
  State<GoogleSTTTranslator> createState() => _GoogleSTTTranslatorState();
}

class _GoogleSTTTranslatorState extends State<GoogleSTTTranslator>
    with TickerProviderStateMixin {
  // Services
  final ConfigService _configService = ConfigService.instance;
  final PermissionService _permissionService = PermissionService.instance;
  // STT provider (Google by default). Can be injected for AssemblyAI.
  late final SttProvider _sttProvider;

  // Translation service uses backend API (Azure Translator)
  final TtsService _ttsService = TtsService();
  final EnhancedTtsServiceRobust _stereoTtsService = EnhancedTtsServiceRobust();
  final NativeAudioRecorderService _nativeRecorder =
      NativeAudioRecorderService();
  final AudioPlayer _speaker1Player = AudioPlayer();
  final AudioPlayer _speaker2Player = AudioPlayer();
  final AudioPlayer _soundEffectPlayer =
      AudioPlayer(); // For recording start/stop sounds

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

  // Speaker gender and earpiece configuration
  Map<int, String> _speakerGenders = {}; // 0: 'male', 1: 'female'
  Map<int, String> _speakerEarpieces = {}; // 0: 'left', 1: 'right'

  // Recording state
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isStartingSession = false;

  // Real-time translation mode (NEW)
  bool _isRealtimeMode = false; // Toggle between manual and real-time mode
  final SonioxRealtimeService _sonioxService = SonioxRealtimeService();
  final StreamingAudioRecorderService _streamingRecorder = StreamingAudioRecorderService();
  StreamSubscription<SonioxResult>? _sonioxStreamSubscription;
  StreamSubscription<Uint8List>? _audioChunkSubscription;
  Timer? _audioPollingTimer; // Timer for polling audio file
  int _lastReadPosition = 0; // Track last read position in audio file
  Map<int, StringBuffer> _realtimeTranscriptions = {}; // Accumulate transcriptions per speaker
  Map<int, StringBuffer> _realtimeTranslations = {}; // Accumulate translations per speaker

  // Audio paths
  String? _recordedAudioPath;
  String? _speaker1AudioPath;
  String? _speaker2AudioPath;

  // TTS audio file paths (translated text to speech)
  String? _speaker1TtsAudioPath; // Speaker 1's translated text as audio
  String? _speaker2TtsAudioPath; // Speaker 2's translated text as audio
  String? _cachedStereoAudioPath; // Cached stereo audio file path

  // API optimization: Store Voice 2's inferred language (no need to test both)
  String?
      _voice2InferredLanguage; // Voice 2's language inferred from Voice 1's detection
  Map<String, dynamic>?
      _voice1CachedTranscription; // Store Voice 1's transcription from detection phase

  // TTS playback states
  bool _isPlayingTts1 = false; // Playing Speaker 1's translated audio
  bool _isPlayingTts2 = false; // Playing Speaker 2's translated audio

  // Stereo audio playback state
  bool _isPlayingStereo = false;
  // Defer TTS cleanup until stereo playback completes
  bool _pendingStereoPlaybackCleanup = false;

  // Per-session cache for STT calls: key = "<audioPath>|<langCode>"
  final Map<String, Map<String, dynamic>> _sttCache = {};

  // Cache for original audio bytes to avoid redundant file reads
  Uint8List? _cachedOriginalAudioBytes;

  // Note: Using SystemSound for sound effects instead of AudioPlayer

  // Automatic translation system state
  bool _isAutomaticMode = false;
  bool _isContinuousRecording = false;
  double _currentSoundLevel = 0.0;
  List<double> _soundLevelHistory = [];
  Timer? _silentDetectionTimer;
  int _silentDetectionCountdown = 0;
  bool _isSilentDetectionActive = false;

  // Manual testing controls
  bool _isManualTestingMode = false;
  double _manualAmplitude = 0.0;

  // Real-time microphone amplitude monitoring
  NoiseMeter? _noiseMeter;
  StreamSubscription<NoiseReading>? _noiseSubscription;

  // Sound level thresholds for speech detection
  static const double _minSpeechLevel =
      0.75; // Minimum level to consider as speech (75% - corresponds to ~67.5 dB)
  // Increased from 40% to avoid false triggers from background noise (fans, AC, etc.)
  static const double _maxSpeechLevel = 1.0; // Maximum level for normal speech
  static const int _silentDetectionDuration =
      3; // 3 seconds of silence before stopping

  // Speech continuity tracking to avoid false triggers from brief noise spikes
  int _consecutiveSpeechDetections = 0;
  static const int _minConsecutiveSpeechDetections =
      3; // Require 3 consecutive detections (300ms) to confirm speech

  // Track if any speech has been detected in current recording session
  bool _hasDetectedSpeechInSession = false;

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

  // Platform-channel helper: force phone mic even if BT/TWS connected
  static const MethodChannel _audioRouteChannel = MethodChannel('audio_route');
  Future<void> _forcePhoneMic() async {
    try {
      await _audioRouteChannel.invokeMethod('forcePhoneMic');
      debugPrint('GoogleSTTTranslator: Forced phone mic via platform channel');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Failed to force phone mic: $e');
    }
  }

  Future<void> _enterRecordingRoute() async {
    try {
      await _audioRouteChannel.invokeMethod('enterRecordingRoute');
      debugPrint('GoogleSTTTranslator: Entered recording route (phone mic)');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Failed to enter recording route: $e');
    }
  }

  Future<void> _enterPlaybackRoute() async {
    try {
      await _audioRouteChannel.invokeMethod('enterPlaybackRoute');
      debugPrint(
          'GoogleSTTTranslator: Entered playback route (prefer BT A2DP)');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Failed to enter playback route: $e');
    }
  }

  /// Check if a WAV file contains meaningful audio (not just a tiny/silent file)
  /// Returns true when file size is above minimal WAV header and not trivially tiny
  Future<bool> _hasMeaningfulAudio(String path,
      {required int speakerIndex}) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint(
            'GoogleSTTTranslator: Speaker $speakerIndex audio missing: $path');
        return false;
      }
      final size = await file.length();
      // 44 bytes = WAV header only; use a conservative threshold (~1KB) to avoid empty streams
      const int minBytes = 1024;
      debugPrint(
          'GoogleSTTTranslator: Speaker $speakerIndex audio size: $size bytes');
      if (size <= 44 || size < minBytes) {
        debugPrint(
            'GoogleSTTTranslator: Skipping STT for Speaker $speakerIndex - audio too small');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint(
          'GoogleSTTTranslator: Audio check error for Speaker $speakerIndex: $e');
      return false;
    }
  }

  Future<void> _initializeServices() async {
    try {
      _sttProvider = (widget.provider ?? GoogleSttProvider());
      await _sttProvider.initialize();

      // Translation service is now backend-based (Azure Translator API)
      // No initialization needed - uses backend API
      await _ttsService.initialize();
      await _stereoTtsService.initialize();

      // Set up TTS service callbacks for UI state synchronization
      _ttsService.setPlaybackCompletedCallback(() {
        if (mounted) {
          setState(() {
            _isPlayingTts1 = false;
            _isPlayingTts2 = false;
          });
          debugPrint(
              'GoogleSTTTranslator: TTS playback completed - UI state updated');
        }
      });

      _ttsService.setPlaybackErrorCallback(() {
        if (mounted) {
          setState(() {
            _isPlayingTts1 = false;
            _isPlayingTts2 = false;
          });
          debugPrint(
              'GoogleSTTTranslator: TTS playback error - UI state updated');
        }
      });

      // Set up unified stereo TTS service callback for both UI state and automatic mode
      _stereoTtsService.setPlaybackCompletedCallback(() async {
        debugPrint(
            'GoogleSTTTranslator: 🎵 Unified playback completion callback triggered!');
        debugPrint(
            '  _isAutomaticMode: $_isAutomaticMode, _isRecording: $_isRecording, _isPlayingStereo: $_isPlayingStereo');

        if (mounted) {
          setState(() {
            _isPlayingStereo = false;
          });
        }

        // Perform deferred cleanup of TTS files after playback completes
        if (_pendingStereoPlaybackCleanup) {
          debugPrint(
              'GoogleSTTTranslator: Performing deferred TTS cleanup after playback');
          await _cleanupTtsFiles();
          _pendingStereoPlaybackCleanup = false;
        }

        // Handle automatic mode restart
        if (_isAutomaticMode && !_isRecording) {
          debugPrint(
              'GoogleSTTTranslator: ✅ Automatic mode - stereo playback COMPLETED! Starting new cycle in 500ms...');

          setState(() {
            _isProcessing = false;
          });

          // Longer delay to ensure TTS audio has completely finished
          // This prevents the mic from capturing the previous cycle's TTS audio
          Future.delayed(const Duration(milliseconds: 1500), () {
            // Double-check conditions before starting new cycle
            if (_isAutomaticMode && !_isRecording && !_isPlayingStereo) {
              debugPrint(
                  'GoogleSTTTranslator: 🔄 Conditions met, starting new recording cycle...');
              debugPrint(
                  'GoogleSTTTranslator: ⏰ 1.5s delay ensures TTS audio has completely finished');
              _startAutomaticRecording();
            } else {
              debugPrint(
                  'GoogleSTTTranslator: ⚠️ Conditions not met for restart: mode=$_isAutomaticMode, recording=$_isRecording, playing=$_isPlayingStereo');
            }
          });
        } else {
          debugPrint(
              'GoogleSTTTranslator: Manual mode - stereo playback completed, UI state updated');
        }
      });

      _stereoTtsService.setPlaybackErrorCallback(() {
        if (mounted) {
          setState(() {
            _isPlayingStereo = false;
          });
          debugPrint(
              'GoogleSTTTranslator: Stereo TTS playback error - UI state updated');
        }
      });
      final languages = await _configService.getSupportedLanguages();
      final defaultEnglish = languages.firstWhere(
        (lang) => lang.code == 'en',
        orElse: () => languages.first,
      );

      final defaultBengali = languages.firstWhere(
        (lang) => lang.code == 'bn',
        orElse: () => languages.first,
      );

      setState(() {
        _supportedLanguages = languages;
        _speakerLanguages = {
          0: defaultEnglish,
          1: defaultBengali,
        };
        _speakerGenders = {
          0: 'male', // Default to male
          1: 'female', // Default to female
        };
        _speakerEarpieces = {
          0: 'left', // Default to left earpiece
          1: 'right', // Default to right earpiece
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

    // No model downloads needed - translation uses Azure Translator API via backend
    debugPrint(
        'GoogleSTTTranslator: ✅ Translation service ready (Azure Translator API)');

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
      // Stop recording based on mode
      if (_isRealtimeMode) {
        await _stopRealtimeSession();
      } else {
        await _stopRecording();
      }
    } else {
      // Start recording based on mode
      if (_isRealtimeMode) {
        await _startRealtimeSession();
      } else {
        await _startRecording();
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      debugPrint('GoogleSTTTranslator: ═══ Starting Recording ═══');

      final hasPermission =
          await _permissionService.requestMicrophonePermission();
      if (!hasPermission) {
        _showErrorDialog('Microphone permission is required for recording.');
        return;
      }

      // CRITICAL: Always force built-in mic for recording
      debugPrint(
          'GoogleSTTTranslator: Step 1: Configuring audio route for recording...');
      await _enterRecordingRoute();
      debugPrint('GoogleSTTTranslator: ✅ Audio route configured for RECORDING');

      // Add delay to ensure audio system has switched modes
      await Future.delayed(const Duration(milliseconds: 200));
      debugPrint('GoogleSTTTranslator: ✅ Audio system ready');

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordedAudioPath = '${directory.path}/recording_$timestamp.wav';

      debugPrint(
          'GoogleSTTTranslator: Step 2: Starting NATIVE audio recorder...');
      debugPrint('GoogleSTTTranslator: Recording path: $_recordedAudioPath');
      debugPrint(
          'GoogleSTTTranslator: Expected input: FORCED built-in microphone (MIC audio source)');

      // Play start recording sound effect
      await _playStartRecordingSound();

      // CRITICAL: Use native recorder that forces MIC audio source
      // This guarantees phone mic is used, not Bluetooth
      final bool recordingStarted =
          await _nativeRecorder.startRecording(_recordedAudioPath!);

      if (!recordingStarted) {
        debugPrint('GoogleSTTTranslator: ❌ Failed to start native recording');
        _showErrorDialog('Failed to start recording. Please try again.');
        return;
      }

      setState(() {
        _isRecording = true;
        // Clear previous results
        _speaker1AudioPath = null;
        _speaker2AudioPath = null;
        _speaker1TtsAudioPath = null;
        _speaker2TtsAudioPath = null;
        _cachedStereoAudioPath = null;
        _speakerSegments = [];
        _cachedOriginalAudioBytes = null; // Clear cached audio bytes

        // Keep gender and earpiece selections - don't reset user preferences
        // _speakerGenders and _speakerEarpieces are preserved
        _isPlayingStereo = false;
        _transcriptions.clear();
        _translations.clear();
        _showTranslation = {
          0: false,
          1: false,
        };
        _isPlayingTts1 = false;
        _isPlayingTts2 = false;
      });

      _pulseController.repeat(reverse: true);
      _waveController.repeat();

      debugPrint('GoogleSTTTranslator: ✅ Recording started successfully');
      debugPrint('GoogleSTTTranslator: Using built-in phone microphone');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: ❌ Recording error: $e');
      _showErrorDialog('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      // Play stop recording sound effect
      await _playStopRecordingSound();

      // CRITICAL: Stop sound level monitoring FIRST
      // This prevents mic from capturing during processing/playback phases
      _stopSoundLevelMonitoring();
      debugPrint(
          'GoogleSTTTranslator: ✅ Sound level monitoring stopped (mic OFF for playback)');

      // Stop the NATIVE audio recorder
      debugPrint('GoogleSTTTranslator: Stopping native audio recorder...');
      final String? recordedPath = await _nativeRecorder.stopRecording();

      if (recordedPath == null) {
        debugPrint('GoogleSTTTranslator: ❌ Failed to stop recording properly');
      } else {
        debugPrint('GoogleSTTTranslator: ✅ Recording saved: $recordedPath');
      }

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

  // ═══════════════════════════════════════════════════════════════
  // REAL-TIME MODE METHODS (NEW)
  // ═══════════════════════════════════════════════════════════════

  /// Start real-time translation session using Soniox
  Future<void> _startRealtimeSession() async {
    try {
      debugPrint('GoogleSTTTranslator: ═══ Starting Real-time Session ═══');

      final hasPermission =
          await _permissionService.requestMicrophonePermission();
      if (!hasPermission) {
        _showErrorDialog('Microphone permission is required for recording.');
        return;
      }

      setState(() {
        _isRecording = true;
        _isProcessing = false;
        // Clear previous results
        _speaker1AudioPath = null;
        _speaker2AudioPath = null;
        _speaker1TtsAudioPath = null;
        _speaker2TtsAudioPath = null;
        _cachedStereoAudioPath = null;
        _speakerSegments = [];
        _transcriptions.clear();
        _translations.clear();
        _realtimeTranscriptions = {0: StringBuffer(), 1: StringBuffer()};
        _realtimeTranslations = {0: StringBuffer(), 1: StringBuffer()};
        _showTranslation = {0: false, 1: false};
        _isPlayingTts1 = false;
        _isPlayingTts2 = false;
      });

      debugPrint('GoogleSTTTranslator: Configuring audio route for recording...');
      await _enterRecordingRoute();
      await Future.delayed(const Duration(milliseconds: 200));

      // Initialize Soniox service
      debugPrint('GoogleSTTTranslator: Initializing Soniox service...');
      await _sonioxService.initialize();

      // Connect to Soniox WebSocket
      final speaker1Lang = _speakerLanguages[0]?.code ?? 'en';
      final speaker2Lang = _speakerLanguages[1]?.code ?? 'bn';
      
      debugPrint('GoogleSTTTranslator: Connecting to Soniox...');
      debugPrint('GoogleSTTTranslator: Speaker 1 language: $speaker1Lang');
      debugPrint('GoogleSTTTranslator: Speaker 2 language: $speaker2Lang');

      await _sonioxService.connect(
        languageA: speaker1Lang,
        languageB: speaker2Lang,
        enableSpeakerDiarization: true,
      );

      // Set up callbacks
      _sonioxService.onConnected = () {
        debugPrint('GoogleSTTTranslator: ✅ Soniox connected - starting audio stream');
        _startAudioStreaming();
      };

      _sonioxService.onError = (error) {
        debugPrint('GoogleSTTTranslator: ❌ Soniox error: $error');
        _showErrorDialog('Real-time translation error: $error');
        _stopRealtimeSession();
      };

      _sonioxService.onDisconnected = () {
        debugPrint('GoogleSTTTranslator: ⚠️ Soniox disconnected');
      };

      // Listen to Soniox results
      _sonioxStreamSubscription = _sonioxService.resultStream?.listen(
        _handleSonioxResult,
        onError: (error) {
          debugPrint('GoogleSTTTranslator: ❌ Soniox stream error: $error');
        },
      );

      // Play start recording sound
      await _playStartRecordingSound();

      // Start native audio recording (fallback approach)
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordedAudioPath = '${directory.path}/realtime_recording_$timestamp.wav';

      debugPrint('GoogleSTTTranslator: Starting native audio recorder...');
      debugPrint('GoogleSTTTranslator: Recording path: $_recordedAudioPath');

      // Use existing native recorder (works immediately)
      final bool recordingStarted =
          await _nativeRecorder.startRecording(_recordedAudioPath!);

      if (!recordingStarted) {
        debugPrint('GoogleSTTTranslator: ❌ Failed to start native recording');
        _showErrorDialog('Failed to start recording. Please try again.');
        await _sonioxService.disconnect();
        return;
      }

      debugPrint('GoogleSTTTranslator: ✅ Native recording started');
      
      // Start polling audio file to send chunks to Soniox
      debugPrint('GoogleSTTTranslator: Starting audio file polling for streaming...');
      _startAudioFilePolling();

      _pulseController.repeat(reverse: true);
      _waveController.repeat();

      debugPrint('GoogleSTTTranslator: ✅ Real-time session started successfully');
      debugPrint('GoogleSTTTranslator: Audio chunks will be streamed to Soniox');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: ❌ Real-time session error: $e');
      _showErrorDialog('Failed to start real-time session: $e');
      setState(() {
        _isRecording = false;
      });
    }
  }

  /// Stop real-time translation session
  Future<void> _stopRealtimeSession() async {
    try {
      debugPrint('GoogleSTTTranslator: Stopping real-time session...');

      // Stop audio polling timer
      _audioPollingTimer?.cancel();
      _audioPollingTimer = null;
      _lastReadPosition = 0;

      // Stop audio chunk subscription (if using streaming recorder)
      await _audioChunkSubscription?.cancel();
      _audioChunkSubscription = null;

      // Play stop recording sound
      await _playStopRecordingSound();

      // Stop native audio recorder
      await _nativeRecorder.stopRecording();

      // Finalize Soniox stream
      await _sonioxService.finalizeAudio();
      await Future.delayed(const Duration(milliseconds: 500));

      // Disconnect from Soniox
      await _sonioxStreamSubscription?.cancel();
      await _sonioxService.disconnect();

      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });

      _pulseController.stop();
      _waveController.stop();

      debugPrint('GoogleSTTTranslator: ✅ Real-time session stopped');
      
      // Transfer accumulated text to main transcriptions/translations
      _transcriptions[0] = _realtimeTranscriptions[0]?.toString() ?? '';
      _transcriptions[1] = _realtimeTranscriptions[1]?.toString() ?? '';
      _translations[0] = _realtimeTranslations[0]?.toString() ?? '';
      _translations[1] = _realtimeTranslations[1]?.toString() ?? '';

      debugPrint('GoogleSTTTranslator: Final transcriptions:');
      debugPrint('  Speaker 0: ${_transcriptions[0]}');
      debugPrint('  Speaker 1: ${_transcriptions[1]}');
      debugPrint('GoogleSTTTranslator: Final translations:');
      debugPrint('  Speaker 0: ${_translations[0]}');
      debugPrint('  Speaker 1: ${_translations[1]}');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: ❌ Stop real-time session error: $e');
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
    }
  }

  /// Start streaming audio to Soniox in chunks
  /// NOTE: This method is no longer needed as streaming is handled by
  /// the audio chunk subscription in _startRealtimeSession
  void _startAudioStreaming() {
    debugPrint('GoogleSTTTranslator: ✅ Audio streaming already configured via subscription');
  }

  /// Start polling audio file to simulate streaming
  /// This is a fallback approach until native streaming is implemented
  void _startAudioFilePolling() {
    debugPrint('GoogleSTTTranslator: Starting audio file polling (100ms intervals)...');
    
    _lastReadPosition = 44; // Skip WAV header (44 bytes)
    
    // Poll every 100ms to read new audio data
    _audioPollingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      try {
        if (!_isRecording || _recordedAudioPath == null) {
          debugPrint('GoogleSTTTranslator: ⚠️ Stopping audio polling - recording stopped');
          timer.cancel();
          return;
        }

        final audioFile = File(_recordedAudioPath!);
        
        // Check if file exists
        if (!await audioFile.exists()) {
          debugPrint('GoogleSTTTranslator: ⚠️ Audio file does not exist yet');
          return;
        }

        // Get current file size
        final fileSize = await audioFile.length();
        
        // Check if there's new data to read
        if (fileSize > _lastReadPosition) {
          // Read new data
          final bytesToRead = fileSize - _lastReadPosition;
          
          // Limit chunk size to ~3200 bytes (100ms of 16kHz 16-bit mono audio)
          final chunkSize = bytesToRead > 3200 ? 3200 : bytesToRead;
          
          // Open file and read from last position
          final randomAccessFile = await audioFile.open(mode: FileMode.read);
          await randomAccessFile.setPosition(_lastReadPosition);
          final chunk = await randomAccessFile.read(chunkSize);
          await randomAccessFile.close();
          
          if (chunk.isNotEmpty) {
            // Send chunk to Soniox
            await _sonioxService.sendAudio(chunk);
            _lastReadPosition += chunk.length;
            
            debugPrint('GoogleSTTTranslator: 📤 Sent ${chunk.length} bytes to Soniox (position: $_lastReadPosition)');
          }
        }
      } catch (e) {
        debugPrint('GoogleSTTTranslator: ❌ Audio polling error: $e');
      }
    });
    
    debugPrint('GoogleSTTTranslator: ✅ Audio file polling started');
  }

  /// Handle Soniox real-time results (Transcription + Diarization ONLY)
  /// Translation will be done separately via Azure API
  void _handleSonioxResult(SonioxResult result) {
    try {
      debugPrint('GoogleSTTTranslator: ═══ Soniox Transcription Result ═══');
      debugPrint('GoogleSTTTranslator: Tokens count: ${result.tokens.length}');
      debugPrint('GoogleSTTTranslator: Speaker 1 language: ${_speakerLanguages[0]?.code}');
      debugPrint('GoogleSTTTranslator: Speaker 2 language: ${_speakerLanguages[1]?.code}');

      if (result.tokens.isEmpty) {
        debugPrint('GoogleSTTTranslator: ⚠️ No tokens in result');
        return;
      }

      // Group transcriptions by speaker
      Map<int, String> transcriptionTexts = {};
      Map<int, String> transcriptionLanguages = {};
      Map<int, bool> hasFinalized = {};
      
      // Process all tokens (transcription only, no translation from Soniox)
      for (var token in result.tokens) {
        debugPrint('GoogleSTTTranslator: Token: "${token.text}" | Lang: ${token.language} | Speaker: ${token.speaker} | Final: ${token.isFinal}');
        
        // Filter out special tokens like <end>, <unk>, etc.
        final tokenText = token.text.trim();
        if (tokenText.startsWith('<') && tokenText.endsWith('>')) {
          debugPrint('GoogleSTTTranslator: ⚠️ Skipping special token: $tokenText');
          continue; // Skip special tokens
        }
        
        // Skip empty tokens
        if (tokenText.isEmpty) {
          continue;
        }
        
        final sonioxSpeakerId = token.speaker ?? 0;
        final detectedLanguage = token.language;
        
        // Accumulate transcription text
        transcriptionTexts[sonioxSpeakerId] = (transcriptionTexts[sonioxSpeakerId] ?? '') + token.text;
        transcriptionLanguages[sonioxSpeakerId] = detectedLanguage;
        
        if (token.isFinal) {
          hasFinalized[sonioxSpeakerId] = true;
        }
      }

      // Process each speaker's transcription
      transcriptionTexts.forEach((sonioxSpeakerId, transcriptionText) {
        final detectedLanguage = transcriptionLanguages[sonioxSpeakerId] ?? '';
        final isFinal = hasFinalized[sonioxSpeakerId] ?? false;
        
        debugPrint('GoogleSTTTranslator: ═══ Processing Soniox Speaker $sonioxSpeakerId ═══');
        debugPrint('  Detected language: $detectedLanguage');
        debugPrint('  Transcription: "$transcriptionText"');
        debugPrint('  Is Final: $isFinal');
        
        // Map Soniox speaker to UI speaker based on detected language AND transcribed text
        // This helps detect phonetic transcriptions (e.g., English spoken but written in Bengali script)
        int uiSpeakerIndex = _mapSonioxSpeakerToUiSpeaker(sonioxSpeakerId, detectedLanguage, transcriptionText);
        
        debugPrint('GoogleSTTTranslator: Mapped Soniox Speaker $sonioxSpeakerId → UI Speaker $uiSpeakerIndex');
        debugPrint('GoogleSTTTranslator: UI Speaker $uiSpeakerIndex configured language: ${_speakerLanguages[uiSpeakerIndex]?.code}');

        // Initialize buffers if needed
        if (_realtimeTranscriptions[uiSpeakerIndex] == null) {
          _realtimeTranscriptions[uiSpeakerIndex] = StringBuffer();
        }
        if (_realtimeTranslations[uiSpeakerIndex] == null) {
          _realtimeTranslations[uiSpeakerIndex] = StringBuffer();
        }

        // For final results, append and translate
        if (isFinal) {
          if (transcriptionText.isNotEmpty) {
            // Append final transcription
            if (_realtimeTranscriptions[uiSpeakerIndex]!.isNotEmpty) {
              _realtimeTranscriptions[uiSpeakerIndex]!.write(' ');
            }
            _realtimeTranscriptions[uiSpeakerIndex]!.write(transcriptionText);
            debugPrint('GoogleSTTTranslator: ✅ Appended FINAL transcription to UI Speaker $uiSpeakerIndex');
          }

          // Update UI with transcription immediately
          if (mounted) {
            setState(() {
              _transcriptions[uiSpeakerIndex] = _realtimeTranscriptions[uiSpeakerIndex]?.toString().trim() ?? '';
            });
            debugPrint('GoogleSTTTranslator: ✅ UI updated with transcription for UI Speaker $uiSpeakerIndex');
          }

          // Translate using Azure API and generate TTS
          if (transcriptionText.isNotEmpty) {
            debugPrint('GoogleSTTTranslator: 🌐 Translating via Azure API...');
            _translateAndPlayRealtimeTts(
              speakerIndex: uiSpeakerIndex,
              transcribedText: transcriptionText.trim(),
              sourceLanguage: detectedLanguage,
            );
          }
        } else {
          // Non-final (interim) results: Show transcription temporarily
          if (mounted) {
            final accumulatedTranscription = _realtimeTranscriptions[uiSpeakerIndex]?.toString().trim() ?? '';
            final interimTranscription = transcriptionText.isNotEmpty
                ? '$accumulatedTranscription $transcriptionText'
                : accumulatedTranscription;

            setState(() {
              _transcriptions[uiSpeakerIndex] = interimTranscription.trim();
            });
            debugPrint('GoogleSTTTranslator: ✅ UI updated with INTERIM transcription for UI Speaker $uiSpeakerIndex');
          }
        }
      });
    } catch (e) {
      debugPrint('GoogleSTTTranslator: ❌ Error handling Soniox result: $e');
      debugPrint('GoogleSTTTranslator: Stack trace: ${StackTrace.current}');
    }
  }

  /// Map Soniox speaker ID to UI speaker index based on detected language
  /// This ensures that regardless of Soniox's speaker numbering, we display
  /// text in the correct speaker section based on the language they're speaking
  int _mapSonioxSpeakerToUiSpeaker(int sonioxSpeakerId, String detectedLanguage, String transcribedText) {
    // Get configured languages for our UI speakers
    final speaker1Lang = _speakerLanguages[0]?.code.toLowerCase() ?? '';
    final speaker2Lang = _speakerLanguages[1]?.code.toLowerCase() ?? '';
    final detectedLangLower = detectedLanguage.toLowerCase();
    
    debugPrint('GoogleSTTTranslator: Language Mapping:');
    debugPrint('  UI Speaker 0 configured: $speaker1Lang');
    debugPrint('  UI Speaker 1 configured: $speaker2Lang');
    debugPrint('  Detected language: $detectedLangLower');
    debugPrint('  Soniox speaker ID: $sonioxSpeakerId');
    debugPrint('  Transcribed text: "$transcribedText"');
    
    // Check if text is phonetically transcribed (English words in Bengali/other script)
    // If it looks like phonetic transcription, it might be the wrong language detection
    final isPhoneticBengali = _isPhoneticTranscription(transcribedText, detectedLangLower);
    if (isPhoneticBengali) {
      debugPrint('GoogleSTTTranslator: ⚠️ Detected phonetic transcription!');
      debugPrint('GoogleSTTTranslator: Likely English spoken but transcribed as $detectedLangLower');
      
      // If phonetic, assume it's actually the OTHER language
      if (detectedLangLower == speaker2Lang) {
        debugPrint('GoogleSTTTranslator: Mapping to UI Speaker 0 (likely English)');
        return 0;
      } else if (detectedLangLower == speaker1Lang) {
        debugPrint('GoogleSTTTranslator: Mapping to UI Speaker 1 (likely Bengali)');
        return 1;
      }
    }
    
    // Match based on language code
    // If detected language matches Speaker 1's language, map to Speaker 1 (index 0)
    // If detected language matches Speaker 2's language, map to Speaker 2 (index 1)
    if (detectedLangLower == speaker1Lang || detectedLangLower.startsWith(speaker1Lang)) {
      debugPrint('GoogleSTTTranslator: Language matches UI Speaker 0');
      return 0;
    } else if (detectedLangLower == speaker2Lang || detectedLangLower.startsWith(speaker2Lang)) {
      debugPrint('GoogleSTTTranslator: Language matches UI Speaker 1');
      return 1;
    }
    
    // Fallback: use Soniox's speaker ID directly
    debugPrint('GoogleSTTTranslator: ⚠️ No language match, using Soniox speaker ID: $sonioxSpeakerId');
    return sonioxSpeakerId;
  }

  /// Check if text appears to be phonetically transcribed
  /// (e.g., English words written in Bengali script like "গুড আফটারনুন")
  bool _isPhoneticTranscription(String text, String detectedLanguage) {
    if (detectedLanguage.toLowerCase() != 'bn') {
      return false; // Only check for Bengali phonetic transcription
    }
    
    // Common English words that appear phonetically in Bengali
    final phoneticIndicators = [
      'গুড', 'হাউ', 'আর', 'ইউ', 'হ্যালো', 'হাই', 'বাই', 'ইয়েস', 'নো',
      'ওকে', 'থ্যাংক', 'প্লিজ', 'সরি', 'এক্সকিউজ', 'মি', 'ওয়েলকাম',
      'আফটারনুন', 'মর্নিং', 'ইভনিং', 'ফাইন', 'নাইস', 'গ্রেট'
    ];
    
    // Check if text contains multiple phonetic indicators
    int phoneticCount = 0;
    for (final indicator in phoneticIndicators) {
      if (text.contains(indicator)) {
        phoneticCount++;
      }
    }
    
    // If 2 or more phonetic indicators, it's likely phonetic transcription
    return phoneticCount >= 2;
  }

  /// Translate transcribed text using Azure API and generate TTS
  Future<void> _translateAndPlayRealtimeTts({
    required int speakerIndex,
    required String transcribedText,
    required String sourceLanguage,
  }) async {
    try {
      debugPrint('GoogleSTTTranslator: ═══ Azure Translation + TTS ═══');
      debugPrint('GoogleSTTTranslator: Initial speaker: $speakerIndex');
      debugPrint('GoogleSTTTranslator: Soniox detected language: $sourceLanguage');
      debugPrint('GoogleSTTTranslator: Transcribed text: "$transcribedText"');

      // CHECK FOR PHONETIC TRANSCRIPTION FIRST
      final isPhonetic = _isPhoneticTranscription(transcribedText, sourceLanguage);
      
      int actualSpeakerIndex = speakerIndex;
      String actualSourceLanguage = sourceLanguage;
      String actualTranscribedText = transcribedText;
      
      if (isPhonetic) {
        debugPrint('GoogleSTTTranslator: ⚠️ PHONETIC DETECTED! Text is likely English written in Bengali script');
        
        // Phonetic transcription means:
        // - Soniox thought it was Bengali (sourceLanguage = 'bn')
        // - But it's actually English spoken and written phonetically
        // - So we need to:
        //   1. Map to the OTHER speaker (English speaker)
        //   2. Use English as the actual source language
        //   3. First translate the phonetic text back to proper English
        
        actualSpeakerIndex = speakerIndex == 0 ? 1 : 0;
        actualSourceLanguage = _speakerLanguages[actualSpeakerIndex]?.code ?? 'en';
        
        debugPrint('GoogleSTTTranslator: 🔄 CORRECTION: Speaker $speakerIndex → Speaker $actualSpeakerIndex');
        debugPrint('GoogleSTTTranslator: 🔄 CORRECTION: Language $sourceLanguage → $actualSourceLanguage');
        
        // Clear the incorrect speaker's text
        _realtimeTranscriptions[speakerIndex]?.clear();
        _realtimeTranslations[speakerIndex]?.clear();
        if (mounted) {
          setState(() {
            _transcriptions[speakerIndex] = '';
            _translations[speakerIndex] = '';
          });
        }
        
        // Try to transliterate/translate phonetic Bengali back to English
        // This is a workaround - we're asking Azure to translate from Bengali to English
        // hoping it will recognize the phonetic pattern
        debugPrint('GoogleSTTTranslator: 🌐 Attempting to recover English from phonetic Bengali...');
        final recoveryResult = await TranslationService.translateText(
          sourceLanguage: sourceLanguage, // 'bn' (what Soniox thought)
          targetLanguage: actualSourceLanguage, // 'en' (what it actually is)
          content: transcribedText,
        );
        
        if (recoveryResult != null && recoveryResult.translatedText.isNotEmpty) {
          actualTranscribedText = recoveryResult.translatedText;
          debugPrint('GoogleSTTTranslator: ✅ Recovered English: "$actualTranscribedText"');
        } else {
          debugPrint('GoogleSTTTranslator: ⚠️ Could not recover English, using phonetic text as-is');
        }
        
        // Initialize corrected speaker buffers if needed
        if (_realtimeTranscriptions[actualSpeakerIndex] == null) {
          _realtimeTranscriptions[actualSpeakerIndex] = StringBuffer();
        }
        if (_realtimeTranslations[actualSpeakerIndex] == null) {
          _realtimeTranslations[actualSpeakerIndex] = StringBuffer();
        }
      }

      // Now we have the ACTUAL speaker and ACTUAL source language
      debugPrint('GoogleSTTTranslator: ═══ Final Processing ═══');
      debugPrint('GoogleSTTTranslator: Actual speaker: $actualSpeakerIndex');
      debugPrint('GoogleSTTTranslator: Actual source language: $actualSourceLanguage');
      debugPrint('GoogleSTTTranslator: Actual transcribed text: "$actualTranscribedText"');

      // Update transcription for the ACTUAL speaker
      if (_realtimeTranscriptions[actualSpeakerIndex]!.isNotEmpty) {
        _realtimeTranscriptions[actualSpeakerIndex]!.write(' ');
      }
      _realtimeTranscriptions[actualSpeakerIndex]!.write(actualTranscribedText);

      // Determine target speaker and language for translation
      final targetSpeakerIndex = actualSpeakerIndex == 0 ? 1 : 0;
      final targetLanguage = _speakerLanguages[targetSpeakerIndex];

      if (targetLanguage == null) {
        debugPrint('GoogleSTTTranslator: ⚠️ Target language not configured');
        return;
      }

      debugPrint('GoogleSTTTranslator: Target speaker: $targetSpeakerIndex');
      debugPrint('GoogleSTTTranslator: Target language: ${targetLanguage.code}');

      // Translate from ACTUAL source to target
      final translationResult = await TranslationService.translateText(
        sourceLanguage: actualSourceLanguage,
        targetLanguage: targetLanguage.code,
        content: actualTranscribedText,
      );

      if (translationResult == null || translationResult.translatedText.isEmpty) {
        debugPrint('GoogleSTTTranslator: ❌ Azure translation failed');
        return;
      }

      final translatedText = translationResult.translatedText;
      debugPrint('GoogleSTTTranslator: ✅ Azure translation: "$translatedText"');

      // Update translation for the ACTUAL speaker
      if (_realtimeTranslations[actualSpeakerIndex]!.isNotEmpty) {
        _realtimeTranslations[actualSpeakerIndex]!.write(' ');
      }
      _realtimeTranslations[actualSpeakerIndex]!.write(translatedText);

      // Update UI
      if (mounted) {
        setState(() {
          _transcriptions[actualSpeakerIndex] = _realtimeTranscriptions[actualSpeakerIndex]?.toString().trim() ?? '';
          _translations[actualSpeakerIndex] = _realtimeTranslations[actualSpeakerIndex]?.toString().trim() ?? '';
        });
        debugPrint('GoogleSTTTranslator: ✅ UI updated for Speaker $actualSpeakerIndex');
        debugPrint('GoogleSTTTranslator: Speaker $actualSpeakerIndex transcription: "${_transcriptions[actualSpeakerIndex]}"');
        debugPrint('GoogleSTTTranslator: Speaker $actualSpeakerIndex translation: "${_translations[actualSpeakerIndex]}"');
      }

      // Generate and play TTS for the TARGET speaker
      final targetGender = _speakerGenders[targetSpeakerIndex] ?? 'male';
      final earpiece = _speakerEarpieces[targetSpeakerIndex] ?? 'left';

      debugPrint('GoogleSTTTranslator: ═══ TTS Generation ═══');
      debugPrint('GoogleSTTTranslator: TTS for target speaker: $targetSpeakerIndex');
      debugPrint('GoogleSTTTranslator: TTS language: ${targetLanguage.code}');
      debugPrint('GoogleSTTTranslator: TTS text: "$translatedText"');
      debugPrint('GoogleSTTTranslator: TTS gender: $targetGender');
      debugPrint('GoogleSTTTranslator: TTS earpiece: $earpiece');

      // Generate TTS audio file
      final ttsPath = await _stereoTtsService.generateMonoAudioFile(
        translatedText,
        targetLanguage.code,
        gender: targetGender,
      );

      if (ttsPath == null || ttsPath.isEmpty) {
        debugPrint('GoogleSTTTranslator: ❌ TTS generation failed');
        return;
      }

      debugPrint('GoogleSTTTranslator: ✅ TTS generated: $ttsPath');

      // Play TTS audio with stereo routing
      await _playRealtimeTtsWithStereo(
        speakerIndex: actualSpeakerIndex,
        targetSpeakerIndex: targetSpeakerIndex,
        ttsPath: ttsPath,
        earpiece: earpiece,
      );

    } catch (e) {
      debugPrint('GoogleSTTTranslator: ❌ Translation + TTS error: $e');
      debugPrint('GoogleSTTTranslator: Stack trace: ${StackTrace.current}');
    }
  }

  /// Play TTS audio with stereo routing in real-time
  Future<void> _playRealtimeTtsWithStereo({
    required int speakerIndex,
    required int targetSpeakerIndex,
    required String ttsPath,
    required String earpiece,
  }) async {
    try {
      debugPrint('GoogleSTTTranslator: ═══ Playing TTS with Stereo Routing ═══');
      debugPrint('GoogleSTTTranslator: Speaker: $speakerIndex');
      debugPrint('GoogleSTTTranslator: Target speaker: $targetSpeakerIndex');
      debugPrint('GoogleSTTTranslator: Earpiece: $earpiece');
      debugPrint('GoogleSTTTranslator: TTS path: $ttsPath');

      // Switch to playback route
      await _enterPlaybackRoute();
      await Future.delayed(const Duration(milliseconds: 300));

      // Generate stereo audio file with TTS routed to correct earpiece
      final tempDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      debugPrint('GoogleSTTTranslator: Creating stereo audio with routing...');

      // Create a silent audio file for the opposite channel
      final silentAudioPath = await _createMatchingSilentAudioFile(ttsPath);
      
      if (silentAudioPath == null) {
        debugPrint('GoogleSTTTranslator: ⚠️ Failed to create silent audio, using TTS for both channels');
      }

      // Route TTS to correct earpiece, silence to the other
      final leftChannelPath = earpiece == 'left' ? ttsPath : (silentAudioPath ?? ttsPath);
      final rightChannelPath = earpiece == 'right' ? ttsPath : (silentAudioPath ?? ttsPath);
      
      debugPrint('GoogleSTTTranslator: Left channel: ${earpiece == 'left' ? "TTS" : "Silent"}');
      debugPrint('GoogleSTTTranslator: Right channel: ${earpiece == 'right' ? "TTS" : "Silent"}');
      
      final stereoPath = await _stereoTtsService.createTrueStereoAudioFile(
        leftChannelPath,
        rightChannelPath,
        outputFileName: 'realtime_stereo_$timestamp.wav',
      );

      if (stereoPath == null || stereoPath.isEmpty) {
        debugPrint('GoogleSTTTranslator: ❌ Failed to create stereo audio');
        return;
      }

      debugPrint('GoogleSTTTranslator: ✅ Stereo audio created: $stereoPath');

      // Play stereo audio
      if (targetSpeakerIndex == 0) {
        setState(() => _isPlayingTts1 = true);
      } else {
        setState(() => _isPlayingTts2 = true);
      }

      await _stereoTtsService.playStereoAudio(stereoPath);

      if (mounted) {
        setState(() {
          _isPlayingTts1 = false;
          _isPlayingTts2 = false;
        });
      }

      debugPrint('GoogleSTTTranslator: ✅ TTS playback completed');

      // Clean up temporary files
      try {
        final stereoFile = File(stereoPath);
        if (await stereoFile.exists()) {
          await stereoFile.delete();
          debugPrint('GoogleSTTTranslator: ✅ Cleaned up temporary stereo file');
        }
        
        if (silentAudioPath != null) {
          final silentFile = File(silentAudioPath);
          if (await silentFile.exists()) {
            await silentFile.delete();
            debugPrint('GoogleSTTTranslator: ✅ Cleaned up temporary silent file');
          }
        }
      } catch (e) {
        debugPrint('GoogleSTTTranslator: ⚠️ Failed to delete temporary files: $e');
      }

      // Switch back to recording route if still recording
      if (_isRecording && _isRealtimeMode) {
        await Future.delayed(const Duration(milliseconds: 200));
        await _enterRecordingRoute();
        debugPrint('GoogleSTTTranslator: ✅ Switched back to recording route');
      }
    } catch (e) {
      debugPrint('GoogleSTTTranslator: ❌ TTS playback error: $e');
      debugPrint('GoogleSTTTranslator: Stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() {
          _isPlayingTts1 = false;
          _isPlayingTts2 = false;
        });
      }
    }
  }

  /// Create a silent audio file with the same duration as the reference audio
  Future<String?> _createMatchingSilentAudioFile(String referenceAudioPath) async {
    try {
      debugPrint('GoogleSTTTranslator: Creating silent audio file...');
      
      // Read reference audio file to get duration
      final refFile = File(referenceAudioPath);
      if (!await refFile.exists()) {
        debugPrint('GoogleSTTTranslator: ❌ Reference audio file does not exist');
        return null;
      }
      
      final refBytes = await refFile.readAsBytes();
      
      // WAV file header is 44 bytes
      // Data size is in bytes 40-43 (little-endian)
      if (refBytes.length < 44) {
        debugPrint('GoogleSTTTranslator: ❌ Reference audio file is too small');
        return null;
      }
      
      // Get audio data size from WAV header
      final dataSize = refBytes[40] | 
                      (refBytes[41] << 8) | 
                      (refBytes[42] << 16) | 
                      (refBytes[43] << 24);
      
      debugPrint('GoogleSTTTranslator: Reference audio data size: $dataSize bytes');
      
      // Create silent audio file with same size
      final tempDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final silentPath = '${tempDir.path}/silent_$timestamp.wav';
      
      // Copy WAV header from reference file
      final silentBytes = Uint8List(44 + dataSize);
      silentBytes.setAll(0, refBytes.sublist(0, 44));
      
      // Fill audio data with zeros (silence)
      for (int i = 44; i < silentBytes.length; i++) {
        silentBytes[i] = 0;
      }
      
      // Write silent audio file
      final silentFile = File(silentPath);
      await silentFile.writeAsBytes(silentBytes);
      
      debugPrint('GoogleSTTTranslator: ✅ Silent audio file created: $silentPath');
      return silentPath;
    } catch (e) {
      debugPrint('GoogleSTTTranslator: ❌ Error creating silent audio: $e');
      return null;
    }
  }

  /// Toggle between manual and real-time mode
  void _toggleTranslationMode() {
    setState(() {
      _isRealtimeMode = !_isRealtimeMode;
    });
    
    debugPrint('GoogleSTTTranslator: Mode switched to: ${_isRealtimeMode ? "REAL-TIME" : "MANUAL"}');
    
    // Show mode info
    final mode = _isRealtimeMode ? 'Real-time Mode' : 'Manual Mode';
    final description = _isRealtimeMode
        ? 'Continuous translation without stop button'
        : 'Press stop to process translation';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mode,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(description),
          ],
        ),
        backgroundColor: _isRealtimeMode ? Colors.purple : Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _processAudio() async {
    if (_recordedAudioPath == null) return;

    try {
      setState(() {
        _processingProgress = 0.1;
        _processingStatus = 'Reading audio file...';
      });

      // Read audio file (cache it for reuse)
      final audioFile = File(_recordedAudioPath!);
      _cachedOriginalAudioBytes = await audioFile.readAsBytes();
      final audioBytes = _cachedOriginalAudioBytes!;

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

      // Step 1: Create temporary audio files for each detected speaker
      final tempSpeaker1Path = '${directory.path}/temp_speaker1_$timestamp.wav';
      final tempSpeaker2Path = '${directory.path}/temp_speaker2_$timestamp.wav';

      // Use cached audio bytes if available, otherwise read from file
      Uint8List originalBytes;
      if (_cachedOriginalAudioBytes != null) {
        debugPrint(
            'GoogleSTTTranslator: ✅ Using cached original audio bytes (avoiding redundant file read)');
        originalBytes = _cachedOriginalAudioBytes!;
      } else {
        debugPrint(
            'GoogleSTTTranslator: Reading original audio file (cache miss)');
        final originalFile = File(_recordedAudioPath!);
        originalBytes = await originalFile.readAsBytes();
        _cachedOriginalAudioBytes = originalBytes; // Cache for future use
      }

      // Convert to Float32List for processing
      final Float32List audioData = _convertBytesToFloat32List(originalBytes);

      // Create temporary speaker-specific audio files
      await _createSpeakerAudioFile(audioData, tempSpeaker1Path, 0);
      await _createSpeakerAudioFile(audioData, tempSpeaker2Path, 1);

      // Step 2: Language-based speaker assignment
      setState(() {
        _processingProgress = 0.70;
        _processingStatus = 'Detecting languages and assigning speakers...';
      });

      // Get configured languages for both speakers
      final speaker1ConfiguredLanguage = _speakerLanguages[0]?.code ?? 'en';
      final speaker2ConfiguredLanguage = _speakerLanguages[1]?.code ?? 'en';
      final List<String> preferredLanguages = [
        speaker1ConfiguredLanguage,
        speaker2ConfiguredLanguage
      ];

      debugPrint(
          'GoogleSTTTranslator: Configured languages - Speaker 1: $speaker1ConfiguredLanguage, Speaker 2: $speaker2ConfiguredLanguage');

      // Assign speakers based on language detection
      final Map<String, String> speakerAssignment =
          await _assignSpeakersByLanguage(
              tempSpeaker1Path, tempSpeaker2Path, preferredLanguages);

      // Step 3: Create final speaker files with correct assignment
      _speaker1AudioPath = '${directory.path}/speaker1_$timestamp.wav';
      _speaker2AudioPath = '${directory.path}/speaker2_$timestamp.wav';

      // Copy the correctly assigned files
      await File(speakerAssignment['speaker1']!).copy(_speaker1AudioPath!);
      await File(speakerAssignment['speaker2']!).copy(_speaker2AudioPath!);

      // Clean up temporary files
      await File(tempSpeaker1Path).delete();
      await File(tempSpeaker2Path).delete();

      debugPrint(
          'GoogleSTTTranslator: Audio separation completed with language-based assignment');
      debugPrint(
          'GoogleSTTTranslator: Final assignment - Speaker 1: ${speakerAssignment['speaker1']}, Speaker 2: ${speakerAssignment['speaker2']}');
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
      debugPrint(
          'GoogleSTTTranslator: 🚀 OPTIMIZATION: Using cached Voice 1 transcription');

      // Determine which speaker is Voice 1 (already transcribed during language detection)
      // Voice 1's transcription is cached in _voice1CachedTranscription
      // We need to figure out if Voice 1 became Speaker 1 or Speaker 2

      final speaker1Lang = _speakerLanguages[0]?.code ?? 'en';
      final speaker2Lang = _speakerLanguages[1]?.code ?? 'en';

      // Voice 1's detected language tells us which speaker it is
      final voice1Language = _voice1CachedTranscription?['language'] as String?;
      bool voice1IsSpeaker1 = (voice1Language == speaker1Lang);

      // Transcribe Speaker 1 audio (skip if file has no meaningful audio)
      if (_speaker1AudioPath != null &&
          await File(_speaker1AudioPath!).exists() &&
          await _hasMeaningfulAudio(_speaker1AudioPath!, speakerIndex: 0)) {
        final speaker1Language = _speakerLanguages[0];
        final speaker1LanguageCode =
            _mapLanguageToGoogleCode(speaker1Language?.code ?? 'en');

        // Check if this is Voice 1 (can reuse cached transcription)
        if (voice1IsSpeaker1 && _voice1CachedTranscription != null) {
          // OPTIMIZATION: Reuse Voice 1's cached transcription (0 API calls)
          debugPrint(
              'GoogleSTTTranslator: ✅ Speaker 1 is Voice 1 - using cached transcription (0 API calls)');
          final cachedText = _voice1CachedTranscription!['text'] as String?;
          if (cachedText != null && cachedText.isNotEmpty) {
            _transcriptions[0] = cachedText;
            debugPrint(
                'GoogleSTTTranslator: Stored Speaker 1 transcript: "${_transcriptions[0]}"');
          }
        } else {
          // This is Voice 2 - need to transcribe (1 API call)
          debugPrint(
              'GoogleSTTTranslator: Speaker 1 is Voice 2 - transcribing with language: $speaker1LanguageCode (1 API call)');

          final audioBytes = await File(_speaker1AudioPath!).readAsBytes();
          final List<String> allConfiguredLanguages = [
            speaker1Lang,
            speaker2Lang
          ];

          // Check cache first (in case it was called before)
          final cacheKey1 = '$_speaker1AudioPath|$speaker1LanguageCode';
          Map<String, dynamic>? cached1 = _sttCache[cacheKey1];
          var result1 = cached1;
          if (cached1 == null) {
            final r = await _sttProvider.transcribeWithDiarization(
              audioBytes: audioBytes,
              languageCode: speaker1LanguageCode,
              alternativeLanguages: allConfiguredLanguages,
              minSpeakers: 1,
              maxSpeakers: 1,
            );
            if (r != null) {
              final text = r.fullTranscript.isNotEmpty
                  ? r.fullTranscript
                  : r.segments.map((s) => s.text).join(' ');
              result1 = {
                'text': text,
                'segmentCount': r.segments.length,
                'confidence': _calculateTextQualityConfidence(
                    text, text.length, r.segments.length),
              };
              _sttCache[cacheKey1] = result1;
            } else {
              result1 = null;
            }
          }

          if (result1 != null) {
            debugPrint('GoogleSTTTranslator: Speaker 1 transcription result:');
            debugPrint('  Language: $speaker1LanguageCode');
            debugPrint('  Text: "${result1['text']}"');
            _transcriptions[0] = (result1['text'] as String?) ?? '';
            debugPrint(
                'GoogleSTTTranslator: Stored Speaker 1 transcript: "${_transcriptions[0]}"');
          } else {
            debugPrint(
                'GoogleSTTTranslator: Speaker 1 transcription failed - no result');
          }
        }
      }

      // Transcribe Speaker 2 audio (skip if file has no meaningful audio)
      if (_speaker2AudioPath != null &&
          await File(_speaker2AudioPath!).exists() &&
          await _hasMeaningfulAudio(_speaker2AudioPath!, speakerIndex: 1)) {
        final speaker2Language = _speakerLanguages[1];
        final speaker2LanguageCode =
            _mapLanguageToGoogleCode(speaker2Language?.code ?? 'en');

        // Check if this is Voice 1 (can reuse cached transcription)
        if (!voice1IsSpeaker1 && _voice1CachedTranscription != null) {
          // OPTIMIZATION: Reuse Voice 1's cached transcription (0 API calls)
          debugPrint(
              'GoogleSTTTranslator: ✅ Speaker 2 is Voice 1 - using cached transcription (0 API calls)');
          final cachedText = _voice1CachedTranscription!['text'] as String?;
          if (cachedText != null && cachedText.isNotEmpty) {
            _transcriptions[1] = cachedText;
            debugPrint(
                'GoogleSTTTranslator: Stored Speaker 2 transcript: "${_transcriptions[1]}"');
          }
        } else {
          // This is Voice 2 - need to transcribe (1 API call)
          debugPrint(
              'GoogleSTTTranslator: Speaker 2 is Voice 2 - transcribing with language: $speaker2LanguageCode (1 API call)');

          final audioBytes = await File(_speaker2AudioPath!).readAsBytes();
          final List<String> allConfiguredLanguages = [
            speaker1Lang,
            speaker2Lang
          ];

          // Check cache first (in case it was called before)
          final cacheKey2 = '$_speaker2AudioPath|$speaker2LanguageCode';
          Map<String, dynamic>? cached2 = _sttCache[cacheKey2];
          var result2 = cached2;
          if (cached2 == null) {
            final r = await _sttProvider.transcribeWithDiarization(
              audioBytes: audioBytes,
              languageCode: speaker2LanguageCode,
              alternativeLanguages: allConfiguredLanguages,
              minSpeakers: 1,
              maxSpeakers: 1,
            );
            if (r != null) {
              final text = r.fullTranscript.isNotEmpty
                  ? r.fullTranscript
                  : r.segments.map((s) => s.text).join(' ');
              result2 = {
                'text': text,
                'segmentCount': r.segments.length,
                'confidence': _calculateTextQualityConfidence(
                    text, text.length, r.segments.length),
              };
              _sttCache[cacheKey2] = result2;
            } else {
              result2 = null;
            }
          }

          if (result2 != null) {
            debugPrint('GoogleSTTTranslator: Speaker 2 transcription result:');
            debugPrint('  Language: $speaker2LanguageCode');
            debugPrint('  Text: "${result2['text']}"');
            _transcriptions[1] = (result2['text'] as String?) ?? '';
            debugPrint(
                'GoogleSTTTranslator: Stored Speaker 2 transcript: "${_transcriptions[1]}"');
          } else {
            debugPrint(
                'GoogleSTTTranslator: Speaker 2 transcription failed - no result');
          }
        }
      }

      debugPrint('GoogleSTTTranslator: ===== TRANSCRIPTION COMPLETED =====');
      debugPrint('  Speaker 0: ${_transcriptions[0] ?? "No transcription"}');
      debugPrint('  Speaker 1: ${_transcriptions[1] ?? "No transcription"}');
      debugPrint(
          'GoogleSTTTranslator: Total transcriptions: ${_transcriptions.length}');
      debugPrint(
          'GoogleSTTTranslator: Transcription keys: ${_transcriptions.keys.toList()}');
      debugPrint(
          'GoogleSTTTranslator: 🎉 API OPTIMIZATION: Total STT API calls = 3');
      debugPrint(
          'GoogleSTTTranslator:   - Voice 1 detection: 2 calls (both languages)');
      debugPrint(
          'GoogleSTTTranslator:   - Voice 2 transcription: 1 call (inferred language)');
      debugPrint(
          'GoogleSTTTranslator:   - Saved: 3 API calls (50% reduction from 6 to 3)');
      debugPrint(
          'GoogleSTTTranslator: ==========================================');

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

      setState(() {
        _processingStatus = 'Translating text...';
        _processingProgress = 0.85;
      });

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
      if (speaker1LangCode == speaker2LangCode) {
        debugPrint(
            'GoogleSTTTranslator: No translation needed - same language');
        return;
      }

      // OPTIMIZATION: Translate both speakers in parallel
      debugPrint(
          'GoogleSTTTranslator: 🚀 Starting parallel translation API calls...');

      final List<Future<void>> translationTasks = [];

      // Translate Speaker 1's text to Speaker 2's language using Azure Translator API
      if (_transcriptions[0] != null && _transcriptions[0]!.isNotEmpty) {
        translationTasks.add(
          TranslationService.translateText(
            sourceLanguage: speaker1LangCode,
            targetLanguage: speaker2LangCode,
            content: _transcriptions[0]!,
          ).then((result) {
            if (result != null && result.translatedText.isNotEmpty) {
              _translations[0] = result.translatedText;
              debugPrint(
                  'GoogleSTTTranslator: Speaker 1 translation: "${result.translatedText}"');
            } else {
              debugPrint('GoogleSTTTranslator: Speaker 1 translation failed');
            }
          }).catchError((e) {
            debugPrint('GoogleSTTTranslator: Speaker 1 translation error: $e');
          }),
        );
        debugPrint(
            'GoogleSTTTranslator: Queued translation for Speaker 1 text to $speaker2LangCode...');
      }

      // Translate Speaker 2's text to Speaker 1's language using Azure Translator API
      if (_transcriptions[1] != null && _transcriptions[1]!.isNotEmpty) {
        translationTasks.add(
          TranslationService.translateText(
            sourceLanguage: speaker2LangCode,
            targetLanguage: speaker1LangCode,
            content: _transcriptions[1]!,
          ).then((result) {
            if (result != null && result.translatedText.isNotEmpty) {
              _translations[1] = result.translatedText;
              debugPrint(
                  'GoogleSTTTranslator: Speaker 2 translation: "${result.translatedText}"');
            } else {
              debugPrint('GoogleSTTTranslator: Speaker 2 translation failed');
            }
          }).catchError((e) {
            debugPrint('GoogleSTTTranslator: Speaker 2 translation error: $e');
          }),
        );
        debugPrint(
            'GoogleSTTTranslator: Queued translation for Speaker 2 text to $speaker1LangCode...');
      }

      // Execute all translations in parallel
      if (translationTasks.isNotEmpty) {
        await Future.wait(translationTasks);
        debugPrint(
            'GoogleSTTTranslator: ✅ Parallel translation API calls completed');
      }

      debugPrint('GoogleSTTTranslator: Translation process completed');
      debugPrint(
          '  Speaker 1 translation: ${_translations[0] ?? "No translation"}');
      debugPrint(
          '  Speaker 2 translation: ${_translations[1] ?? "No translation"}');

      // Generate TTS audio for translated text
      await _generateTtsAudio();

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

  /// Helper method to generate TTS audio for a single speaker with retry logic
  Future<String?> _generateSpeakerTtsWithRetry(
    String text,
    String languageCode,
    String gender,
    int speakerIndex,
  ) async {
    bool ttsSuccess = false;
    int retryCount = 0;
    const maxRetries = 3;
    String? ttsAudioPath;

    while (!ttsSuccess && retryCount < maxRetries) {
      try {
        debugPrint(
            'GoogleSTTTranslator: Generating Speaker $speakerIndex TTS with gender: $gender (attempt ${retryCount + 1})');
        ttsAudioPath = await _ttsService.generateAudioFile(
          text,
          languageCode,
          gender: gender,
        );
        debugPrint(
            'GoogleSTTTranslator: Speaker $speakerIndex TTS audio path (attempt ${retryCount + 1}): $ttsAudioPath');

        // Verify the file was actually created and has content
        if (ttsAudioPath != null) {
          final file = File(ttsAudioPath);
          final exists = await file.exists();
          final size = exists ? await file.length() : 0;
          debugPrint(
              'GoogleSTTTranslator: Speaker $speakerIndex TTS file verification (attempt ${retryCount + 1}):');
          debugPrint('  File exists: $exists');
          debugPrint('  File size: $size bytes');

          if (exists && size > 0) {
            ttsSuccess = true;
            debugPrint(
                'GoogleSTTTranslator: Speaker $speakerIndex TTS file generation successful');
          } else {
            debugPrint(
                'GoogleSTTTranslator: Speaker $speakerIndex TTS file generation failed - file is empty or missing (attempt ${retryCount + 1})');
            ttsAudioPath = null;
            retryCount++;
            if (retryCount < maxRetries) {
              debugPrint(
                  'GoogleSTTTranslator: Retrying Speaker $speakerIndex TTS generation...');
              await Future.delayed(const Duration(milliseconds: 1000));
            }
          }
        } else {
          debugPrint(
              'GoogleSTTTranslator: Speaker $speakerIndex TTS generation returned null (attempt ${retryCount + 1})');
          retryCount++;
          if (retryCount < maxRetries) {
            debugPrint(
                'GoogleSTTTranslator: Retrying Speaker $speakerIndex TTS generation...');
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }
      } catch (e) {
        debugPrint(
            'GoogleSTTTranslator: Speaker $speakerIndex TTS generation error (attempt ${retryCount + 1}): $e');
        retryCount++;
        if (retryCount < maxRetries) {
          debugPrint(
              'GoogleSTTTranslator: Retrying Speaker $speakerIndex TTS generation...');
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
    }

    if (!ttsSuccess) {
      debugPrint(
          'GoogleSTTTranslator: Speaker $speakerIndex TTS generation failed after $maxRetries attempts');
      // Create silent audio as fallback
      debugPrint(
          'GoogleSTTTranslator: Creating silent audio fallback for Speaker $speakerIndex');
      ttsAudioPath =
          await _createSilentAudioFile('speaker${speakerIndex}_fallback');
    }

    return ttsAudioPath;
  }

  /// Generate TTS audio files for translated text
  Future<void> _generateTtsAudio() async {
    try {
      debugPrint('GoogleSTTTranslator: Starting TTS audio generation...');

      setState(() {
        _processingStatus = 'Generating speech audio...';
        _processingProgress = 0.90;
      });

      // Always ensure we have TTS files for both speakers (real or silent)
      bool hasSpeaker1Translation =
          _translations[0] != null && _translations[0]!.isNotEmpty;
      bool hasSpeaker2Translation =
          _translations[1] != null && _translations[1]!.isNotEmpty;

      debugPrint('GoogleSTTTranslator: Translation status:');
      debugPrint('  Speaker 1 has translation: $hasSpeaker1Translation');
      debugPrint('  Speaker 2 has translation: $hasSpeaker2Translation');

      // OPTIMIZATION: Generate TTS for both speakers in parallel
      debugPrint('GoogleSTTTranslator: 🚀 Starting parallel TTS generation...');

      final List<Future<void>> ttsTasks = [];

      // Generate TTS audio for Speaker 1's translated text (for Speaker 2 to hear)
      if (hasSpeaker1Translation) {
        final speaker2Language = _speakerLanguages[1];
        if (speaker2Language != null) {
          debugPrint(
              'GoogleSTTTranslator: Queuing TTS generation for Speaker 1 translation in ${speaker2Language.code}...');
          debugPrint('  Text to convert: "${_translations[0]}"');

          ttsTasks.add(
            _generateSpeakerTtsWithRetry(
              _translations[0]!,
              speaker2Language.code,
              _speakerGenders[0] ?? 'male',
              1,
            ).then((path) {
              _speaker1TtsAudioPath = path;
              if (path != null) {
                debugPrint(
                    'GoogleSTTTranslator: ✅ Speaker 1 TTS generated: $path');
              }
            }).catchError((e) {
              debugPrint(
                  'GoogleSTTTranslator: Speaker 1 TTS generation error: $e');
              _speaker1TtsAudioPath = null;
            }),
          );
        } else {
          debugPrint(
              'GoogleSTTTranslator: Speaker 2 language is null, cannot generate TTS for Speaker 1');
        }
      } else {
        debugPrint(
            'GoogleSTTTranslator: Speaker 1 translation is null or empty, skipping TTS generation');
      }

      // Generate TTS audio for Speaker 2's translated text (for Speaker 1 to hear)
      if (hasSpeaker2Translation) {
        final speaker1Language = _speakerLanguages[0];
        if (speaker1Language != null) {
          debugPrint(
              'GoogleSTTTranslator: Queuing TTS generation for Speaker 2 translation in ${speaker1Language.code}...');
          debugPrint('  Text to convert: "${_translations[1]}"');

          ttsTasks.add(
            _generateSpeakerTtsWithRetry(
              _translations[1]!,
              speaker1Language.code,
              _speakerGenders[1] ?? 'female',
              2,
            ).then((path) {
              _speaker2TtsAudioPath = path;
              if (path != null) {
                debugPrint(
                    'GoogleSTTTranslator: ✅ Speaker 2 TTS generated: $path');
              }
            }).catchError((e) {
              debugPrint(
                  'GoogleSTTTranslator: Speaker 2 TTS generation error: $e');
              _speaker2TtsAudioPath = null;
            }),
          );
        } else {
          debugPrint(
              'GoogleSTTTranslator: Speaker 1 language is null, cannot generate TTS for Speaker 2');
        }
      } else {
        debugPrint(
            'GoogleSTTTranslator: Speaker 2 translation is null or empty, skipping TTS generation');
      }

      // Execute all TTS generations in parallel
      if (ttsTasks.isNotEmpty) {
        await Future.wait(ttsTasks);
        debugPrint('GoogleSTTTranslator: ✅ Parallel TTS generation completed');
      }

      // Ensure we have TTS files for both speakers (create silent audio for missing ones)
      if (!hasSpeaker1Translation && _speaker1TtsAudioPath == null) {
        debugPrint(
            'GoogleSTTTranslator: Creating silent audio for Speaker 1 (no translation)');
        _speaker1TtsAudioPath = await _createSilentAudioFile('speaker1_silent');
      }

      if (!hasSpeaker2Translation && _speaker2TtsAudioPath == null) {
        debugPrint(
            'GoogleSTTTranslator: Creating silent audio for Speaker 2 (no translation)');
        _speaker2TtsAudioPath = await _createSilentAudioFile('speaker2_silent');
      }

      // Add a small delay to ensure file system operations complete
      await Future.delayed(const Duration(milliseconds: 500));

      // Generate stereo audio file immediately after TTS generation
      await _generateStereoAudioFile();

      // Force UI refresh to enable TTS buttons
      if (mounted) {
        setState(() {
          // This will trigger a rebuild to enable TTS buttons
        });
      }

      debugPrint('GoogleSTTTranslator: TTS audio generation completed');
      debugPrint('  Speaker 1 TTS path: $_speaker1TtsAudioPath');
      debugPrint('  Speaker 2 TTS path: $_speaker2TtsAudioPath');

      // Verify TTS files exist and are playable
      if (_speaker1TtsAudioPath != null) {
        final file1 = File(_speaker1TtsAudioPath!);
        final exists1 = await file1.exists();
        final size1 = exists1 ? await file1.length() : 0;
        debugPrint('  Speaker 1 TTS file exists: $exists1, size: $size1 bytes');
      }

      if (_speaker2TtsAudioPath != null) {
        final file2 = File(_speaker2TtsAudioPath!);
        final exists2 = await file2.exists();
        final size2 = exists2 ? await file2.length() : 0;
        debugPrint('  Speaker 2 TTS file exists: $exists2, size: $size2 bytes');
      }
    } catch (e) {
      debugPrint('GoogleSTTTranslator: TTS audio generation error: $e');
      // Don't throw - TTS failure shouldn't break the app
    }
  }

  /// Detect language by running balanced STT calls: once per configured language
  /// Caches results per (audioPath, language) to avoid duplicate API calls later.
  Future<Map<String, dynamic>> _detectVoiceLanguageOptimized(
      String audioPath, List<String> preferredLanguages) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        debugPrint(
            'GoogleSTTTranslator: Audio file does not exist: $audioPath');
        return {'language': null, 'confidence': 0.0, 'text': null};
      }

      final audioBytes = await file.readAsBytes();
      if (audioBytes.isEmpty) {
        debugPrint('GoogleSTTTranslator: Audio file is empty: $audioPath');
        return {'language': null, 'confidence': 0.0, 'text': null};
      }

      debugPrint(
          'GoogleSTTTranslator: Using Google STT multi-language detection for: $audioPath');
      debugPrint(
          'GoogleSTTTranslator: Preferred languages: $preferredLanguages');

      // Balanced: call once with en, once with bn (or configured pair)
      final primaryA = _mapLanguageToGoogleCode(preferredLanguages[0]);
      final primaryB = _mapLanguageToGoogleCode(preferredLanguages[1]);

      Future<Map<String, dynamic>?> transcribeFor(
          String primary, String alt) async {
        final cacheKey = '$audioPath|$primary';
        if (_sttCache.containsKey(cacheKey)) {
          return _sttCache[cacheKey];
        }
        final r = await _sttProvider.transcribeWithDiarization(
          audioBytes: audioBytes,
          languageCode: primary,
          alternativeLanguages: [primary, alt],
          minSpeakers: 1,
          maxSpeakers: 1,
        );
        if (r == null) return null;
        final text = r.fullTranscript.isNotEmpty
            ? r.fullTranscript
            : r.segments.map((s) => s.text).join(' ');
        final textLength = text.length;
        final segmentCount = r.segments.length;
        final confidence =
            _calculateTextQualityConfidence(text, textLength, segmentCount);
        final detected = _determineLanguageFromText(text, preferredLanguages);
        final payload = <String, dynamic>{
          'language': detected,
          'confidence': confidence,
          'text': text,
          'textLength': textLength,
          'segmentCount': segmentCount,
        };
        _sttCache[cacheKey] = payload;
        return payload;
      }

      // Execute sequentially to limit load; still exactly two calls
      final a = await transcribeFor(primaryA, primaryB);
      final b = await transcribeFor(primaryB, primaryA);

      Map<String, dynamic>? best = a;
      if (b != null &&
          (best == null ||
              (b['confidence'] as double) > (best['confidence'] as double))) {
        best = b;
      }

      if (best == null) {
        debugPrint('GoogleSTTTranslator: No transcription result from STT');
        return {'language': null, 'confidence': 0.0, 'text': null};
      }

      debugPrint('GoogleSTTTranslator: Balanced detection result:');
      debugPrint('  Text: "${best['text']}"');
      debugPrint('  Detected Language: ${best['language']}');
      debugPrint('  Confidence: ${best['confidence']}');
      debugPrint('  Text Length: ${best['textLength']}');
      debugPrint('  Segments: ${best['segmentCount']}');

      return best;
    } catch (e) {
      debugPrint(
          'GoogleSTTTranslator: Multi-language detection error for $audioPath: $e');
      return {'language': null, 'confidence': 0.0, 'text': null};
    }
  }

  /// Calculate confidence based on text quality metrics
  double _calculateTextQualityConfidence(
      String text, int textLength, int segmentCount) {
    if (text.isEmpty) return 0.0;

    double confidence = 0.0;

    // Base confidence from text length (longer text = higher confidence)
    confidence += (textLength * 0.01).clamp(0.0, 0.4);

    // Bonus for having segments (indicates successful processing)
    confidence += segmentCount > 0 ? 0.2 : 0.0;

    // Bonus for text containing meaningful characters
    final meaningfulChars = text.replaceAll(RegExp(r'[^\w\s]'), '').length;
    confidence += (meaningfulChars * 0.005).clamp(0.0, 0.2);

    // Bonus for text containing multiple words
    final wordCount =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    confidence += (wordCount * 0.02).clamp(0.0, 0.2);

    return confidence.clamp(0.0, 1.0);
  }

  /// Determine language from text content using script detection
  String? _determineLanguageFromText(
      String text, List<String> preferredLanguages) {
    if (text.isEmpty) return null;

    // Count characters by script
    int bengaliCount = 0;
    int hindiCount = 0;
    int sinhalaCount = 0;
    int latinCount = 0;
    int arabicCount = 0;
    int chineseCount = 0;
    int otherCount = 0;

    for (final rune in text.runes) {
      if (rune >= 0x0980 && rune <= 0x09FF) {
        bengaliCount++; // Bengali Unicode block
      } else if (rune >= 0x0900 && rune <= 0x097F) {
        hindiCount++; // Devanagari (Hindi) Unicode block
      } else if (rune >= 0x0D80 && rune <= 0x0DFF) {
        sinhalaCount++; // Sinhala Unicode block
      } else if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
        latinCount++; // Latin script
      } else if (rune >= 0x0600 && rune <= 0x06FF) {
        arabicCount++; // Arabic script
      } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
        chineseCount++; // CJK Unified Ideographs
      } else if (rune > 0x007F) {
        otherCount++; // Other non-ASCII characters
      }
    }

    final totalChars = bengaliCount +
        hindiCount +
        sinhalaCount +
        latinCount +
        arabicCount +
        chineseCount +
        otherCount;
    if (totalChars == 0)
      return preferredLanguages[0]; // Fallback to first language

    // Calculate script ratios
    final bengaliRatio = bengaliCount / totalChars;
    final hindiRatio = hindiCount / totalChars;
    final sinhalaRatio = sinhalaCount / totalChars;
    final latinRatio = latinCount / totalChars;
    final arabicRatio = arabicCount / totalChars;
    final chineseRatio = chineseCount / totalChars;

    debugPrint('GoogleSTTTranslator: Script analysis:');
    debugPrint('  Bengali: $bengaliCount ($bengaliRatio)');
    debugPrint('  Hindi: $hindiCount ($hindiRatio)');
    debugPrint('  Sinhala: $sinhalaCount ($sinhalaRatio)');
    debugPrint('  Latin: $latinCount ($latinRatio)');
    debugPrint('  Arabic: $arabicCount ($arabicRatio)');
    debugPrint('  Chinese: $chineseCount ($chineseRatio)');

    // Determine language based on dominant script
    if (bengaliRatio > 0.5) {
      // Bengali script dominant
      for (final lang in preferredLanguages) {
        if (lang.toLowerCase().startsWith('bn')) return lang;
      }
    } else if (hindiRatio > 0.5) {
      // Hindi script dominant - treat as Bengali for our purposes
      debugPrint(
          'GoogleSTTTranslator: Detected Hindi script, treating as Bengali');
      for (final lang in preferredLanguages) {
        if (lang.toLowerCase().startsWith('bn')) return lang;
      }
    } else if (sinhalaRatio > 0.5) {
      // Sinhala script dominant - treat as Bengali for our purposes
      debugPrint(
          'GoogleSTTTranslator: Detected Sinhala script, treating as Bengali');
      for (final lang in preferredLanguages) {
        if (lang.toLowerCase().startsWith('bn')) return lang;
      }
    } else if (latinRatio > 0.5) {
      // Latin script dominant
      for (final lang in preferredLanguages) {
        if (lang.toLowerCase().startsWith('en') ||
            lang.toLowerCase().startsWith('es') ||
            lang.toLowerCase().startsWith('fr') ||
            lang.toLowerCase().startsWith('de')) return lang;
      }
    } else if (arabicRatio > 0.5) {
      // Arabic script dominant
      for (final lang in preferredLanguages) {
        if (lang.toLowerCase().startsWith('ar')) return lang;
      }
    } else if (chineseRatio > 0.5) {
      // Chinese script dominant
      for (final lang in preferredLanguages) {
        if (lang.toLowerCase().startsWith('zh')) return lang;
      }
    }

    // Fallback: return the language with highest script match
    final scriptScores = <String, double>{};
    for (final lang in preferredLanguages) {
      final langLower = lang.toLowerCase();
      if (langLower.startsWith('bn')) {
        // Use the highest of Bengali, Hindi, or Sinhala ratio for Bengali language
        scriptScores[lang] =
            math.max(bengaliRatio, math.max(hindiRatio, sinhalaRatio));
      } else if (langLower.startsWith('en') ||
          langLower.startsWith('es') ||
          langLower.startsWith('fr') ||
          langLower.startsWith('de')) {
        scriptScores[lang] = latinRatio;
      } else if (langLower.startsWith('ar')) {
        scriptScores[lang] = arabicRatio;
      } else if (langLower.startsWith('zh')) {
        scriptScores[lang] = chineseRatio;
      } else {
        scriptScores[lang] =
            latinRatio; // Default to Latin for unknown languages
      }
    }

    // Return language with highest script score
    String? bestLanguage;
    double bestScore = 0.0;
    for (final entry in scriptScores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestLanguage = entry.key;
      }
    }

    debugPrint(
        'GoogleSTTTranslator: Script-based language detection: $bestLanguage (score: $bestScore)');
    return bestLanguage ?? preferredLanguages[0];
  }

  /// Detect language of a diarized voice by testing both languages and picking the best result
  Future<Map<String, dynamic>> _detectVoiceLanguage(
      String audioPath, List<String> preferredLanguages) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        debugPrint(
            'GoogleSTTTranslator: Audio file does not exist: $audioPath');
        return {'language': null, 'confidence': 0.0, 'text': null};
      }

      final audioBytes = await file.readAsBytes();
      if (audioBytes.isEmpty) {
        debugPrint('GoogleSTTTranslator: Audio file is empty: $audioPath');
        return {'language': null, 'confidence': 0.0, 'text': null};
      }

      debugPrint(
          'GoogleSTTTranslator: Testing voice with both languages: $audioPath');
      debugPrint(
          'GoogleSTTTranslator: Preferred languages: $preferredLanguages');

      // Test each preferred language and pick the best result
      final Map<String, Map<String, dynamic>> languageResults = {};

      for (final language in preferredLanguages) {
        try {
          debugPrint('GoogleSTTTranslator: Testing with language: $language');

          final result = await _sttProvider.transcribeWithDiarization(
            audioBytes: audioBytes,
            languageCode: _mapLanguageToGoogleCode(language),
            alternativeLanguages: [
              _mapLanguageToGoogleCode(language),
              _mapLanguageToGoogleCode(preferredLanguages[1]),
            ],
            minSpeakers: 1,
            maxSpeakers: 1,
          );

          if (result != null) {
            final text = result.fullTranscript.isNotEmpty
                ? result.fullTranscript
                : result.segments.map((s) => s.text).join(' ');
            final avgConfidence = result.segments.isNotEmpty
                ? result.segments
                        .map((s) => s.confidence)
                        .reduce((a, b) => a + b) /
                    result.segments.length
                : 0.0;

            languageResults[language] = {
              'text': text,
              'confidence': avgConfidence,
              'segmentCount': result.segments.length,
              'textLength': text.length,
            };

            debugPrint('GoogleSTTTranslator: Language $language result:');
            debugPrint('  Text: "$text"');
            debugPrint('  Avg Confidence: $avgConfidence');
            debugPrint('  Segments: ${result.segments.length}');
            debugPrint('  Text Length: ${text.length}');
          }
        } catch (e) {
          debugPrint(
              'GoogleSTTTranslator: Error testing language $language: $e');
        }
      }

      // Find the best language based on confidence and text quality
      String? bestLanguage;
      double bestScore = 0.0;
      String bestText = '';

      for (final entry in languageResults.entries) {
        final language = entry.key;
        final result = entry.value;
        final confidence = result['confidence'] as double;
        final textLength = result['textLength'] as int;
        final segmentCount = result['segmentCount'] as int;

        // Calculate a composite score: confidence + text length bonus + segment count bonus
        final score = confidence +
            (textLength > 0 ? 0.1 : 0.0) +
            (segmentCount > 0 ? 0.05 : 0.0);

        debugPrint(
            'GoogleSTTTranslator: Language $language score: $score (confidence: $confidence, length: $textLength, segments: $segmentCount)');

        if (score > bestScore) {
          bestScore = score;
          bestLanguage = language;
          bestText = result['text'] as String;
        }
      }

      debugPrint(
          'GoogleSTTTranslator: Best language match: $bestLanguage (score: $bestScore)');
      debugPrint('GoogleSTTTranslator: Best text: "$bestText"');

      return {
        'language': bestLanguage,
        'confidence': bestScore,
        'text': bestText,
        'allResults': languageResults,
      };
    } catch (e) {
      debugPrint(
          'GoogleSTTTranslator: Language detection error for $audioPath: $e');
      return {'language': null, 'confidence': 0.0, 'text': null};
    }
  }

  /// Calculate language match score between detected and preferred language
  double _calculateLanguageMatchScore(String detectedLanguage,
      String preferredLanguage, double originalConfidence) {
    // Normalize language codes
    final detected = detectedLanguage.toLowerCase().trim();
    final preferred = preferredLanguage.toLowerCase().trim();

    debugPrint(
        'GoogleSTTTranslator: Calculating match score: "$detected" vs "$preferred"');

    // Extract primary language codes (e.g., 'en' from 'en-US')
    final detectedPrimary = detected.split('-')[0].split('_')[0];
    final preferredPrimary = preferred.split('-')[0].split('_')[0];

    // Exact match - highest score
    if (detected == preferred) {
      debugPrint('GoogleSTTTranslator: Exact match: $detected');
      return originalConfidence * 1.0;
    }

    // Primary language code match - high score
    if (detectedPrimary == preferredPrimary) {
      debugPrint('GoogleSTTTranslator: Primary code match: $detectedPrimary');
      return originalConfidence * 0.9;
    }

    // Partial match - medium score
    if (detected.contains(preferred) || preferred.contains(detected)) {
      debugPrint(
          'GoogleSTTTranslator: Partial match: $detected contains $preferred');
      return originalConfidence * 0.8;
    }

    // Handle common language variations
    final languageVariations = {
      'en': ['english', 'eng', 'en-us', 'en-gb'],
      'bn': ['bengali', 'bangla', 'ben', 'bn-bd', 'bn-in'],
      'hi': ['hindi', 'hin', 'hi-in'],
      'es': ['spanish', 'spa', 'es-es', 'es-mx'],
      'fr': ['french', 'fra', 'fr-fr', 'fr-ca'],
      'de': ['german', 'deu', 'de-de'],
      'ja': ['japanese', 'jpn', 'ja-jp'],
      'ko': ['korean', 'kor', 'ko-kr'],
      'zh': ['chinese', 'chi', 'zh-cn', 'zh-tw'],
      'ar': ['arabic', 'ara', 'ar-sa'],
      'pt': ['portuguese', 'por', 'pt-br', 'pt-pt'],
      'ru': ['russian', 'rus', 'ru-ru'],
    };

    // Check if detected language matches any variation of preferred language
    for (final entry in languageVariations.entries) {
      if (entry.key == preferredPrimary) {
        for (final variation in entry.value) {
          if (detected.contains(variation) ||
              detectedPrimary.contains(variation)) {
            debugPrint(
                'GoogleSTTTranslator: Variation match: $detected matches $variation for $preferred');
            return originalConfidence * 0.7;
          }
        }
      }
    }

    // No match found - very low score
    debugPrint('GoogleSTTTranslator: No match found: $detected vs $preferred');
    return originalConfidence * 0.1;
  }

  /// Assign speakers based on language detection results
  Future<Map<String, String>> _assignSpeakersByLanguage(String voice1Path,
      String voice2Path, List<String> preferredLanguages) async {
    try {
      debugPrint(
          'GoogleSTTTranslator: ===== OPTIMIZED LANGUAGE-BASED ASSIGNMENT (3 API calls) =====');
      debugPrint('GoogleSTTTranslator: Voice 1: $voice1Path');
      debugPrint('GoogleSTTTranslator: Voice 2: $voice2Path');
      debugPrint(
          'GoogleSTTTranslator: Preferred languages: $preferredLanguages');

      final speaker1Lang = _speakerLanguages[0]?.code ?? 'en';
      final speaker2Lang = _speakerLanguages[1]?.code ?? 'en';

      // OPTIMIZATION: Only test Voice 1 with both languages (2 API calls)
      // Voice 2's language can be inferred (it's the OTHER language)
      debugPrint(
          'GoogleSTTTranslator: 🚀 OPTIMIZATION: Testing Voice 1 with both languages...');
      debugPrint('GoogleSTTTranslator: This will use 2 API calls for Voice 1');

      final voice1Result =
          await _detectVoiceLanguageOptimized(voice1Path, preferredLanguages);

      debugPrint('GoogleSTTTranslator: Voice 1 language detection result:');
      debugPrint('  Detected Language: ${voice1Result['language']}');
      debugPrint('  Confidence: ${voice1Result['confidence']}');
      debugPrint('  Text: "${voice1Result['text']}"');

      final voice1Language = voice1Result['language'] as String?;

      // Store Voice 1's transcription for reuse (avoid redundant API call later)
      _voice1CachedTranscription = voice1Result;

      // Create assignment based on Voice 1's detected language
      final Map<String, String> assignment = {};
      String voice2AssignedLanguage;

      if (voice1Language != null &&
          preferredLanguages.contains(voice1Language)) {
        // Voice 1's language is detected, assign it to the correct speaker
        if (voice1Language == speaker1Lang) {
          // Voice 1 speaks Speaker 1's language
          assignment['speaker1'] = voice1Path;
          assignment['speaker2'] = voice2Path;
          voice2AssignedLanguage = speaker2Lang;
          debugPrint(
              'GoogleSTTTranslator: ✅ Voice 1 → Speaker 1 ($voice1Language)');
          debugPrint(
              'GoogleSTTTranslator: ✅ Voice 2 → Speaker 2 ($voice2AssignedLanguage) [INFERRED - no API call needed]');
        } else if (voice1Language == speaker2Lang) {
          // Voice 1 speaks Speaker 2's language
          assignment['speaker1'] = voice2Path;
          assignment['speaker2'] = voice1Path;
          voice2AssignedLanguage = speaker1Lang;
          debugPrint(
              'GoogleSTTTranslator: ✅ Voice 1 → Speaker 2 ($voice1Language)');
          debugPrint(
              'GoogleSTTTranslator: ✅ Voice 2 → Speaker 1 ($voice2AssignedLanguage) [INFERRED - no API call needed]');
        } else {
          // Fallback: language doesn't match, use original order
          debugPrint(
              'GoogleSTTTranslator: ⚠️ Voice 1 language ($voice1Language) doesn\'t match configured languages');
          debugPrint(
              'GoogleSTTTranslator: Using default assignment (Voice 1 → Speaker 1, Voice 2 → Speaker 2)');
          assignment['speaker1'] = voice1Path;
          assignment['speaker2'] = voice2Path;
          voice2AssignedLanguage = speaker2Lang;
        }
      } else {
        // No clear detection, use default assignment
        debugPrint(
            'GoogleSTTTranslator: ⚠️ Could not detect Voice 1 language clearly');
        debugPrint(
            'GoogleSTTTranslator: Using default assignment (Voice 1 → Speaker 1, Voice 2 → Speaker 2)');
        assignment['speaker1'] = voice1Path;
        assignment['speaker2'] = voice2Path;
        voice2AssignedLanguage = speaker2Lang;
      }

      // Now transcribe Voice 2 with the inferred language (1 API call)
      // This will be used later in _transcribeSeparatedAudio
      debugPrint(
          'GoogleSTTTranslator: 🚀 OPTIMIZATION: Will transcribe Voice 2 with inferred language ($voice2AssignedLanguage)');
      debugPrint('GoogleSTTTranslator: This will use 1 API call for Voice 2');

      // Store the inferred language for Voice 2 (for reference, though we determine speaker from Voice 1 language)
      _voice2InferredLanguage = voice2AssignedLanguage;

      debugPrint('GoogleSTTTranslator: ===== OPTIMIZATION COMPLETE =====');
      debugPrint('GoogleSTTTranslator: Total API calls used: 2 (Voice 1 only)');
      debugPrint(
          'GoogleSTTTranslator: Voice 2 will use: 1 API call (inferred language)');
      debugPrint(
          'GoogleSTTTranslator: Grand total: 3 API calls (vs 6 in old approach)');
      debugPrint('GoogleSTTTranslator: API call reduction: 50% 🎉');
      debugPrint('GoogleSTTTranslator: Speaker 1: ${assignment['speaker1']}');
      debugPrint('GoogleSTTTranslator: Speaker 2: ${assignment['speaker2']}');
      debugPrint(
          'GoogleSTTTranslator: ==========================================');

      return assignment;
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Language-based assignment error: $e');
      // Fallback to original order
      return {
        'speaker1': voice1Path,
        'speaker2': voice2Path,
      };
    }
  }

  /// Create a silent audio file for missing speakers
  Future<String?> _createSilentAudioFile(String prefix) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final silentFilePath = '${directory.path}/${prefix}_${timestamp}.wav';

      // Create a 2-second silent WAV file (16kHz, 16-bit, mono)
      const sampleRate = 16000;
      const duration = 2.0; // 2 seconds
      final numSamples = (sampleRate * duration).round();

      // WAV header (44 bytes)
      final header = Uint8List(44);
      final data = ByteData.view(header.buffer);

      // RIFF header
      data.setUint8(0, 0x52); // 'R'
      data.setUint8(1, 0x49); // 'I'
      data.setUint8(2, 0x46); // 'F'
      data.setUint8(3, 0x46); // 'F'
      data.setUint32(4, 36 + numSamples * 2, Endian.little); // File size - 8

      // WAVE header
      data.setUint8(8, 0x57); // 'W'
      data.setUint8(9, 0x41); // 'A'
      data.setUint8(10, 0x56); // 'V'
      data.setUint8(11, 0x45); // 'E'

      // fmt chunk
      data.setUint8(12, 0x66); // 'f'
      data.setUint8(13, 0x6D); // 'm'
      data.setUint8(14, 0x74); // 't'
      data.setUint8(15, 0x20); // ' '
      data.setUint32(16, 16, Endian.little); // fmt chunk size
      data.setUint16(20, 1, Endian.little); // Audio format (PCM)
      data.setUint16(22, 1, Endian.little); // Number of channels (mono)
      data.setUint32(24, sampleRate, Endian.little); // Sample rate
      data.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
      data.setUint16(32, 2, Endian.little); // Block align
      data.setUint16(34, 16, Endian.little); // Bits per sample

      // data chunk
      data.setUint8(36, 0x64); // 'd'
      data.setUint8(37, 0x61); // 'a'
      data.setUint8(38, 0x74); // 't'
      data.setUint8(39, 0x61); // 'a'
      data.setUint32(40, numSamples * 2, Endian.little); // Data size

      // Create silent audio data (all zeros)
      final audioData = Uint8List(numSamples * 2);

      // Combine header and audio data
      final silentFile = Uint8List(44 + numSamples * 2);
      silentFile.setRange(0, 44, header);
      silentFile.setRange(44, 44 + numSamples * 2, audioData);

      // Write to file
      await File(silentFilePath).writeAsBytes(silentFile);

      debugPrint(
          'GoogleSTTTranslator: Created silent audio file: $silentFilePath');
      debugPrint(
          '  Duration: ${duration}s, Sample rate: ${sampleRate}Hz, Size: ${silentFile.length} bytes');

      return silentFilePath;
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Failed to create silent audio file: $e');
      return null;
    }
  }

  /// Generate stereo audio file from TTS audio files
  /// This method creates the stereo file once and caches it for reuse
  Future<void> _generateStereoAudioFile() async {
    try {
      debugPrint(
          'GoogleSTTTranslator: Starting stereo audio file generation...');

      setState(() {
        _processingStatus = 'Creating stereo audio...';
        _processingProgress = 0.95;
      });

      debugPrint('  Speaker1TtsAudioPath: $_speaker1TtsAudioPath');
      debugPrint('  Speaker2TtsAudioPath: $_speaker2TtsAudioPath');

      // Handle single-speaker scenarios by creating silent audio for missing speakers
      bool needsSilentAudio = false;

      if (_speaker1TtsAudioPath == null) {
        debugPrint(
            'GoogleSTTTranslator: Speaker 1 TTS missing, will create silent audio');
        _speaker1TtsAudioPath = await _createSilentAudioFile('speaker1_silent');
        needsSilentAudio = true;
      }

      if (_speaker2TtsAudioPath == null) {
        debugPrint(
            'GoogleSTTTranslator: Speaker 2 TTS missing, will create silent audio');
        _speaker2TtsAudioPath = await _createSilentAudioFile('speaker2_silent');
        needsSilentAudio = true;
      }

      if (needsSilentAudio) {
        debugPrint(
            'GoogleSTTTranslator: Created silent audio files for missing speakers');
      }

      // Check if both files exist
      final leftFile = File(_speaker1TtsAudioPath!);
      final rightFile = File(_speaker2TtsAudioPath!);

      final leftExists = await leftFile.exists();
      final rightExists = await rightFile.exists();

      debugPrint('GoogleSTTTranslator: TTS file existence check:');
      debugPrint('  Left file exists: $leftExists');
      debugPrint('  Right file exists: $rightExists');

      if (!leftExists || !rightExists) {
        debugPrint(
            'GoogleSTTTranslator: Cannot generate stereo audio - TTS files do not exist');
        if (!leftExists) {
          debugPrint('  Left TTS file missing: $_speaker1TtsAudioPath');
        }
        if (!rightExists) {
          debugPrint('  Right TTS file missing: $_speaker2TtsAudioPath');
        }
        return;
      }

      // Check file sizes
      final leftSize = await leftFile.length();
      final rightSize = await rightFile.length();
      debugPrint('GoogleSTTTranslator: TTS file sizes:');
      debugPrint('  Left file size: $leftSize bytes');
      debugPrint('  Right file size: $rightSize bytes');

      debugPrint('GoogleSTTTranslator: Generating stereo audio file...');
      debugPrint('  Speaker 1 TTS file: $_speaker1TtsAudioPath');
      debugPrint('  Speaker 2 TTS file: $_speaker2TtsAudioPath');
      debugPrint('  Speaker 1 earpiece: ${_speakerEarpieces[0]}');
      debugPrint('  Speaker 2 earpiece: ${_speakerEarpieces[1]}');

      // Determine which TTS file goes to which channel based on earpiece configuration
      // CORRECT LOGIC: Each speaker's translated TTS should play in the OTHER speaker's earpiece
      String leftChannelFile;
      String rightChannelFile;

      if (_speakerEarpieces[0] == 'left') {
        // Speaker 1 has left earpiece, so Speaker 2's translated TTS goes to left channel (for Speaker 1 to hear)
        // Speaker 2 has right earpiece, so Speaker 1's translated TTS goes to right channel (for Speaker 2 to hear)
        leftChannelFile =
            _speaker2TtsAudioPath!; // Speaker 2's translated TTS for Speaker 1's left earpiece
        rightChannelFile =
            _speaker1TtsAudioPath!; // Speaker 1's translated TTS for Speaker 2's right earpiece
        debugPrint(
            'GoogleSTTTranslator: Audio routing - Left channel: Speaker 2 TTS (for Speaker 1), Right channel: Speaker 1 TTS (for Speaker 2)');
      } else {
        // Speaker 1 has right earpiece, so Speaker 2's translated TTS goes to right channel (for Speaker 1 to hear)
        // Speaker 2 has left earpiece, so Speaker 1's translated TTS goes to left channel (for Speaker 2 to hear)
        leftChannelFile =
            _speaker1TtsAudioPath!; // Speaker 1's translated TTS for Speaker 2's left earpiece
        rightChannelFile =
            _speaker2TtsAudioPath!; // Speaker 2's translated TTS for Speaker 1's right earpiece
        debugPrint(
            'GoogleSTTTranslator: Audio routing - Left channel: Speaker 1 TTS (for Speaker 2), Right channel: Speaker 2 TTS (for Speaker 1)');
      }

      // Generate stereo audio file using the robust service
      _cachedStereoAudioPath =
          await _stereoTtsService.createTrueStereoAudioFile(
        leftChannelFile,
        rightChannelFile,
        outputFileName:
            'cached_stereo_${DateTime.now().millisecondsSinceEpoch}.wav',
      );

      if (_cachedStereoAudioPath != null) {
        debugPrint(
            'GoogleSTTTranslator: Stereo audio file generated and cached: $_cachedStereoAudioPath');

        // Verify the cached file exists
        final cachedFile = File(_cachedStereoAudioPath!);
        final cachedExists = await cachedFile.exists();
        final cachedSize = cachedExists ? await cachedFile.length() : 0;
        debugPrint('GoogleSTTTranslator: Cached stereo file verification:');
        debugPrint('  File exists: $cachedExists');
        debugPrint('  File size: $cachedSize bytes');

        setState(() {
          _processingStatus = 'Ready to play!';
          _processingProgress = 1.0;
        });

        // Auto-play the stereo audio if file was successfully generated
        if (cachedExists && cachedSize > 0) {
          debugPrint('GoogleSTTTranslator: Auto-playing stereo audio...');
          // Add a small delay to ensure UI updates and user sees the stereo audio is ready
          await Future.delayed(const Duration(milliseconds: 500));
          await _autoPlayStereoAudio();

          // Clear processing state after auto-play starts
          setState(() {
            _isProcessing = false;
          });
        } else {
          debugPrint(
              'GoogleSTTTranslator: Stereo audio file is empty or missing, skipping auto-play');
          setState(() {
            _isProcessing = false;
          });
        }
      } else {
        debugPrint(
            'GoogleSTTTranslator: Failed to generate stereo audio file - returned null');
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('GoogleSTTTranslator: Error generating stereo audio file: $e');
      debugPrint('GoogleSTTTranslator: Stack trace: $stackTrace');

      setState(() {
        _isProcessing = false;
        _processingStatus = 'Error occurred';
      });
    } finally {
      // Defer cleanup; we'll clean after playback completes so UI buttons keep working
      _pendingStereoPlaybackCleanup = true;
      debugPrint(
          'GoogleSTTTranslator: Deferring TTS cleanup until playback completion');
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

  /// Play TTS audio for Speaker 1's translated text
  Future<void> _playSpeaker1TtsAudio() async {
    try {
      // If TTS not ready but translation exists, generate on-demand
      if ((_speaker1TtsAudioPath == null || _speaker1TtsAudioPath!.isEmpty) &&
          (_translations[0]?.isNotEmpty ?? false)) {
        debugPrint(
            'GoogleSTTTranslator: Speaker 1 TTS missing, generating on-demand...');
        final speaker2Language = _speakerLanguages[1];
        if (speaker2Language != null) {
          _speaker1TtsAudioPath = await _ttsService.generateAudioFile(
            _translations[0]!,
            speaker2Language.code,
            gender: _speakerGenders[0],
          );
        }
      }
      if (_speaker1TtsAudioPath == null || _speaker1TtsAudioPath!.isEmpty) {
        debugPrint('GoogleSTTTranslator: No TTS audio available for Speaker 1');
        return;
      }

      if (_isPlayingTts1) {
        await _ttsService.stop();
        setState(() {
          _isPlayingTts1 = false;
        });
      } else {
        // Stop other TTS playback
        if (_isPlayingTts2) {
          await _ttsService.stop();
          setState(() {
            _isPlayingTts2 = false;
          });
        }

        await _ttsService.playAudioFile(_speaker1TtsAudioPath!);
        setState(() {
          _isPlayingTts1 = true;
        });
      }
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Speaker 1 TTS playback error: $e');
      setState(() {
        _isPlayingTts1 = false;
      });
    }
  }

  /// Play TTS audio for Speaker 2's translated text
  Future<void> _playSpeaker2TtsAudio() async {
    try {
      // If TTS not ready but translation exists, generate on-demand
      if ((_speaker2TtsAudioPath == null || _speaker2TtsAudioPath!.isEmpty) &&
          (_translations[1]?.isNotEmpty ?? false)) {
        debugPrint(
            'GoogleSTTTranslator: Speaker 2 TTS missing, generating on-demand...');
        final speaker1Language = _speakerLanguages[0];
        if (speaker1Language != null) {
          _speaker2TtsAudioPath = await _ttsService.generateAudioFile(
            _translations[1]!,
            speaker1Language.code,
            gender: _speakerGenders[1],
          );
        }
      }
      if (_speaker2TtsAudioPath == null || _speaker2TtsAudioPath!.isEmpty) {
        debugPrint('GoogleSTTTranslator: No TTS audio available for Speaker 2');
        return;
      }

      if (_isPlayingTts2) {
        await _ttsService.stop();
        setState(() {
          _isPlayingTts2 = false;
        });
      } else {
        // Stop other TTS playback
        if (_isPlayingTts1) {
          await _ttsService.stop();
          setState(() {
            _isPlayingTts1 = false;
          });
        }

        await _ttsService.playAudioFile(_speaker2TtsAudioPath!);
        setState(() {
          _isPlayingTts2 = true;
        });
      }
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Speaker 2 TTS playback error: $e');
      setState(() {
        _isPlayingTts2 = false;
      });
    }
  }

  /// Play stereo audio with both speakers' translated text
  /// Left channel: Speaker 1's translated text (for Speaker 2 to hear)
  /// Right channel: Speaker 2's translated text (for Speaker 1 to hear)
  Future<void> _playStereoAudio() async {
    try {
      // Manual play should not require translations; rely on cached stereo file

      if (_isPlayingStereo) {
        // Stop stereo audio
        await _stereoTtsService.stopStereoAudio();
        setState(() {
          _isPlayingStereo = false;
        });
        debugPrint('GoogleSTTTranslator: Stereo audio stopped');
      } else {
        // Stop any individual TTS playback
        await _ttsService.stop();
        setState(() {
          _isPlayingTts1 = false;
          _isPlayingTts2 = false;
        });

        // Check if we have a cached stereo audio file
        if (_cachedStereoAudioPath == null) {
          debugPrint(
              'GoogleSTTTranslator: No cached stereo audio file available');
          _showErrorDialog(
              'Stereo audio file not available. Please try again.');
          return;
        }

        // Check if the cached file exists
        final stereoFile = File(_cachedStereoAudioPath!);
        if (!await stereoFile.exists()) {
          debugPrint(
              'GoogleSTTTranslator: Cached stereo audio file does not exist: $_cachedStereoAudioPath');
          _showErrorDialog('Stereo audio file not found. Please try again.');
          return;
        }

        debugPrint('GoogleSTTTranslator: Playing cached stereo audio...');
        debugPrint('  Cached stereo file: $_cachedStereoAudioPath');

        // CRITICAL: Switch to playback route for proper TWS stereo routing
        debugPrint('GoogleSTTTranslator: Switching to playback route...');
        await _enterPlaybackRoute();

        // IMPORTANT: Add delay to allow audio system to switch modes
        // TWS devices need time to switch from SCO/COMMUNICATION to A2DP/MUSIC mode
        // Android 11 may need longer delay for proper mode switching
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint(
            'GoogleSTTTranslator: ✅ Audio route switched (waited 500ms), ready for stereo playback');

        // Play the cached stereo audio file
        await _stereoTtsService.playStereoAudio(_cachedStereoAudioPath!);

        setState(() {
          _isPlayingStereo = true;
        });
        debugPrint('GoogleSTTTranslator: Stereo audio playing successfully');
      }
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Stereo audio playback error: $e');
      setState(() {
        _isPlayingStereo = false;
      });
      _showErrorDialog('Error playing stereo audio: $e');
    }
  }

  /// Auto-play stereo audio immediately after generation
  /// This method is called automatically when stereo audio is successfully generated
  Future<void> _autoPlayStereoAudio() async {
    try {
      // GUARD: Prevent multiple simultaneous playbacks
      if (_isPlayingStereo) {
        debugPrint(
            'GoogleSTTTranslator: ⚠️ Stereo audio already playing, skipping auto-play');
        return;
      }

      debugPrint('GoogleSTTTranslator: Starting auto-play of stereo audio...');

      // Do not require translations for auto-play; rely on generated stereo file

      // CRITICAL: Switch to playback route for proper TWS stereo routing
      debugPrint(
          'GoogleSTTTranslator: Auto-play: Switching to playback route...');
      await _enterPlaybackRoute();

      // IMPORTANT: Add delay to allow audio system to switch modes
      // TWS devices need time to switch from SCO/COMMUNICATION to A2DP/MUSIC mode
      // Android 11 may need longer delay for proper mode switching
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint(
          'GoogleSTTTranslator: ✅ Audio route switched for auto-play (waited 500ms)');

      // Check if we have language information
      final speaker1Language = _speakerLanguages[0];
      final speaker2Language = _speakerLanguages[1];
      if (speaker1Language == null || speaker2Language == null) {
        debugPrint(
            'GoogleSTTTranslator: No language information available for auto-play stereo audio');
        return;
      }

      // Check if we have a cached stereo audio file
      if (_cachedStereoAudioPath == null) {
        debugPrint(
            'GoogleSTTTranslator: No cached stereo audio file available for auto-play');
        return;
      }

      // Check if the cached file exists
      final stereoFile = File(_cachedStereoAudioPath!);
      if (!await stereoFile.exists()) {
        debugPrint(
            'GoogleSTTTranslator: Cached stereo audio file does not exist for auto-play: $_cachedStereoAudioPath');
        return;
      }

      debugPrint('GoogleSTTTranslator: Auto-playing cached stereo audio...');
      debugPrint('  Cached stereo file: $_cachedStereoAudioPath');
      debugPrint(
          '  Left channel (Speaker 1): "${_translations[0]}" in ${speaker2Language.code}');
      debugPrint(
          '  Right channel (Speaker 2): "${_translations[1]}" in ${speaker1Language.code}');

      // Stop any individual TTS playback before starting stereo
      await _ttsService.stop();
      setState(() {
        _isPlayingTts1 = false;
        _isPlayingTts2 = false;
        _isPlayingStereo =
            true; // Set BEFORE playing to prevent race conditions
      });

      // Play the cached stereo audio file
      await _stereoTtsService.playStereoAudio(_cachedStereoAudioPath!);

      debugPrint(
          'GoogleSTTTranslator: ✅ Auto-play stereo audio started successfully');
      debugPrint(
          'GoogleSTTTranslator: Waiting for playback completion callback...');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: ❌ Auto-play stereo audio error: $e');
      setState(() {
        _isPlayingStereo = false;
      });
      // Don't show error dialog for auto-play failures - just log them
      debugPrint(
          'GoogleSTTTranslator: Auto-play failed silently, user can still play manually');
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
        0.001; // Minimum energy to be considered voice (lowered from 0.01)
    const int minSilenceDuration = 8000; // 0.5 seconds of silence
    const int minVoiceDuration = 4800; // 0.3 seconds minimum voice

    debugPrint(
        'GoogleSTTTranslator: Voice activity detection - Audio data length: ${audioData.length} samples');
    debugPrint('GoogleSTTTranslator: Energy threshold: $energyThreshold');

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

      // Debug logging for energy values
      if (i % (windowSize * 10) == 0) {
        // Log every 10th window to avoid spam
        debugPrint(
            'GoogleSTTTranslator: Energy at sample $i: ${energy.toStringAsFixed(6)}, threshold: $energyThreshold');
      }

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

  // Download dialogs removed - no model downloads needed with Azure Translator API

  /// Start automatic translation mode
  Future<void> _startAutomaticMode() async {
    if (_isAutomaticMode) return;

    setState(() {
      _isAutomaticMode = true;
    });

    debugPrint('GoogleSTTTranslator: Starting automatic translation mode');

    // Start the continuous translation loop
    await _startContinuousTranslationLoop();
  }

  /// Stop automatic translation mode
  Future<void> _stopAutomaticMode() async {
    if (!_isAutomaticMode) return;

    setState(() {
      _isAutomaticMode = false;
      _isContinuousRecording = false;
    });

    // Stop any ongoing recording
    if (_isRecording) {
      await _stopRecording();
    }

    // Cancel silent detection timer
    _silentDetectionTimer?.cancel();
    _silentDetectionTimer = null;

    // Stop noise meter monitoring
    _stopSoundLevelMonitoring();

    debugPrint('GoogleSTTTranslator: Stopped automatic translation mode');
  }

  /// Stop sound level monitoring
  void _stopSoundLevelMonitoring() {
    debugPrint('GoogleSTTTranslator: Stopping sound level monitoring');

    // Cancel noise meter subscription
    _noiseSubscription?.cancel();
    _noiseSubscription = null;

    // Dispose noise meter
    _noiseMeter = null;

    // Reset sound level data
    setState(() {
      _currentSoundLevel = 0.0;
      _soundLevelHistory.clear();
    });
  }

  /// Start continuous translation loop
  Future<void> _startContinuousTranslationLoop() async {
    if (!_isAutomaticMode) return;

    debugPrint('GoogleSTTTranslator: Starting continuous translation loop');

    // Start recording with sound level monitoring
    await _startAutomaticRecording();
  }

  /// Start automatic recording with sound level monitoring
  Future<void> _startAutomaticRecording() async {
    if (!_isAutomaticMode || _isRecording) return;

    try {
      debugPrint('GoogleSTTTranslator: ═══ Starting new recording cycle ═══');

      // NOTE: We do NOT stop playback here!
      // Playback should have already finished before this is called.
      // This method is only called from the playback completion callback.

      // NOTE: We do NOT clean up files here!
      // Files are cleaned up AFTER stereo generation and playback completes.
      // This prevents deleting TTS files that are still being used.

      setState(() {
        _isContinuousRecording = true;
        _isRecording = true;
        _isSilentDetectionActive = false;
        _silentDetectionCountdown = 0;
        _consecutiveSpeechDetections = 0; // Reset speech detection counter
        _hasDetectedSpeechInSession = false; // Reset first speech flag
        _isProcessing = false; // Ensure processing flag is cleared
        _isPlayingStereo = false; // Ensure playback flag is cleared
      });

      debugPrint(
          'GoogleSTTTranslator: Starting automatic recording (waiting for first speech...)');

      // CRITICAL: Ensure no audio is playing before starting mic
      // This prevents capturing TTS audio from previous cycle
      if (_isPlayingStereo) {
        debugPrint(
            'GoogleSTTTranslator: ⚠️ Stereo audio still playing, waiting...');
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      // Play start recording sound effect
      await _playStartRecordingSound();

      // IMPORTANT: Start recorder FIRST before noise meter
      // This ensures the recorder gets priority access to the microphone

      // Get recording path
      final directory = await getApplicationDocumentsDirectory();
      final recordingPath =
          '${directory.path}/auto_recording_${DateTime.now().millisecondsSinceEpoch}.wav';

      // Start NATIVE recording with FORCED phone mic
      debugPrint('GoogleSTTTranslator: [AUTO] Starting NATIVE recorder...');
      debugPrint(
          'GoogleSTTTranslator: [AUTO] Forced MIC audio source (phone mic only)');
      final bool started = await _nativeRecorder.startRecording(recordingPath);

      if (!started) {
        debugPrint(
            'GoogleSTTTranslator: ❌ [AUTO] Failed to start native recording');
        return;
      }

      _recordedAudioPath = recordingPath;

      debugPrint('GoogleSTTTranslator: Audio recorder started successfully');

      // Add a small delay to ensure recorder has exclusive microphone access
      await Future.delayed(const Duration(milliseconds: 200));

      // Start sound level monitoring (now sharing microphone with recorder)
      _startSoundLevelMonitoring();

      // DON'T start silent detection timer yet!
      // It will start automatically when first speech is detected
      debugPrint(
          'GoogleSTTTranslator: Waiting for first speech to activate silent detection...');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Error starting automatic recording: $e');
      setState(() {
        _isRecording = false;
        _isContinuousRecording = false;
      });
    }
  }

  /// Start sound level monitoring using real microphone input
  void _startSoundLevelMonitoring() {
    debugPrint(
      'GoogleSTTTranslator: Starting real-time microphone amplitude monitoring',
    );

    try {
      // Initialize noise meter for real-time microphone monitoring
      _noiseMeter = NoiseMeter();

      // Start listening to real microphone input
      _noiseSubscription = _noiseMeter!.noise.listen(
        (NoiseReading noiseReading) {
          if (!_isAutomaticMode || !_isRecording) return;

          // Convert decibel reading to normalized amplitude (0.0 to 1.0)
          final normalizedAmplitude = _convertDecibelToAmplitude(
            noiseReading.meanDecibel,
          );

          setState(() {
            _currentSoundLevel = normalizedAmplitude;

            // Add to history for graph (keep last 100 samples)
            _soundLevelHistory.add(normalizedAmplitude);
            if (_soundLevelHistory.length > 100) {
              _soundLevelHistory.removeAt(0);
            }
          });

          // Log significant changes
          if (normalizedAmplitude > 0.05 ||
              (normalizedAmplitude - _currentSoundLevel).abs() > 0.1) {
            debugPrint(
              'GoogleSTTTranslator: Real microphone amplitude: ${noiseReading.meanDecibel.toStringAsFixed(1)} dB, normalized: ${(normalizedAmplitude * 100).toStringAsFixed(1)}%',
            );
          }

          // Check if sound level indicates speech
          if (_isSpeechDetected(normalizedAmplitude)) {
            _onSpeechDetected();
          }
        },
        onError: (error) {
          debugPrint('GoogleSTTTranslator: Noise meter error: $error');
        },
      );

      debugPrint(
        'GoogleSTTTranslator: Real-time microphone monitoring started successfully',
      );
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Error starting noise meter: $e');
    }
  }

  /// Convert decibel reading to normalized amplitude (0.0 to 1.0)
  double _convertDecibelToAmplitude(double decibel) {
    // Real-world range: 30 dB (quiet) to 80 dB (loud speech)
    final normalized = (decibel - 30) / 50;
    return normalized.clamp(0.0, 1.0);
  }

  /// Check if current sound level indicates speech
  bool _isSpeechDetected(double soundLevel) {
    final isAboveThreshold =
        soundLevel >= _minSpeechLevel && soundLevel <= _maxSpeechLevel;

    // Track consecutive speech detections to avoid false triggers from brief noise spikes
    if (isAboveThreshold) {
      _consecutiveSpeechDetections++;
    } else {
      _consecutiveSpeechDetections = 0; // Reset counter when below threshold
    }

    // Require multiple consecutive detections to confirm actual speech
    final isSpeech =
        _consecutiveSpeechDetections >= _minConsecutiveSpeechDetections;

    // Debug logging for speech detection
    if (soundLevel > 0.05) {
      // Only log if there's some sound
      debugPrint(
          'GoogleSTTTranslator: Sound level: ${(soundLevel * 100).toStringAsFixed(1)}%, '
          'Above threshold: $isAboveThreshold, Consecutive: $_consecutiveSpeechDetections, '
          'Speech confirmed: $isSpeech, Threshold: ${(_minSpeechLevel * 100).toStringAsFixed(0)}%');
    }

    return isSpeech;
  }

  /// Handle speech detection
  void _onSpeechDetected() {
    // Check if this is the first speech in this session
    if (!_hasDetectedSpeechInSession) {
      _hasDetectedSpeechInSession = true;
      debugPrint(
          'GoogleSTTTranslator: First speech detected! Starting silent detection timer');

      // Start silent detection timer for the first time
      _startSilentDetectionTimer();
      return;
    }

    // If already in silent detection mode, reset the timer
    if (!_isSilentDetectionActive) return;

    debugPrint(
        'GoogleSTTTranslator: Speech detected, resetting silent detection timer');

    // Reset silent detection timer
    _silentDetectionTimer?.cancel();
    _startSilentDetectionTimer();
  }

  /// Start silent detection timer
  void _startSilentDetectionTimer() {
    _silentDetectionTimer?.cancel();

    setState(() {
      _isSilentDetectionActive = true;
      _silentDetectionCountdown = _silentDetectionDuration;
    });

    debugPrint(
        'GoogleSTTTranslator: Starting silent detection timer (${_silentDetectionDuration}s)');

    _silentDetectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isAutomaticMode || !_isRecording) {
        timer.cancel();
        debugPrint(
            'GoogleSTTTranslator: Silent detection timer cancelled - mode changed');
        return;
      }

      setState(() {
        _silentDetectionCountdown--;
      });

      debugPrint(
          'GoogleSTTTranslator: Silent detection countdown: ${_silentDetectionCountdown}s');

      if (_silentDetectionCountdown <= 0) {
        timer.cancel();
        debugPrint('GoogleSTTTranslator: Silent detection timeout reached');
        _onSilentDetectionTimeout();
      }
    });
  }

  /// Handle silent detection timeout
  Future<void> _onSilentDetectionTimeout() async {
    if (!_isAutomaticMode || !_isRecording) return;

    debugPrint(
        'GoogleSTTTranslator: Silent detection timeout, stopping recording');

    // Play stop recording sound effect
    await _playStopRecordingSound();

    // Stop recording
    await _stopRecording();

    // Process the recorded audio
    await _processRecordedAudio();
  }

  /// Process recorded audio through the translation pipeline
  Future<void> _processRecordedAudio() async {
    if (!_isAutomaticMode) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      debugPrint(
          'GoogleSTTTranslator: Processing recorded audio in automatic mode');

      // Set up playback completion callback BEFORE processing starts
      // This ensures the callback is ready when auto-play happens
      _setupPlaybackCompletionCallback();

      // Process through the existing pipeline (this will trigger auto-play)
      await _processAudio();

      // Note: The callback will handle restarting after playback completes
      debugPrint(
          'GoogleSTTTranslator: Processing complete, waiting for TTS playback to finish...');
    } catch (e) {
      debugPrint(
          'GoogleSTTTranslator: Error processing audio in automatic mode: $e');
      setState(() {
        _isProcessing = false;
      });

      // Restart recording after error
      await Future.delayed(const Duration(seconds: 2));
      await _startAutomaticRecording();
    }
  }

  /// Set up playback completion callback for automatic restart
  void _setupPlaybackCompletionCallback() {
    debugPrint(
        'GoogleSTTTranslator: Playback completion callback already set up in initState() - no action needed');

    // NOTE: The callback is already set up in initState() as a unified callback
    // that handles both UI state updates and automatic mode restart.
    // No need to set up another callback here.
  }

  /// Build sound level graph widget
  Widget _buildSoundLevelGraph() {
    if (!_isAutomaticMode) return const SizedBox.shrink();

    return Container(
      height: 120,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isRecording ? Colors.green : Colors.grey,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.graphic_eq,
                color: _isRecording ? Colors.green : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Sound Level Monitor',
                style: TextStyle(
                  color: _isRecording ? Colors.green : Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_isSilentDetectionActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange, width: 1),
                  ),
                  child: Text(
                    'Silent: ${_silentDetectionCountdown}s',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              // Manual testing toggle
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isManualTestingMode = !_isManualTestingMode;
                    if (_isManualTestingMode) {
                      _manualAmplitude = 0.0;
                    }
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isManualTestingMode
                        ? Colors.blue.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isManualTestingMode ? Colors.blue : Colors.grey,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _isManualTestingMode ? 'Manual' : 'Auto',
                    style: TextStyle(
                      color: _isManualTestingMode ? Colors.blue : Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              painter: SoundLevelGraphPainter(
                soundLevelHistory: _soundLevelHistory,
                currentLevel: _currentSoundLevel,
                isRecording: _isRecording,
                speechThreshold: _minSpeechLevel,
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Current: ${(_currentSoundLevel * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _isRecording ? Colors.green : Colors.grey,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                'Speech Threshold: ${(_minSpeechLevel * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          // Manual testing controls
          if (_isManualTestingMode) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Manual Amplitude:',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _manualAmplitude,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (value) {
                      setState(() {
                        _manualAmplitude = value;
                      });
                    },
                    activeColor: Colors.blue,
                    inactiveColor: Colors.grey,
                  ),
                ),
                Text(
                  '${(_manualAmplitude * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _manualAmplitude = 0.0;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: const Text('Silence', style: TextStyle(fontSize: 10)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _manualAmplitude = 0.1;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: const Text('Low', style: TextStyle(fontSize: 10)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _manualAmplitude = 0.3;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: const Text('Speech', style: TextStyle(fontSize: 10)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _manualAmplitude = 0.6;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  child: const Text('Loud', style: TextStyle(fontSize: 10)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Clean up only TTS files (called after stereo generation)
  Future<void> _cleanupTtsFiles() async {
    try {
      debugPrint('GoogleSTTTranslator: Cleaning up TTS files...');

      int deletedCount = 0;

      // Delete TTS audio files
      if (_speaker1TtsAudioPath != null) {
        final file1 = File(_speaker1TtsAudioPath!);
        if (await file1.exists()) {
          await file1.delete();
          deletedCount++;
          debugPrint(
              'GoogleSTTTranslator: Deleted Speaker 1 TTS: $_speaker1TtsAudioPath');
        }
        _speaker1TtsAudioPath = null;
      }

      if (_speaker2TtsAudioPath != null) {
        final file2 = File(_speaker2TtsAudioPath!);
        if (await file2.exists()) {
          await file2.delete();
          deletedCount++;
          debugPrint(
              'GoogleSTTTranslator: Deleted Speaker 2 TTS: $_speaker2TtsAudioPath');
        }
        _speaker2TtsAudioPath = null;
      }

      debugPrint('GoogleSTTTranslator: ✅ Cleaned up $deletedCount TTS files');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Error cleaning up TTS files: $e');
    }
  }

  /// Clean up files from previous cycle
  Future<void> _cleanupPreviousCycleFiles() async {
    try {
      debugPrint('GoogleSTTTranslator: Cleaning up previous cycle files...');

      int deletedCount = 0;

      // NOTE: TTS files are cleaned up separately after stereo generation
      // This prevents deleting files that are still being used

      // Delete cached stereo audio file
      if (_cachedStereoAudioPath != null) {
        final stereoFile = File(_cachedStereoAudioPath!);
        if (await stereoFile.exists()) {
          await stereoFile.delete();
          deletedCount++;
          debugPrint(
              'GoogleSTTTranslator: Deleted cached stereo: $_cachedStereoAudioPath');
        }
        _cachedStereoAudioPath = null;
      }

      // Delete previous speaker audio files from diarization
      if (_speaker1AudioPath != null) {
        final sp1File = File(_speaker1AudioPath!);
        if (await sp1File.exists()) {
          await sp1File.delete();
          deletedCount++;
        }
        _speaker1AudioPath = null;
      }

      if (_speaker2AudioPath != null) {
        final sp2File = File(_speaker2AudioPath!);
        if (await sp2File.exists()) {
          await sp2File.delete();
          deletedCount++;
        }
        _speaker2AudioPath = null;
      }

      debugPrint(
          'GoogleSTTTranslator: ✅ Cleaned up $deletedCount files from previous cycle');
    } catch (e) {
      debugPrint('GoogleSTTTranslator: Error cleaning up files: $e');
      // Don't block new cycle if cleanup fails
    }
  }

  /// Play start recording sound effect using system sound
  /// Play start recording sound effect
  /// Uses custom sound file if available, falls back to system sound
  Future<void> _playStartRecordingSound() async {
    try {
      // Try to play custom sound file first
      try {
        await _soundEffectPlayer
            .play(AssetSource('sounds/recording_start.mp3'));
        debugPrint(
            'GoogleSTTTranslator: ✅ Played START recording sound (custom)');
      } catch (e) {
        // Fallback to system sound if custom file not available
        debugPrint(
            'GoogleSTTTranslator: Custom sound not found, using system sound');
        SystemSound.play(SystemSoundType.click);
        debugPrint(
            'GoogleSTTTranslator: ✅ Played START recording sound (system click)');
      }
    } catch (e) {
      debugPrint(
          'GoogleSTTTranslator: ❌ Error playing start recording sound: $e');
      // Don't block recording if sound effect fails
    }
  }

  /// Play stop recording sound effect
  /// Uses custom sound file if available, falls back to system sound
  Future<void> _playStopRecordingSound() async {
    try {
      // Try to play custom sound file first
      try {
        await _soundEffectPlayer.play(AssetSource('sounds/recording_stop.mp3'));
        debugPrint(
            'GoogleSTTTranslator: ✅ Played STOP recording sound (custom)');
      } catch (e) {
        // Fallback to system sound if custom file not available
        debugPrint(
            'GoogleSTTTranslator: Custom sound not found, using system sound');
        SystemSound.play(SystemSoundType.alert);
        debugPrint(
            'GoogleSTTTranslator: ✅ Played STOP recording sound (system alert)');
      }
    } catch (e) {
      debugPrint(
          'GoogleSTTTranslator: ❌ Error playing stop recording sound: $e');
      // Don't block processing if sound effect fails
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    // Native recorder doesn't need explicit dispose
    _speaker1Player.dispose();
    _speaker2Player.dispose();
    _soundEffectPlayer.dispose();
    _ttsService.dispose();
    _stereoTtsService.dispose();
    // Translation service is static - no dispose needed
    // Note: No need to dispose SystemSound

    // Clean up automatic mode resources
    _silentDetectionTimer?.cancel();
    _silentDetectionTimer = null;

    // Clean up noise meter resources
    _stopSoundLevelMonitoring();

    // Clean up real-time resources
    _audioPollingTimer?.cancel();
    _audioChunkSubscription?.cancel();
    _sonioxStreamSubscription?.cancel();
    _sonioxService.dispose();
    _streamingRecorder.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Circular progress indicator
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D9FF)),
                ),
                const SizedBox(height: 30),

                // Status text
                Text(
                  'Initializing translator...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
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
        if (!_showSpeakerSetup) ...[
          // Mode toggle button (Real-time / Manual)
          IconButton(
            icon: Icon(
              _isRealtimeMode ? Icons.flash_on : Icons.flash_off,
              color: _isRealtimeMode ? Colors.purple : Colors.white,
            ),
            tooltip: _isRealtimeMode ? 'Real-time Mode' : 'Manual Mode',
            onPressed: _toggleTranslationMode,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              setState(() {
                _showSpeakerSetup = true;
              });
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSpeakerSetupScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Configure Speakers',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // Mode indicator
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isRealtimeMode
                  ? Colors.purple.withValues(alpha: 0.2)
                  : Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isRealtimeMode ? Colors.purple : Colors.blue,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isRealtimeMode ? Icons.flash_on : Icons.flash_off,
                  color: _isRealtimeMode ? Colors.purple : Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRealtimeMode ? 'Real-time Mode' : 'Manual Mode',
                        style: TextStyle(
                          color: _isRealtimeMode ? Colors.purple : Colors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isRealtimeMode
                            ? 'Continuous translation with instant TTS playback'
                            : 'Press stop button to process translation',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz, color: Colors.white),
                  onPressed: _toggleTranslationMode,
                  tooltip: 'Switch mode',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(_numberOfSpeakers, (index) {
            return _buildSpeakerConfig(index);
          }),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isStartingSession ? null : _startRecordingSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              padding: const EdgeInsets.symmetric(vertical: 14),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: speakerColor.withValues(alpha: 0.2),
                ),
                child: Icon(
                  Icons.person,
                  color: speakerColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _speakerNames[speakerIndex],
                style: TextStyle(
                  color: speakerColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Language Selection
          DropdownButtonFormField<Language>(
            value: currentLanguage,
            decoration: InputDecoration(
              labelText: 'Select Language',
              labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
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
            style: const TextStyle(color: Colors.white, fontSize: 14),
            items: _supportedLanguages.map((language) {
              return DropdownMenuItem<Language>(
                value: language,
                child:
                    Text(language.name, style: const TextStyle(fontSize: 14)),
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

          const SizedBox(height: 12),

          // Gender Selection
          Row(
            children: [
              Text(
                'Gender:',
                style: TextStyle(
                  color: speakerColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildGenderOption(
                        speakerIndex,
                        'male',
                        'Male',
                        Icons.male,
                        speakerColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildGenderOption(
                        speakerIndex,
                        'female',
                        'Female',
                        Icons.female,
                        speakerColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Earpiece Selection
          Row(
            children: [
              Text(
                'Earpiece:',
                style: TextStyle(
                  color: speakerColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildEarpieceOption(
                        speakerIndex,
                        'left',
                        'Left',
                        Icons.headphones,
                        speakerColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildEarpieceOption(
                        speakerIndex,
                        'right',
                        'Right',
                        Icons.headphones,
                        speakerColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGenderOption(int speakerIndex, String gender, String label,
      IconData icon, Color speakerColor) {
    final isSelected = _speakerGenders[speakerIndex] == gender;

    return GestureDetector(
      onTap: () {
        setState(() {
          _speakerGenders[speakerIndex] = gender;
        });
        debugPrint(
            'GoogleSTTTranslator: Speaker $speakerIndex gender changed to: $gender');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? speakerColor.withValues(alpha: 0.2)
              : const Color(0xFF0A0E21),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? speakerColor : speakerColor.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? speakerColor : Colors.white70,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? speakerColor : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEarpieceOption(int speakerIndex, String earpiece, String label,
      IconData icon, Color speakerColor) {
    final isSelected = _speakerEarpieces[speakerIndex] == earpiece;

    return GestureDetector(
      onTap: () {
        setState(() {
          // Update current speaker's earpiece
          _speakerEarpieces[speakerIndex] = earpiece;

          // Automatically assign opposite earpiece to other speaker
          final otherSpeakerIndex = speakerIndex == 0 ? 1 : 0;
          final oppositeEarpiece = earpiece == 'left' ? 'right' : 'left';
          _speakerEarpieces[otherSpeakerIndex] = oppositeEarpiece;
        });
        debugPrint(
            'GoogleSTTTranslator: Speaker $speakerIndex earpiece changed to: $earpiece');
        debugPrint(
            'GoogleSTTTranslator: Speaker ${speakerIndex == 0 ? 1 : 0} earpiece automatically set to: ${earpiece == 'left' ? 'right' : 'left'}');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? speakerColor.withValues(alpha: 0.2)
              : const Color(0xFF0A0E21),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? speakerColor : speakerColor.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? speakerColor : Colors.white70,
              size: 18,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? speakerColor : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        _buildSpeakerInfoBar(),
        _buildSoundLevelGraph(),
        Expanded(
          child: _isProcessing
              ? _buildProcessingView()
              : (_isRealtimeMode && (_transcriptions.isNotEmpty || _translations.isNotEmpty))
                  ? _buildRealtimeResultsView()
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
                  const SizedBox(height: 4),
                  // Gender and Earpiece Configuration
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _speakerGenders[index] == 'female'
                            ? Icons.female
                            : Icons.male,
                        color: speakerColor.withValues(alpha: 0.7),
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _speakerGenders[index]?.toUpperCase() ?? 'M',
                        style: TextStyle(
                          color: speakerColor.withValues(alpha: 0.7),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.headphones,
                        color: speakerColor.withValues(alpha: 0.7),
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _speakerEarpieces[index]?.toUpperCase() ?? 'L',
                        style: TextStyle(
                          color: speakerColor.withValues(alpha: 0.7),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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

  /// Real-time results view for continuous translation
  Widget _buildRealtimeResultsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          // Real-time mode indicator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.purple.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isRecording ? Icons.mic : Icons.check_circle,
                  color: Colors.purple,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRecording ? 'Real-time Translation Active' : 'Translation Completed',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isRecording
                            ? 'Listening and translating continuously...'
                            : 'Review the translated conversation',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          // Speaker 1 transcription/translation
          _buildRealtimeTranscriptionCard(
            speakerIndex: 0,
          ),
          const SizedBox(height: 20),
          // Speaker 2 transcription/translation
          _buildRealtimeTranscriptionCard(
            speakerIndex: 1,
          ),
        ],
      ),
    );
  }

  /// Build real-time transcription card for a speaker
  Widget _buildRealtimeTranscriptionCard({
    required int speakerIndex,
  }) {
    final speakerColor = _speakerColors[speakerIndex % _speakerColors.length];
    final transcription = _transcriptions[speakerIndex] ?? '';
    final translation = _translations[speakerIndex] ?? '';
    final language = _speakerLanguages[speakerIndex];
    final targetLanguage = _speakerLanguages[speakerIndex == 0 ? 1 : 0];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: speakerColor.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: speakerColor.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Speaker header
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: speakerColor.withValues(alpha: 0.2),
                ),
                child: Icon(
                  Icons.person,
                  color: speakerColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _speakerNames[speakerIndex],
                      style: TextStyle(
                        color: speakerColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${language?.name ?? "Unknown"} → ${targetLanguage?.name ?? "Unknown"}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Transcription (Original)
          _buildTextSection(
            icon: Icons.mic,
            title: 'Original (${language?.name ?? "Unknown"})',
            text: transcription.isEmpty ? 'Waiting for speech...' : transcription,
            color: speakerColor,
            isEmpty: transcription.isEmpty,
          ),
          
          const SizedBox(height: 16),
          
          // Translation
          _buildTextSection(
            icon: Icons.translate,
            title: 'Translation (${targetLanguage?.name ?? "Unknown"})',
            text: translation.isEmpty ? 'Waiting for translation...' : translation,
            color: speakerColor,
            isEmpty: translation.isEmpty,
          ),
        ],
      ),
    );
  }

  /// Build text section for transcription or translation
  Widget _buildTextSection({
    required IconData icon,
    required String title,
    required String text,
    required Color color,
    required bool isEmpty,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: isEmpty ? Colors.white38 : Colors.white,
              fontSize: 15,
              height: 1.5,
              fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ],
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
          const SizedBox(height: 30),
          // Stereo Audio Button
          _buildStereoAudioButton(),
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
          // TTS play button for translated text (show in counter speaker's bubble)
          if (isTranslated &&
              translation != null &&
              translation.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildTtsPlayButton(speakerIndex, speakerColor),
          ],
        ],
      ),
    );
  }

  /// Build TTS play button for translated text
  Widget _buildTtsPlayButton(int speakerIndex, Color speakerColor) {
    // Determine which TTS audio to play based on speaker index
    final isPlayingTts = speakerIndex == 0 ? _isPlayingTts1 : _isPlayingTts2;
    final ttsAudioPath =
        speakerIndex == 0 ? _speaker1TtsAudioPath : _speaker2TtsAudioPath;
    final onTtsTap =
        speakerIndex == 0 ? _playSpeaker1TtsAudio : _playSpeaker2TtsAudio;

    // Get the target language name for the TTS audio
    final targetLanguageName = _getTargetLanguageName(speakerIndex);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: speakerColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: speakerColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.volume_up,
            color: speakerColor,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Listen in $targetLanguageName',
              style: TextStyle(
                color: speakerColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: ttsAudioPath != null && ttsAudioPath.isNotEmpty
                ? onTtsTap
                : null,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: speakerColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: speakerColor.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Icon(
                isPlayingTts ? Icons.stop : Icons.play_arrow,
                color: speakerColor,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build stereo audio button for playing both speakers' translated text
  Widget _buildStereoAudioButton() {
    // Enable play/stop when a cached stereo file exists (single-speaker compatible)
    final hasStereoFile = _cachedStereoAudioPath != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isPlayingStereo
              ? Colors.purple
              : Colors.purple.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: _isPlayingStereo
            ? [
                BoxShadow(
                  color: Colors.purple.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isPlayingStereo
                      ? Colors.purple.withValues(alpha: 0.2)
                      : Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.headphones,
                  color: _isPlayingStereo
                      ? Colors.purple
                      : Colors.purple.withValues(alpha: 0.7),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stereo Audio Playback',
                      style: TextStyle(
                        color: _isPlayingStereo ? Colors.purple : Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Left: Speaker 1\'s translation → Right: Speaker 2\'s translation',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                    if (_isPlayingStereo) ...[
                      const SizedBox(height: 4),
                      Text(
                        '🔊 Playing...',
                        style: TextStyle(
                          color: Colors.purple,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: hasStereoFile ? _playStereoAudio : null,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: hasStereoFile
                        ? (_isPlayingStereo ? Colors.red : Colors.purple)
                        : Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasStereoFile
                          ? (_isPlayingStereo ? Colors.red : Colors.purple)
                          : Colors.grey.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    boxShadow: (hasStereoFile)
                        ? [
                            BoxShadow(
                              color: (_isPlayingStereo
                                      ? Colors.red
                                      : Colors.purple)
                                  .withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    _isPlayingStereo ? Icons.stop : Icons.play_arrow,
                    color: hasStereoFile
                        ? Colors.white
                        : Colors.grey.withValues(alpha: 0.6),
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
          if (!hasStereoFile) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Stereo audio file not available. Please try recording again.',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        child: Column(
          children: [
            // Automatic Mode Toggle
            // if (!_isAutomaticMode) ...[
            //   Container(
            //     margin: const EdgeInsets.only(bottom: 16),
            //     child: ElevatedButton.icon(
            //       onPressed: _isProcessing ? null : _startAutomaticMode,
            //       icon: const Icon(Icons.autorenew),
            //       label: const Text('Start Automatic Mode'),
            //       style: ElevatedButton.styleFrom(
            //         backgroundColor: Colors.green,
            //         foregroundColor: Colors.white,
            //         padding: const EdgeInsets.symmetric(
            //             horizontal: 24, vertical: 12),
            //       ),
            //     ),
            //   ),
            // ],

            // Manual Recording Controls (only show when not in automatic mode)
            if (!_isAutomaticMode) ...[
              Row(
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
                              color: _isRecording
                                  ? Colors.red
                                  : const Color(0xFF00D9FF),
                              boxShadow: _isRecording
                                  ? [
                                      BoxShadow(
                                        color:
                                            Colors.red.withValues(alpha: 0.3),
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
            ],

            // Automatic Mode Controls
            if (_isAutomaticMode) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Stop Automatic Mode Button
                  Container(
                    margin: const EdgeInsets.only(right: 16),
                    child: ElevatedButton.icon(
                      onPressed: _stopAutomaticMode,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Auto'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ),

                  // Status Indicator
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? Colors.green.withValues(alpha: 0.2)
                          : Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isRecording ? Colors.green : Colors.blue,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isRecording ? Icons.mic : Icons.pause,
                          color: _isRecording ? Colors.green : Colors.blue,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isRecording ? 'Listening...' : 'Processing...',
                          style: TextStyle(
                            color: _isRecording ? Colors.green : Colors.blue,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
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

/// Custom painter for drawing sound level graph
class SoundLevelGraphPainter extends CustomPainter {
  final List<double> soundLevelHistory;
  final double currentLevel;
  final bool isRecording;
  final double speechThreshold;

  SoundLevelGraphPainter({
    required this.soundLevelHistory,
    required this.currentLevel,
    required this.isRecording,
    required this.speechThreshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (soundLevelHistory.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw speech threshold line
    final thresholdY = size.height * (1 - speechThreshold);
    paint.color = Colors.orange.withValues(alpha: 0.5);
    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      paint,
    );

    // Draw sound level history
    if (soundLevelHistory.length > 1) {
      final path = Path();
      final stepX = size.width / (soundLevelHistory.length - 1);

      for (int i = 0; i < soundLevelHistory.length; i++) {
        final x = i * stepX;
        final y = size.height * (1 - soundLevelHistory[i]);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      // Color based on recording state and speech detection
      if (isRecording) {
        paint.color =
            currentLevel >= speechThreshold ? Colors.green : Colors.blue;
      } else {
        paint.color = Colors.grey;
      }

      canvas.drawPath(path, paint);
    }

    // Draw current level indicator
    if (isRecording) {
      final currentY = size.height * (1 - currentLevel);
      paint.color =
          currentLevel >= speechThreshold ? Colors.green : Colors.blue;
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size.width - 10, currentY),
        4.0,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Always repaint for real-time updates
  }
}
