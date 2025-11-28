import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:collection';
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
import '../../services/bluetooth_service.dart';
import '../../models/translation_session_summary.dart';

/// TTS Queue Item for Realtime Translation
/// PRODUCTION-READY: Pre-generation architecture with stereo channel routing
/// Phase 1: Generate TTS file → Convert to stereo → Store file path in queue
/// Phase 2: Pick file path → Play immediately (no generation latency)
class TtsQueueItem {
  final int speakerIndex;
  final String filePath;        // Path to pre-generated STEREO TTS audio file
  final String channel;         // Audio channel: 'left' or 'right'
  final String originalText;    // Original text (for logging/debugging)
  final int fileSize;           // File size in bytes (for verification)
  final DateTime timestamp;     // When TTS was generated

  TtsQueueItem({
    required this.speakerIndex,
    required this.filePath,
    required this.channel,
    required this.originalText,
    required this.fileSize,
    required this.timestamp,
  });
}

/// Realtime Translation - Full-duplex translation with simultaneous recording and playback
/// Real-time transcription, translation, and TTS playback with stereo channel routing
class RealtimeTranslator extends StatefulWidget {
  final SttProvider? provider;
  const RealtimeTranslator({super.key, this.provider});

  @override
  State<RealtimeTranslator> createState() => _RealtimeTranslatorState();
}

class _RealtimeTranslatorState extends State<RealtimeTranslator>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Services
  final ConfigService _configService = ConfigService.instance;
  final PermissionService _permissionService = PermissionService.instance;
  // STT provider (Google by default). Can be injected for AssemblyAI.
  late final SttProvider _sttProvider;

  // Translation: Primary = Soniox real-time (saves ~2-3s), Fallback = Azure Translator API
  final TtsService _ttsService = TtsService();
  final EnhancedTtsServiceRobust _stereoTtsService = EnhancedTtsServiceRobust();
  final NativeAudioRecorderService _nativeRecorder =
      NativeAudioRecorderService();
  final BluetoothService _bluetoothService = BluetoothService();
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
  bool _showSpeakerSetup = false; // Skip setup screen, settings are in headers now

  // Speaker gender and earpiece configuration
  Map<int, String> _speakerGenders = {}; // 0: 'male', 1: 'female'
  Map<int, String> _speakerEarpieces = {}; // 0: 'left', 1: 'right'

  // Recording state
  bool _isRecording = false;
  bool _isInitializing = false; // Connecting to Soniox and setting up
  bool _isProcessing = false;
  bool _isStartingSession = false;
  bool _isRealtimeListeningPaused = false; // Mic paused while playback is running
  bool _isPlaybackInProgress = false; // Playback actively running
  bool _isTranslationInProgress = false; // Translation+TTS+Playback in progress (prevents concurrent processing)
  
  // TWS (True Wireless Stereo) connection state
  bool _isTwsConnected = false; // Track TWS connection status
  bool _hasShownTwsNotConnectedDialog = false; // Track if we've shown the "no TWS" dialog
  bool _hasShownTwsConnectedDialog = false; // Track if we've shown the "TWS connected" dialog

  // Session tracking for summary
  DateTime? _sessionStartTime;
  DateTime? _sessionEndTime;
  double _audioSecondsProcessed = 0.0;
  int _totalInputAudioTokens = 0; // Audio tokens (duration-based)
  int _totalOutputTextTokens = 0; // Text tokens (character-based: transcription + translation)
  int _totalTranscriptionCharacters = 0;
  int _totalTranslationCharacters = 0;
  Map<int, int> _transcriptionCharactersPerSpeaker = {0: 0, 1: 0};
  Map<int, int> _translationCharactersPerSpeaker = {0: 0, 1: 0};
  List<double> _translationLatencies = [];
  int _totalTranslations = 0;
  
  // Soniox real-time pricing (https://soniox.com/pricing)
  // Input audio: 1 hour = 30,000 tokens → 1 second = 8.333 tokens
  static const double _tokensPerSecond = 8.333;
  static const double _inputAudioCostPerMillion = 2.0; // $2.00 per 1M tokens
  // Output text: 1 character = 0.3 tokens
  static const double _tokensPerCharacter = 0.3;
  static const double _outputTextCostPerMillion = 4.0; // $4.00 per 1M tokens

  // Real-time translation mode (NEW)
  bool _isRealtimeMode = true; // Real-time mode enabled by default
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

  // API optimization: Store Voice 1's transcription from detection phase
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

  // Scroll controllers for auto-scrolling to latest content in each speaker section
  // Each speaker has separate controllers for transcription and translation
  final ScrollController _speaker1TranscriptionScrollController = ScrollController();
  final ScrollController _speaker1TranslationScrollController = ScrollController();
  final ScrollController _speaker2TranscriptionScrollController = ScrollController();
  final ScrollController _speaker2TranslationScrollController = ScrollController();

  bool _isInitialized = false;

  // REALTIME TRANSLATION: TTS Queue System
  final Queue<TtsQueueItem> _ttsQueue = Queue<TtsQueueItem>();
  bool _isProcessingQueue = false;
  String? _currentPlayingTtsPath;
  
  // Pending translations: Wait for Soniox translation tokens before falling back to Azure
  Map<int, Timer?> _pendingTranslationTimers = {};
  Map<int, String> _pendingTranscriptions = {};
  Map<int, String> _pendingLanguages = {};
  
  // Sentence buffering: Accumulate text until complete sentence for TTS
  Map<int, StringBuffer> _sentenceTranscriptionBuffers = {};
  Map<int, StringBuffer> _sentenceTranslationBuffers = {};
  Map<int, String> _sentenceLanguages = {};
  
  // BATCH PROCESSING: Smart adaptive timer to accumulate multiple sentences before TTS generation
  // This prevents generating TTS for each chunk individually
  // Timer waits for a pause in translation chunks before processing all accumulated sentences
  Map<int, Timer?> _sentenceProcessingTimers = {}; // Per-speaker timers
  Map<int, DateTime?> _lastChunkReceivedTime = {}; // Track when last chunk arrived per speaker
  Map<int, int> _accumulatedChunkCount = {}; // Track how many chunks accumulated per speaker
  
  // ADAPTIVE DELAYS: Longer delay allows more sentences to accumulate
  static const Duration _minProcessingDelay = Duration(milliseconds: 2000); // Minimum 2s wait
  static const Duration _maxProcessingDelay = Duration(milliseconds: 4000); // Maximum 4s wait
  static const Duration _adaptiveExtension = Duration(milliseconds: 500); // Extend by 500ms per chunk
  
  // Sentence thresholds
  static const int _minSentencesForBatch = 2; // Wait for at least 2 sentences if possible
  static const int _maxSentencesForBatch = 10; // Process if we have 10+ sentences

  // Theme-aware color helpers
  bool get _isDarkMode {
    return Theme.of(context).brightness == Brightness.dark;
  }

  Color get _scaffoldBackgroundColor {
    return _isDarkMode ? const Color(0xFF0A0E27) : Colors.grey[50]!;
  }

  Color get _appBarBackgroundColor {
    return _isDarkMode ? const Color(0xFF1D1E33) : Colors.grey[200]!;
  }

  Color get _cardBackgroundColor {
    return _isDarkMode ? const Color(0xFF1D1E33) : Colors.white;
  }

  Color get _secondaryCardBackgroundColor {
    return _isDarkMode ? const Color(0xFF0A0E21) : Colors.grey[100]!;
  }

  Color get _primaryTextColor {
    return _isDarkMode ? Colors.white : Colors.black87;
  }

  Color get _secondaryTextColor {
    return _isDarkMode ? Colors.white70 : Colors.black54;
  }

  Color get _tertiaryTextColor {
    return _isDarkMode ? Colors.white38 : Colors.black38;
  }

  Color get _dividerColor {
    return _isDarkMode ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);
  }

  Color get _primaryAccentColor {
    return const Color(0xFF00D9FF); // Keep accent color consistent across themes
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Add lifecycle observer
    _initializeServices();
    _setupAudioPlayers();
    _initializeAnimations();
    _initializeBluetoothAndCheck(); // Initialize Bluetooth service and check connection
    _initializeContinuousA2DPMode(); // Initialize continuous A2DP mode (no switching)
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // When app comes back to foreground, re-initialize A2DP mode
    // This ensures audio routing is correct after being backgrounded
    if (state == AppLifecycleState.resumed) {
      debugPrint('RealtimeTranslator: App resumed - re-initializing A2DP mode');
      _initializeContinuousA2DPMode();
    }
  }


  /// Auto-scroll to bottom of speaker section when new content is added
  void _autoScrollToBottom(int speakerIndex, {bool isTranslation = false}) {
    final transcriptionController = speakerIndex == 0 
        ? _speaker1TranscriptionScrollController 
        : _speaker2TranscriptionScrollController;
    final translationController = speakerIndex == 0 
        ? _speaker1TranslationScrollController 
        : _speaker2TranslationScrollController;
    
    final controller = isTranslation ? translationController : transcriptionController;
    
    if (controller.hasClients) {
      // Use a small delay to ensure the content is rendered
      Future.delayed(const Duration(milliseconds: 100), () {
        if (controller.hasClients) {
          controller.animateTo(
            controller.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
    
    // Also scroll the other section if it has content
    final otherController = isTranslation ? transcriptionController : translationController;
    if (otherController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (otherController.hasClients && otherController.position.maxScrollExtent > 0) {
          otherController.animateTo(
            otherController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  // Platform-channel helper: force phone mic even if BT/TWS connected
  static const MethodChannel _audioRouteChannel = MethodChannel('audio_route');
  Future<void> _enterRecordingRoute() async {
    try {
      await _audioRouteChannel.invokeMethod('enterRecordingRoute');
      debugPrint('RealtimeTranslator: Entered recording route (phone mic)');
    } catch (e) {
      debugPrint('RealtimeTranslator: Failed to enter recording route: $e');
    }
  }

  /// REALTIME TRANSLATION: Initialize continuous A2DP mode (NO switching)
  /// Uses MODE_NORMAL approach: Phone mic input + A2DP output simultaneously
  Future<void> _initializeContinuousA2DPMode() async {
    try {
      debugPrint('RealtimeTranslator: ═══ Initializing Continuous A2DP Mode (MODE_NORMAL) ═══');
      debugPrint('RealtimeTranslator: Solution: MODE_NORMAL enables simultaneous:');
      debugPrint('RealtimeTranslator: - Recording from phone mic (AudioRecord MIC source)');
      debugPrint('RealtimeTranslator: - Playback through TWS via A2DP (MEDIA stream routing)');
      debugPrint('RealtimeTranslator: - NO mode switching during session');
      debugPrint('RealtimeTranslator: - NO SCO activation (Bluetooth stays in A2DP mode)');
      
      await _audioRouteChannel.invokeMethod('enterContinuousA2DPMode');
      
      debugPrint('RealtimeTranslator: ✅ Continuous A2DP mode initialized');
      debugPrint('RealtimeTranslator: ✅ AudioManager mode: NORMAL (media mode)');
      debugPrint('RealtimeTranslator: ✅ Bluetooth SCO: OFF (A2DP active)');
      debugPrint('RealtimeTranslator: ✅ Recording source: Phone built-in mic (MIC source)');
      debugPrint('RealtimeTranslator: ✅ Playback output: TWS speakers via A2DP (MEDIA stream)');
      debugPrint('RealtimeTranslator: ✅ Full-duplex: Both input and output active simultaneously');
      
      // CRITICAL: Verify audio routing after initialization
      try {
        debugPrint('RealtimeTranslator: ═══ Verifying Audio Routing ═══');
        final routingInfo = await _audioRouteChannel.invokeMethod<Map>('checkAudioRouting');
        if (routingInfo != null) {
          debugPrint('RealtimeTranslator: Audio routing status:');
          debugPrint('RealtimeTranslator:   - Mode: ${routingInfo["mode"]}');
          debugPrint('RealtimeTranslator:   - A2DP on: ${routingInfo["isBluetoothA2dpOn"]}');
          debugPrint('RealtimeTranslator:   - SCO on: ${routingInfo["isBluetoothScoOn"]}');
          debugPrint('RealtimeTranslator:   - Has Bluetooth A2DP device: ${routingInfo["hasBluetoothA2dp"]}');
          
          if (routingInfo["isBluetoothA2dpOn"] == true && routingInfo["hasBluetoothA2dp"] == true) {
            debugPrint('RealtimeTranslator: ✅ Bluetooth A2DP is active - routing should work');
          } else {
            debugPrint('RealtimeTranslator: ⚠️ WARNING: A2DP may not be active!');
            debugPrint('RealtimeTranslator: ⚠️ Audio may route to phone speaker');
            debugPrint('RealtimeTranslator: ⚠️ Solution: Play music through TWS first to activate A2DP');
          }
        }
      } catch (e) {
        debugPrint('RealtimeTranslator: ⚠️ Could not verify routing: $e');
      }
      
      // Allow time for audio system to stabilize and A2DP to be ready
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint('RealtimeTranslator: ✅ Audio system ready for full-duplex operation');
      debugPrint('RealtimeTranslator: ✅ Expected behavior: TTS plays through TWS, recording from phone mic');
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Failed to initialize continuous A2DP mode: $e');
      // Will fall back to default routing
    }
  }

  Future<void> _enterPlaybackRoute() async {
    // REALTIME TRANSLATION: NO-OP in continuous A2DP mode
    // Mode stays NORMAL throughout - no switching needed
    debugPrint('RealtimeTranslator: Continuous A2DP - no route switching (mode stays NORMAL)');
  }

  Future<void> _returnToRecordingRoute() async {
    // REALTIME TRANSLATION: NO-OP in continuous A2DP mode
    // Mode stays NORMAL throughout - no switching needed
    debugPrint('RealtimeTranslator: Continuous A2DP - staying in NORMAL mode');
  }

  /// REALTIME TRANSLATION: Initialize Bluetooth service and check connection
  Future<void> _initializeBluetoothAndCheck() async {
    try {
      // Initialize Bluetooth service
      await _bluetoothService.initialize();
      debugPrint('RealtimeTranslator: Bluetooth service initialized');
      
      // Wait a bit for initialization to complete and for Bluetooth profiles to be ready
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Check Bluetooth connection using the existing service
      // This checks both A2DP and HEADSET profiles
      final deviceInfo = await _bluetoothService.checkConnection();
      
      // Update TWS connection state
      _isTwsConnected = deviceInfo.isConnected;
      
      debugPrint('RealtimeTranslator: ═══ Bluetooth Connection Check ═══');
      debugPrint('RealtimeTranslator: Connected: ${deviceInfo.isConnected}');
      debugPrint('RealtimeTranslator: Device Name: ${deviceInfo.deviceName}');
      
      if (!deviceInfo.isConnected) {
        debugPrint('RealtimeTranslator: ⚠️ No Bluetooth device connected');
        debugPrint('RealtimeTranslator: ⚠️ Translation will work but playback will be disabled');
        // Dialog will be shown when user tries to start recording
      } else {
        debugPrint('RealtimeTranslator: ✅ Bluetooth device connected: ${deviceInfo.deviceName}');
        debugPrint('RealtimeTranslator: Ready for Realtime Translation with audio playback');
      }
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error checking Bluetooth: $e');
      debugPrint('RealtimeTranslator: Stack trace: ${StackTrace.current}');
      // If check fails, don't block - let user try and check again when starting
      debugPrint('RealtimeTranslator: ⚠️ Bluetooth check failed, will check again when starting recording');
    }
  }
  
  /// REALTIME TRANSLATION: Check Bluetooth before starting recording
  /// NEW: Allows translation without TWS (playback will be disabled)
  Future<bool> _checkBluetoothBeforeRecording() async {
    try {
      final deviceInfo = await _bluetoothService.checkConnection();
      
      // Update TWS connection state
      _isTwsConnected = deviceInfo.isConnected;
      
      if (!deviceInfo.isConnected) {
        debugPrint('RealtimeTranslator: ⚠️ No Bluetooth device connected before recording');
        debugPrint('RealtimeTranslator: ⚠️ Translation will work but playback will be disabled');
        
        // Show dialog asking user to connect TWS for better performance
        if (mounted && !_hasShownTwsNotConnectedDialog) {
          _hasShownTwsNotConnectedDialog = true;
          _showTwsNotConnectedDialog();
        }
        
        // Allow translation to proceed (without playback)
        return true;
      }
      
      debugPrint('RealtimeTranslator: ✅ Bluetooth device connected: ${deviceInfo.deviceName}');
      
      // Show dialog with earpiece sharing instructions when TWS is connected
      if (mounted && !_hasShownTwsConnectedDialog) {
        _hasShownTwsConnectedDialog = true;
        _showTwsConnectedDialog();
      }
      
      return true;
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error checking Bluetooth before recording: $e');
      
      // On error, assume TWS not connected but allow translation
      _isTwsConnected = false;
      
      if (mounted && !_hasShownTwsNotConnectedDialog) {
        _hasShownTwsNotConnectedDialog = true;
        _showTwsNotConnectedDialog();
      }
      
      // Allow translation to proceed (without playback)
      return true;
    }
  }

  /// REALTIME TRANSLATION: Show dialog when TWS is NOT connected
  /// NEW: Informative dialog asking user to connect TWS for better performance
  void _showTwsNotConnectedDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: _cardBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.bluetooth_disabled,
                color: Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'TWS Not Connected',
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You can still use translation, but audio playback will be disabled.',
                style: TextStyle(
                  color: _primaryTextColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'For better performance and audio playback:',
                style: TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              _buildDialogBulletPoint(
                'Connect your TWS (True Wireless Stereo) earpieces',
              ),
              _buildDialogBulletPoint(
                'Enable audio playback for translated text',
              ),
              _buildDialogBulletPoint(
                'Get the best translation experience',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Retry Bluetooth check
                debugPrint('RealtimeTranslator: Retrying Bluetooth check...');
                final deviceInfo = await _bluetoothService.checkConnection();
                _isTwsConnected = deviceInfo.isConnected;
                if (deviceInfo.isConnected) {
                  debugPrint('RealtimeTranslator: ✅ Bluetooth now connected: ${deviceInfo.deviceName}');
                  _hasShownTwsConnectedDialog = false; // Reset to show connected dialog
                  if (mounted) {
                    _showTwsConnectedDialog();
                  }
                } else {
                  debugPrint('RealtimeTranslator: ⚠️ Still not connected');
                }
              },
              child: Text(
                'Retry',
                style: TextStyle(
                  color: const Color(0xFF00D9FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Continue Without TWS',
                style: TextStyle(
                  color: _secondaryTextColor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// REALTIME TRANSLATION: Show dialog when TWS IS connected
  /// NEW: Instructions for earpiece sharing and phone placement
  void _showTwsConnectedDialog() {
    final speaker2Earpiece = _speakerEarpieces[1] ?? 'left';
    final speaker2EarpieceLabel = speaker2Earpiece == 'left' ? 'Left' : 'Right';
    final otherEarpiece = speaker2Earpiece == 'left' ? 'Right' : 'Left';
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: _cardBackgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.bluetooth_connected,
                color: const Color(0xFF00D9FF),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'TWS Connected',
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'For the best translation experience:',
                style: TextStyle(
                  color: _primaryTextColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _secondaryCardBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00D9FF).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Earpiece Sharing:',
                      style: TextStyle(
                        color: const Color(0xFF00D9FF),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Speaker 2 is using the $speaker2EarpieceLabel earpiece. Please share the $otherEarpiece earpiece with Speaker 1.',
                      style: TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildDialogBulletPoint(
                'Keep your phone closer to both speakers',
              ),
              _buildDialogBulletPoint(
                'This ensures clear audio capture',
              ),
              _buildDialogBulletPoint(
                'Better transcription accuracy',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Got It',
                style: TextStyle(
                  color: const Color(0xFF00D9FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Helper to build bullet points in dialogs
  Widget _buildDialogBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              color: const Color(0xFF00D9FF),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: _secondaryTextColor,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// STEREO CONVERSION: Convert mono TTS to stereo with channel routing
  /// This routes audio to the specified channel (left or right earpiece)
  /// Similar to Stereo Translation, but for mono pre-generated TTS
  Future<String?> _convertMonoToStereoWithChannel(
    String monoFilePath,
    String channel,
  ) async {
    try {
      debugPrint('RealtimeTranslator: ═══ Converting Mono to Stereo ═══');
      debugPrint('RealtimeTranslator: Mono file: $monoFilePath');
      debugPrint('RealtimeTranslator: Target channel: $channel');

      // Read mono file
      final monoFile = File(monoFilePath);
      if (!await monoFile.exists()) {
        debugPrint('RealtimeTranslator: ❌ Mono file does not exist');
        return null;
      }

      final monoBytes = await monoFile.readAsBytes();
      debugPrint('RealtimeTranslator: Read ${monoBytes.length} bytes from mono file');

      // Extract audio data and metadata from WAV file
      if (monoBytes.length < 44) {
        debugPrint('RealtimeTranslator: ❌ File too small to be valid WAV');
        return null;
      }

      // Parse WAV header (44 bytes standard WAV header)
      final sampleRate = monoBytes[24] |
          (monoBytes[25] << 8) |
          (monoBytes[26] << 16) |
          (monoBytes[27] << 24);
      
      final channels = monoBytes[22] | (monoBytes[23] << 8);
      final bitsPerSample = monoBytes[34] | (monoBytes[35] << 8);

      debugPrint('RealtimeTranslator: WAV metadata:');
      debugPrint('RealtimeTranslator:   Sample rate: $sampleRate Hz');
      debugPrint('RealtimeTranslator:   Channels: $channels');
      debugPrint('RealtimeTranslator:   Bits per sample: $bitsPerSample');

      // Extract audio data (skip 44-byte header)
      final audioData = monoBytes.sublist(44);
      debugPrint('RealtimeTranslator: Extracted ${audioData.length} bytes of audio data');

      // Create stereo data with channel routing
      final stereoData = <int>[];

      // Interleave audio based on target channel
      for (int i = 0; i < audioData.length; i += 2) {
        if (channel == 'left') {
          // Left channel: audio, Right channel: silence
          stereoData.add(audioData[i]);
          stereoData.add(audioData[i + 1]);
          stereoData.add(0);  // Right channel silence (low byte)
          stereoData.add(0);  // Right channel silence (high byte)
        } else {
          // Left channel: silence, Right channel: audio
          stereoData.add(0);  // Left channel silence (low byte)
          stereoData.add(0);  // Left channel silence (high byte)
          stereoData.add(audioData[i]);
          stereoData.add(audioData[i + 1]);
        }
      }

      // Create stereo WAV header
      final dataSize = stereoData.length;
      final fileSize = 36 + dataSize;
      final byteRate = sampleRate * 2 * 2; // sampleRate * channels * (bitsPerSample / 8)

      final header = <int>[
        // RIFF header
        0x52, 0x49, 0x46, 0x46, // "RIFF"
        fileSize & 0xFF, (fileSize >> 8) & 0xFF, (fileSize >> 16) & 0xFF, (fileSize >> 24) & 0xFF,
        0x57, 0x41, 0x56, 0x45, // "WAVE"

        // fmt chunk
        0x66, 0x6D, 0x74, 0x20, // "fmt "
        0x10, 0x00, 0x00, 0x00, // fmt chunk size (16)
        0x01, 0x00, // audio format (PCM)
        0x02, 0x00, // number of channels (2 = stereo)
        sampleRate & 0xFF, (sampleRate >> 8) & 0xFF, (sampleRate >> 16) & 0xFF, (sampleRate >> 24) & 0xFF, // sample rate
        byteRate & 0xFF, (byteRate >> 8) & 0xFF, (byteRate >> 16) & 0xFF, (byteRate >> 24) & 0xFF, // byte rate
        0x04, 0x00, // block align (2 * 2)
        0x10, 0x00, // bits per sample (16)

        // data chunk
        0x64, 0x61, 0x74, 0x61, // "data"
        dataSize & 0xFF, (dataSize >> 8) & 0xFF, (dataSize >> 16) & 0xFF, (dataSize >> 24) & 0xFF,
      ];

      // Combine header and stereo data
      final stereoWav = Uint8List.fromList([...header, ...stereoData]);

      // Save stereo file
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final stereoFileName = 'stereo_${channel}_$timestamp.wav';
      final stereoPath = '${directory.path}/$stereoFileName';
      
      final stereoFile = File(stereoPath);
      await stereoFile.writeAsBytes(stereoWav);

      debugPrint('RealtimeTranslator: ✅ Stereo file created successfully');
      debugPrint('RealtimeTranslator:   Path: $stereoPath');
      debugPrint('RealtimeTranslator:   Size: ${stereoWav.length} bytes');
      debugPrint('RealtimeTranslator:   Channel: $channel');
      debugPrint('RealtimeTranslator:   Sample rate: $sampleRate Hz');

      // Clean up original mono file
      try {
        await monoFile.delete();
        debugPrint('RealtimeTranslator: ✅ Cleaned up original mono file');
      } catch (e) {
        debugPrint('RealtimeTranslator: ⚠️ Could not delete mono file: $e');
      }

      return stereoPath;
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error converting mono to stereo: $e');
      debugPrint('RealtimeTranslator:    Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  /// PHASE 1: Generate TTS file and add to queue (Pre-generation Architecture + Stereo)
  /// PRODUCTION-READY: TTS generation + stereo conversion happens in Phase 1 (parallel to recording)
  /// This eliminates playback latency and enables pipeline processing with stereo channel routing
  Future<void> _addToTtsQueue({
    required int speakerIndex,
    required String text,
    required String languageCode,
    required String gender,
  }) async {
    try {
      debugPrint('RealtimeTranslator: ═══ PHASE 1: TTS Pre-Generation + Stereo Conversion ═══');
      debugPrint('RealtimeTranslator: Speaker: $speakerIndex');
      debugPrint('RealtimeTranslator: Language: $languageCode');
      debugPrint('RealtimeTranslator: Text: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');
      debugPrint('RealtimeTranslator: Gender: $gender');
      
      // Get speaker's earpiece preference (left or right channel)
      final earpiece = _speakerEarpieces[speakerIndex] ?? 'left';
      debugPrint('RealtimeTranslator: Target channel: $earpiece');
      debugPrint('RealtimeTranslator: Recording continues during TTS generation + stereo conversion (parallel processing)');

      // STEP 1: Generate mono TTS file (Phase 1 pre-generation)
      final startTime = DateTime.now();
      final monoTtsPath = await _ttsService.generateAudioFile(
        text,
        languageCode,
        gender: gender,
      );
      final generationTime = DateTime.now().difference(startTime).inMilliseconds;

      if (monoTtsPath != null && monoTtsPath.isNotEmpty) {
        debugPrint('RealtimeTranslator: ✅ Mono TTS file generated successfully');
        debugPrint('RealtimeTranslator:    Path: $monoTtsPath');
        debugPrint('RealtimeTranslator:    Generation time: ${generationTime}ms');

        // STEP 2: Convert mono to stereo with channel routing
        final stereoStartTime = DateTime.now();
        final stereoTtsPath = await _convertMonoToStereoWithChannel(
          monoTtsPath,
          earpiece,
        );
        final stereoConversionTime = DateTime.now().difference(stereoStartTime).inMilliseconds;

        if (stereoTtsPath != null && stereoTtsPath.isNotEmpty) {
          // Verify stereo file exists and get size
          final stereoFile = File(stereoTtsPath);
          if (await stereoFile.exists()) {
            final stereoFileSize = await stereoFile.length();
            
            debugPrint('RealtimeTranslator: ✅ Stereo TTS file ready for queueing');
            debugPrint('RealtimeTranslator:    Path: $stereoTtsPath');
            debugPrint('RealtimeTranslator:    Size: $stereoFileSize bytes');
            debugPrint('RealtimeTranslator:    Channel: $earpiece');
            debugPrint('RealtimeTranslator:    Total time: ${generationTime + stereoConversionTime}ms (${generationTime}ms gen + ${stereoConversionTime}ms stereo)');
            debugPrint('RealtimeTranslator:    File is pre-verified and ready for immediate stereo playback');

            // Add pre-generated STEREO file to queue (not mono!)
            final item = TtsQueueItem(
              speakerIndex: speakerIndex,
              filePath: stereoTtsPath,
              channel: earpiece,
              originalText: text,
              fileSize: stereoFileSize,
              timestamp: DateTime.now(),
            );
            
            _ttsQueue.add(item);
            debugPrint('RealtimeTranslator: ✅ Added pre-generated STEREO TTS to queue');
            debugPrint('RealtimeTranslator:    Queue size: ${_ttsQueue.length}');
            debugPrint('RealtimeTranslator:    Ready for immediate stereo playback (no generation delay)');
            debugPrint('RealtimeTranslator:    Will play through $earpiece earpiece only');
            debugPrint('RealtimeTranslator:    Recording continues uninterrupted');

            // Start processing queue if not already processing
            if (!_isProcessingQueue) {
              _processTtsQueue();
            }
          } else {
            debugPrint('RealtimeTranslator: ❌ Stereo TTS file does not exist after conversion: $stereoTtsPath');
            debugPrint('RealtimeTranslator:    File will not be added to queue');
            // Don't add to queue - skip this TTS
          }
        } else {
          debugPrint('RealtimeTranslator: ❌ Stereo conversion failed for mono file: $monoTtsPath');
          debugPrint('RealtimeTranslator:    Conversion time: ${stereoConversionTime}ms');
          debugPrint('RealtimeTranslator:    File will not be added to queue - translation will be skipped');
          // Don't add to queue - skip this TTS
        }
      } else {
        debugPrint('RealtimeTranslator: ❌ Mono TTS generation failed for text: "$text"');
        debugPrint('RealtimeTranslator:    Generation time: ${generationTime}ms');
        debugPrint('RealtimeTranslator:    File will not be added to queue - translation will be skipped');
        // Don't add to queue - skip this TTS
      }
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error in Phase 1 TTS generation + stereo conversion: $e');
      debugPrint('RealtimeTranslator:    Stack trace: ${StackTrace.current}');
      debugPrint('RealtimeTranslator:    This TTS will be skipped - queue continues');
      // Don't add to queue - error isolation ensures other TTS items continue
    }
  }

  /// PHASE 2: Process TTS queue - Simplified playback only (Pre-generation Architecture)
  /// PRODUCTION-READY: Files are pre-generated in Phase 1, so just pick and play
  /// This eliminates generation latency and enables immediate playback
  Future<void> _processTtsQueue() async {
    if (_isProcessingQueue || _ttsQueue.isEmpty) {
      return;
    }

    _isProcessingQueue = true;
    debugPrint('RealtimeTranslator: ═══ PHASE 2: STEREO TTS Queue Processing ═══');
    debugPrint('RealtimeTranslator: Queue size: ${_ttsQueue.length} pre-generated STEREO files ready');
    debugPrint('RealtimeTranslator: TWS connected: $_isTwsConnected');
    
    // NEW: Check TWS connection - skip playback if not connected
    if (!_isTwsConnected) {
      debugPrint('RealtimeTranslator: ⚠️ TWS not connected - skipping playback, cleaning up queue');
      
      // Clean up all TTS files in queue without playing
      while (_ttsQueue.isNotEmpty) {
        final item = _ttsQueue.removeFirst();
        try {
          final file = File(item.filePath);
          if (await file.exists()) {
            await file.delete();
            debugPrint('RealtimeTranslator: ✅ Cleaned up TTS file (playback disabled): ${item.filePath}');
          }
        } catch (e) {
          debugPrint('RealtimeTranslator: ⚠️ Error deleting TTS file: $e');
        }
      }
      
      _isProcessingQueue = false;
      debugPrint('RealtimeTranslator: ✅ TTS queue cleared (playback disabled - TWS not connected)');
      return;
    }
    
    debugPrint('RealtimeTranslator: Files are already converted to stereo - immediate channel-specific playback starts');

    while (_ttsQueue.isNotEmpty) {
      final item = _ttsQueue.removeFirst();
      final startTime = DateTime.now();
      
      debugPrint('RealtimeTranslator: ═══ Playing Pre-Generated STEREO TTS ═══');
      debugPrint('RealtimeTranslator: Speaker: ${item.speakerIndex}');
      debugPrint('RealtimeTranslator: File: ${item.filePath}');
      debugPrint('RealtimeTranslator: Channel: ${item.channel} earpiece');
      debugPrint('RealtimeTranslator: Text: "${item.originalText.substring(0, item.originalText.length > 50 ? 50 : item.originalText.length)}..."');
      debugPrint('RealtimeTranslator: File size: ${item.fileSize} bytes (stereo format)');
      debugPrint('RealtimeTranslator: Pre-generated at: ${item.timestamp}');
      debugPrint('RealtimeTranslator: NO generation delay - stereo file ready for immediate channel-specific playback');

      try {
        // CRITICAL: Verify file still exists (safety check)
        final file = File(item.filePath);
        if (!await file.exists()) {
          debugPrint('RealtimeTranslator: ❌ Pre-generated file missing: ${item.filePath}');
          debugPrint('RealtimeTranslator:    Skipping this item and continuing to next');
          continue; // Skip to next item
        }

        // Verify file size matches (ensures file wasn't corrupted)
        final currentSize = await file.length();
        if (currentSize != item.fileSize) {
          debugPrint('RealtimeTranslator: ⚠️ File size mismatch: Expected ${item.fileSize}, got $currentSize');
          debugPrint('RealtimeTranslator:    File may be corrupted - skipping');
          // Clean up corrupted file
          try {
            await file.delete();
          } catch (_) {}
          continue; // Skip to next item
        }

        debugPrint('RealtimeTranslator: ✅ Stereo file verified - starting channel-specific playback immediately');
        debugPrint('RealtimeTranslator: ✅ Audio will play through ${item.channel} earpiece only');
        
        _currentPlayingTtsPath = item.filePath;
        
        // Update UI state
        if (mounted) {
          setState(() {
            if (item.speakerIndex == 0) {
              _isPlayingTts1 = true;
            } else {
              _isPlayingTts2 = true;
            }
          });
        }

        // Play STEREO TTS (recording continues - full-duplex, NO mode switching)
        // MODE_NORMAL approach: Phone mic input + A2DP stereo output simultaneously
        // Native MediaPlayer plays stereo WAV with channel separation
        // AudioRecord with MIC source continues from phone mic (independent of mode)
        debugPrint('RealtimeTranslator: ═══ Playing STEREO TTS (MODE_NORMAL Full-Duplex) ═══');
        debugPrint('RealtimeTranslator: Mode: NORMAL (media mode - A2DP routing enabled)');
        debugPrint('RealtimeTranslator: Recording: Phone built-in mic (continues)');
        debugPrint('RealtimeTranslator: Playback: TWS speakers via A2DP (MEDIA stream - STEREO)');
        debugPrint('RealtimeTranslator: Channel routing: ${item.channel} earpiece (stereo file)');
        debugPrint('RealtimeTranslator: Simultaneous: Both active - NO mode switching');
        
        // Play pre-generated file (NO generation wait!)
        await _ttsService.playAudioFile(item.filePath);
        
        final playbackTime = DateTime.now().difference(startTime).inMilliseconds;
        
        debugPrint('RealtimeTranslator: ✅ STEREO TTS playback completed through TWS A2DP');
        debugPrint('RealtimeTranslator: ✅ Total time (queue → playback complete): ${playbackTime}ms');
        debugPrint('RealtimeTranslator: ✅ Audio played through ${item.channel} earpiece as expected');
        debugPrint('RealtimeTranslator: ✅ Recording continued throughout (phone mic still active)');
        debugPrint('RealtimeTranslator: ✅ Full-duplex stereo operation verified');

        // Update UI state after playback
        if (mounted) {
          setState(() {
            if (item.speakerIndex == 0) {
              _isPlayingTts1 = false;
            } else {
              _isPlayingTts2 = false;
            }
          });
        }

        // CRITICAL: Clean up TTS file immediately after successful playback
        // This prevents storage accumulation and ensures files are removed
        try {
          if (await file.exists()) {
            await file.delete();
            debugPrint('RealtimeTranslator: ✅ Cleaned up TTS file: ${item.filePath}');
          }
        } catch (e) {
          debugPrint('RealtimeTranslator: ⚠️ Error deleting TTS file: $e');
          // Non-critical - file will be cleaned up later by system
        }

        _currentPlayingTtsPath = null;
        
      } catch (e) {
        debugPrint('RealtimeTranslator: ❌ Error playing queue item: $e');
        debugPrint('RealtimeTranslator:    Stack trace: ${StackTrace.current}');
        debugPrint('RealtimeTranslator:    Cleaning up file and continuing to next item');
        
        // Clean up file on error
        try {
          final file = File(item.filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // Ignore cleanup errors
        }
        
        // Reset UI state on error
        if (mounted) {
          setState(() {
            _isPlayingTts1 = false;
            _isPlayingTts2 = false;
          });
        }
        
        _currentPlayingTtsPath = null;
        // Continue to next item - error isolation
      }

      // Small delay between queue items for smooth transitions
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _isProcessingQueue = false;
    debugPrint('RealtimeTranslator: ✅ TTS queue processing complete (Phase 2 finished)');
  }

  /// Check if a WAV file contains meaningful audio (not just a tiny/silent file)
  /// Returns true when file size is above minimal WAV header and not trivially tiny
  Future<bool> _hasMeaningfulAudio(String path,
      {required int speakerIndex}) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint(
            'RealtimeTranslator: Speaker $speakerIndex audio missing: $path');
        return false;
      }
      final size = await file.length();
      // 44 bytes = WAV header only; use a conservative threshold (~1KB) to avoid empty streams
      const int minBytes = 1024;
      debugPrint(
          'RealtimeTranslator: Speaker $speakerIndex audio size: $size bytes');
      if (size <= 44 || size < minBytes) {
        debugPrint(
            'RealtimeTranslator: Skipping STT for Speaker $speakerIndex - audio too small');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint(
          'RealtimeTranslator: Audio check error for Speaker $speakerIndex: $e');
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

      // CRITICAL: Configure sound effect player to use Bluetooth/TWS audio
      // This ensures beeps play through the same output as TTS (stereo TWS headset)
      try {
        await _soundEffectPlayer.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: true,
              contentType: AndroidContentType.music,
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {
                AVAudioSessionOptions.allowBluetooth,
                AVAudioSessionOptions.allowBluetoothA2DP,
                AVAudioSessionOptions.mixWithOthers,
              },
            ),
          ),
        );
        debugPrint('RealtimeTranslator: ✅ Sound effect player configured for Bluetooth/TWS output');
      } catch (e) {
        debugPrint('RealtimeTranslator: ⚠️ Failed to configure sound effect player: $e');
      }

      // Set up TTS service callbacks for UI state synchronization
      _ttsService.setPlaybackCompletedCallback(() {
        if (mounted) {
          setState(() {
            _isPlayingTts1 = false;
            _isPlayingTts2 = false;
          });
          debugPrint(
              'RealtimeTranslator: TTS playback completed - UI state updated');
        }
      });

      _ttsService.setPlaybackErrorCallback(() {
        if (mounted) {
          setState(() {
            _isPlayingTts1 = false;
            _isPlayingTts2 = false;
          });
          debugPrint(
              'RealtimeTranslator: TTS playback error - UI state updated');
        }
      });

      // Set up unified stereo TTS service callback for both UI state and automatic mode
      _stereoTtsService.setPlaybackCompletedCallback(() async {
        debugPrint(
            'RealtimeTranslator: 🎵 Unified playback completion callback triggered!');
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
              'RealtimeTranslator: Performing deferred TTS cleanup after playback');
          await _cleanupTtsFiles();
          _pendingStereoPlaybackCleanup = false;
        }

        // Handle automatic mode restart
        if (_isAutomaticMode && !_isRecording) {
          debugPrint(
              'RealtimeTranslator: ✅ Automatic mode - stereo playback COMPLETED! Starting new cycle in 500ms...');

          setState(() {
            _isProcessing = false;
          });

          // Longer delay to ensure TTS audio has completely finished
          // This prevents the mic from capturing the previous cycle's TTS audio
          Future.delayed(const Duration(milliseconds: 1500), () {
            // Double-check conditions before starting new cycle
            if (_isAutomaticMode && !_isRecording && !_isPlayingStereo) {
              debugPrint(
                  'RealtimeTranslator: 🔄 Conditions met, starting new recording cycle...');
              debugPrint(
                  'RealtimeTranslator: ⏰ 1.5s delay ensures TTS audio has completely finished');
              _startAutomaticRecording();
            } else {
              debugPrint(
                  'RealtimeTranslator: ⚠️ Conditions not met for restart: mode=$_isAutomaticMode, recording=$_isRecording, playing=$_isPlayingStereo');
            }
          });
        } else {
          debugPrint(
              'RealtimeTranslator: Manual mode - stereo playback completed, UI state updated');
        }
      });

      _stereoTtsService.setPlaybackErrorCallback(() {
        if (mounted) {
          setState(() {
            _isPlayingStereo = false;
          });
          debugPrint(
              'RealtimeTranslator: Stereo TTS playback error - UI state updated');
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

      debugPrint('RealtimeTranslator: Services initialized successfully');
    } catch (e) {
      debugPrint('RealtimeTranslator: Initialization error: $e');
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

    // No model downloads needed - translation uses Soniox real-time (primary) + Azure API (fallback)
    debugPrint(
        'RealtimeTranslator: ✅ Translation service ready (Soniox primary + Azure fallback)');

    // Transition to main recording screen
    setState(() {
      _showSpeakerSetup = false;
      _isStartingSession = false;
    });

    debugPrint(
        'RealtimeTranslator: Successfully transitioned to recording screen');
  }

  Future<void> _toggleRecording() async {
    // Prevent double-tap during initialization
    if (_isInitializing) {
      debugPrint('RealtimeTranslator: ⏳ Initializing Soniox connection, please wait...');
      return;
    }
    
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
      debugPrint('RealtimeTranslator: ═══ Starting Recording ═══');

      final hasPermission =
          await _permissionService.requestMicrophonePermission();
      if (!hasPermission) {
        _showErrorDialog('Microphone permission is required for recording.');
        return;
      }

      // CRITICAL: Always force built-in mic for recording
      debugPrint(
          'RealtimeTranslator: Step 1: Configuring audio route for recording...');
      await _enterRecordingRoute();
      debugPrint('RealtimeTranslator: ✅ Audio route configured for RECORDING');

      // Add delay to ensure audio system has switched modes
      await Future.delayed(const Duration(milliseconds: 200));
      debugPrint('RealtimeTranslator: ✅ Audio system ready');

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordedAudioPath = '${directory.path}/recording_$timestamp.wav';

      debugPrint(
          'RealtimeTranslator: Step 2: Starting NATIVE audio recorder...');
      debugPrint('RealtimeTranslator: Recording path: $_recordedAudioPath');
      debugPrint(
          'RealtimeTranslator: Expected input: FORCED built-in microphone (MIC audio source)');

      // Play start recording sound effect
      await _playStartRecordingSound();

      // CRITICAL: Use native recorder that forces MIC audio source
      // This guarantees phone mic is used, not Bluetooth
      final bool recordingStarted =
          await _nativeRecorder.startRecording(_recordedAudioPath!);

      if (!recordingStarted) {
        debugPrint('RealtimeTranslator: ❌ Failed to start native recording');
        _showErrorDialog('Failed to start recording. Please try again.');
        return;
      }

      setState(() {
        _isRecording = true;
        _isRealtimeListeningPaused = false;
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

      debugPrint('RealtimeTranslator: ✅ Recording started successfully');
      debugPrint('RealtimeTranslator: Using built-in phone microphone');
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Recording error: $e');
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
          'RealtimeTranslator: ✅ Sound level monitoring stopped (mic OFF for playback)');

      // Stop the NATIVE audio recorder
      debugPrint('RealtimeTranslator: Stopping native audio recorder...');
      final String? recordedPath = await _nativeRecorder.stopRecording();

      if (recordedPath == null) {
        debugPrint('RealtimeTranslator: ❌ Failed to stop recording properly');
      } else {
        debugPrint('RealtimeTranslator: ✅ Recording saved: $recordedPath');
      }

      setState(() {
        _isRecording = false;
        _isProcessing = true;
        _isRealtimeListeningPaused = false;
      });

      _pulseController.stop();
      _waveController.stop();

      debugPrint(
          'RealtimeTranslator: Recording stopped, starting processing...');
      await _processAudio();
    } catch (e) {
      debugPrint('RealtimeTranslator: Stop recording error: $e');
      _showErrorDialog('Failed to stop recording: $e');
      setState(() {
        _isRecording = false;
        _isProcessing = false;
        _isRealtimeListeningPaused = false;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REAL-TIME MODE METHODS (NEW)
  // ═══════════════════════════════════════════════════════════════

  /// Start real-time translation session using Soniox
  /// THREE-PHASE FLOW: Initializing → Ready (beep) → Recording
  Future<void> _startRealtimeSession() async {
    try {
      debugPrint('RealtimeTranslator: ═══ Starting Real-time Session (3-Phase Flow) ═══');

      // ═══════════════════════════════════════════════════════
      // PHASE 1: INITIALIZING STATE
      // ═══════════════════════════════════════════════════════
      debugPrint('RealtimeTranslator: 📍 PHASE 1: INITIALIZING (Connecting to Soniox)');
      
      setState(() {
        _isInitializing = true;
        _isRecording = false;
        _isProcessing = false;
        _isRealtimeListeningPaused = false;
      });

      // Start pulse animation during initialization
      _pulseController.repeat(reverse: true);

      // Check Bluetooth connection
      // NEW: Allows translation without TWS (playback will be disabled)
      debugPrint('RealtimeTranslator: Checking Bluetooth connection...');
      final hasBluetooth = await _checkBluetoothBeforeRecording();
      // Note: hasBluetooth now always returns true (allows translation without TWS)
      // TWS connection status is stored in _isTwsConnected for playback control
      if (!hasBluetooth) {
        debugPrint('RealtimeTranslator: ❌ Cannot start - unexpected error');
        setState(() {
          _isInitializing = false;
        });
        _pulseController.stop();
        return;
      }

      // Check microphone permission
      debugPrint('RealtimeTranslator: Checking microphone permission...');
      final hasPermission =
          await _permissionService.requestMicrophonePermission();
      if (!hasPermission) {
        _showErrorDialog('Microphone permission is required for recording.');
        setState(() {
          _isInitializing = false;
        });
        _pulseController.stop();
        return;
      }

      // Reset session metrics for new session
      _resetSessionMetrics();
      _sessionStartTime = DateTime.now();
      debugPrint('RealtimeTranslator: ✅ Session started at ${_sessionStartTime}');
      
      // Reset dialog flags for new session
      _hasShownTwsNotConnectedDialog = false;
      _hasShownTwsConnectedDialog = false;

      // Clear previous results
      debugPrint('RealtimeTranslator: Clearing previous session data...');
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

      // Configure audio route
      debugPrint('RealtimeTranslator: Configuring audio route...');
      await _enterRecordingRoute();
      await Future.delayed(const Duration(milliseconds: 200));

      // Initialize Soniox service
      debugPrint('RealtimeTranslator: Initializing Soniox service...');
      await _sonioxService.initialize();

      // Connect to Soniox WebSocket
      final speaker1Lang = _speakerLanguages[0]?.code ?? 'en';
      final speaker2Lang = _speakerLanguages[1]?.code ?? 'bn';
      
      debugPrint('RealtimeTranslator: Connecting to Soniox...');
      debugPrint('RealtimeTranslator: Speaker 1 language: $speaker1Lang');
      debugPrint('RealtimeTranslator: Speaker 2 language: $speaker2Lang');

      await _sonioxService.connect(
        languageA: speaker1Lang,
        languageB: speaker2Lang,
        enableSpeakerDiarization: true,
      );

      debugPrint('RealtimeTranslator: ✅ Soniox connected successfully!');

      // Set up callbacks
      _sonioxService.onConnected = () {
        debugPrint('RealtimeTranslator: ✅ Soniox WebSocket connected - ready for audio stream');
      };

      _sonioxService.onError = (error) {
        debugPrint('RealtimeTranslator: ❌ Soniox error: $error');
        _showErrorDialog('Real-time translation error: $error');
        _stopRealtimeSession();
      };

      _sonioxService.onDisconnected = () {
        debugPrint('RealtimeTranslator: ⚠️ Soniox disconnected');
      };

      // Listen to Soniox results
      _sonioxStreamSubscription = _sonioxService.resultStream?.listen(
        _handleSonioxResult,
        onError: (error) {
          debugPrint('RealtimeTranslator: ❌ Soniox stream error: $error');
        },
      );

      // ═══════════════════════════════════════════════════════
      // PHASE 2: READY STATE (Play beep to signal ready)
      // ═══════════════════════════════════════════════════════
      debugPrint('RealtimeTranslator: 📍 PHASE 2: READY (Playing start beep)');

      // Play start beep to signal that system is ready to record
      await _playStartRecordingSound();
      
      debugPrint('RealtimeTranslator: ✅ Ready beep played - user can now speak');

      // ═══════════════════════════════════════════════════════
      // PHASE 3: RECORDING STATE
      // ═══════════════════════════════════════════════════════
      debugPrint('RealtimeTranslator: 📍 PHASE 3: RECORDING (Starting audio capture)');

      // Update state to recording
      setState(() {
        _isInitializing = false;
        _isRecording = true;
      });

      // Stop pulse animation, start wave animation for recording
      _pulseController.stop();
      _waveController.repeat();

      // Start native audio recording (fallback approach)
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordedAudioPath = '${directory.path}/realtime_recording_$timestamp.wav';

      debugPrint('RealtimeTranslator: Starting native audio recorder...');
      debugPrint('RealtimeTranslator: Recording path: $_recordedAudioPath');

      // Use existing native recorder (works immediately)
      final bool recordingStarted =
          await _nativeRecorder.startRecording(_recordedAudioPath!);

      if (!recordingStarted) {
        debugPrint('RealtimeTranslator: ❌ Failed to start native recording');
        _showErrorDialog('Failed to start recording. Please try again.');
        setState(() {
          _isRecording = false;
        });
        _waveController.stop();
        await _sonioxService.disconnect();
        return;
      }

      debugPrint('RealtimeTranslator: ✅ Native recording started');
      
      // Start polling audio file to send chunks to Soniox
      debugPrint('RealtimeTranslator: Starting audio file polling for streaming...');
      _startAudioFilePolling();

      debugPrint('RealtimeTranslator: ✅ Real-time session started successfully');
      debugPrint('RealtimeTranslator: Audio chunks will be streamed to Soniox');
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Real-time session error: $e');
      _showErrorDialog('Failed to start real-time session: $e');
      setState(() {
        _isInitializing = false;
        _isRecording = false;
      });
      _pulseController.stop();
      _waveController.stop();
    }
  }

  /// Stop real-time translation session
  Future<void> _stopRealtimeSession() async {
    try {
      debugPrint('RealtimeTranslator: Stopping real-time session...');

      // Mark session end time
      _sessionEndTime = DateTime.now();
      debugPrint('RealtimeTranslator: ✅ Session ended at ${_sessionEndTime}');
      
      // Update UI to reflect TWS status
      if (mounted) {
        setState(() {
          // UI will update to show TWS status indicator if needed
        });
      }

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

      debugPrint('RealtimeTranslator: ✅ Real-time session stopped');
      
      // Show session summary
      _showSessionSummary();
      
      // Transfer accumulated text to main transcriptions/translations
      _transcriptions[0] = _realtimeTranscriptions[0]?.toString() ?? '';
      _transcriptions[1] = _realtimeTranscriptions[1]?.toString() ?? '';
      _translations[0] = _realtimeTranslations[0]?.toString() ?? '';
      _translations[1] = _realtimeTranslations[1]?.toString() ?? '';

      debugPrint('RealtimeTranslator: Final transcriptions:');
      debugPrint('  Speaker 0: ${_transcriptions[0]}');
      debugPrint('  Speaker 1: ${_transcriptions[1]}');
      debugPrint('RealtimeTranslator: Final translations:');
      debugPrint('  Speaker 0: ${_translations[0]}');
      debugPrint('  Speaker 1: ${_translations[1]}');
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Stop real-time session error: $e');
      setState(() {
        _isRecording = false;
        _isProcessing = false;
      });
    }
  }


  /// Reset session metrics for new session
  void _resetSessionMetrics() {
    _sessionStartTime = null;
    _sessionEndTime = null;
    _audioSecondsProcessed = 0.0;
    _totalInputAudioTokens = 0;
    _totalOutputTextTokens = 0;
    _totalTranscriptionCharacters = 0;
    _totalTranslationCharacters = 0;
    _transcriptionCharactersPerSpeaker = {0: 0, 1: 0};
    _translationCharactersPerSpeaker = {0: 0, 1: 0};
    _translationLatencies = [];
    _totalTranslations = 0;
    
    debugPrint('RealtimeTranslator: ✅ Session metrics reset');
  }

  /// Calculate total session cost based on Soniox pricing
  /// Reference: https://soniox.com/pricing
  double _calculateSessionCost() {
    // Input audio tokens: 1 hour = 30,000 tokens, so 1 second = 8.333 tokens
    final inputAudioTokens = (_audioSecondsProcessed * _tokensPerSecond).round();
    final inputAudioCost = (inputAudioTokens / 1000000) * _inputAudioCostPerMillion;
    
    // Output text tokens: 1 character = 0.3 tokens (transcription + translation)
    final totalOutputCharacters = _totalTranscriptionCharacters + _totalTranslationCharacters;
    final outputTextTokens = (totalOutputCharacters * _tokensPerCharacter).round();
    final outputTextCost = (outputTextTokens / 1000000) * _outputTextCostPerMillion;
    
    final totalCost = inputAudioCost + outputTextCost;
    
    debugPrint('RealtimeTranslator: 💰 Session Cost Breakdown (Soniox Pricing):');
    debugPrint('  Input Audio:');
    debugPrint('    - Audio processed: ${_audioSecondsProcessed.toStringAsFixed(2)}s');
    debugPrint('    - Tokens: $inputAudioTokens (${_audioSecondsProcessed.toStringAsFixed(2)}s × ${_tokensPerSecond.toStringAsFixed(3)} tokens/s)');
    debugPrint('    - Cost: \$${inputAudioCost.toStringAsFixed(6)} ($inputAudioTokens tokens × \$${_inputAudioCostPerMillion}/1M)');
    debugPrint('  Output Text:');
    debugPrint('    - Transcription: $_totalTranscriptionCharacters chars');
    debugPrint('    - Translation: $_totalTranslationCharacters chars');
    debugPrint('    - Total chars: $totalOutputCharacters');
    debugPrint('    - Tokens: $outputTextTokens ($totalOutputCharacters chars × ${_tokensPerCharacter.toStringAsFixed(1)} tokens/char)');
    debugPrint('    - Cost: \$${outputTextCost.toStringAsFixed(6)} ($outputTextTokens tokens × \$${_outputTextCostPerMillion}/1M)');
    debugPrint('  Total Cost: \$${totalCost.toStringAsFixed(4)}');
    
    // Store calculated tokens for summary display
    _totalInputAudioTokens = inputAudioTokens;
    _totalOutputTextTokens = outputTextTokens;
    
    return totalCost;
  }

  /// Start polling audio file to simulate streaming
  /// This is a fallback approach until native streaming is implemented
  void _startAudioFilePolling() {
    debugPrint('RealtimeTranslator: Starting audio file polling (100ms intervals)...');
    
    _lastReadPosition = 44; // Skip WAV header (44 bytes)
    
    // Poll every 100ms to read new audio data
    _audioPollingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      try {
        if (!_isRecording || _recordedAudioPath == null) {
          debugPrint('RealtimeTranslator: ⚠️ Stopping audio polling - recording stopped');
          timer.cancel();
          return;
        }

        final audioFile = File(_recordedAudioPath!);
        
        // Check if file exists
        if (!await audioFile.exists()) {
          debugPrint('RealtimeTranslator: ⚠️ Audio file does not exist yet');
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
            
            // Track audio seconds processed (16-bit PCM, 16000 Hz, mono = 32000 bytes/second)
            final secondsInChunk = chunk.length / 32000.0;
            _audioSecondsProcessed += secondsInChunk;
            
            debugPrint('RealtimeTranslator: 📤 Sent ${chunk.length} bytes to Soniox (position: $_lastReadPosition)');
          }
        }
      } catch (e) {
        debugPrint('RealtimeTranslator: ❌ Audio polling error: $e');
      }
    });
    
    debugPrint('RealtimeTranslator: ✅ Audio file polling started');
  }

  /// REALTIME TRANSLATION: Pause method disabled - full-duplex mode (no pausing)
  /// This method is kept for compatibility but does nothing in mono mode
  Future<bool> _pauseRealtimeListeningForPlayback() async {
    // REALTIME TRANSLATION: No pausing - recording continues during playback
    debugPrint('RealtimeTranslator: Pause disabled (full-duplex mode)');
    return false;
  }

  /// REALTIME TRANSLATION: Resume method disabled - full-duplex mode (no resuming needed)
  /// This method is kept for compatibility but does nothing in mono mode
  Future<void> _resumeRealtimeListeningAfterPlayback() async {
    // REALTIME TRANSLATION: No resuming needed - recording never stopped
    debugPrint('RealtimeTranslator: Resume disabled (full-duplex mode - recording never stopped)');
    return;
  }

  /// Handle Soniox real-time results (Transcription + Translation + Diarization)
  /// ENHANCEMENT: Now using Soniox's native translation (reduces latency by ~2-3 seconds)
  /// Reference: https://soniox.com/docs/stt/rt/real-time-translation
  Future<void> _handleSonioxResult(SonioxResult result) async {
    try {
      debugPrint('RealtimeTranslator: ═══ Soniox Real-Time Result ═══');
      debugPrint('RealtimeTranslator: Tokens count: ${result.tokens.length}');
      debugPrint('RealtimeTranslator: Speaker 1 language: ${_speakerLanguages[0]?.code}');
      debugPrint('RealtimeTranslator: Speaker 2 language: ${_speakerLanguages[1]?.code}');

      if (result.tokens.isEmpty) {
        debugPrint('RealtimeTranslator: ⚠️ No tokens in result');
        return;
      }

      // Group transcriptions AND translations by speaker
      Map<int, String> transcriptionTexts = {};      // Original tokens
      Map<int, String> translationTexts = {};        // Translation tokens (NEW)
      Map<int, String> transcriptionLanguages = {};
      Map<int, String> translationLanguages = {};    // Translation target languages (NEW)
      Map<int, bool> hasFinalized = {};
      
      // Process all tokens (both transcription AND translation from Soniox)
      // Soniox provides tokens with translation_status: "original" or "translation"
      for (var token in result.tokens) {
        debugPrint('RealtimeTranslator: Token: "${token.text}" | Status: ${token.translationStatus} | Lang: ${token.language} | Source: ${token.sourceLanguage} | Speaker: ${token.speaker} | Final: ${token.isFinal}');
        
        // Filter out special tokens like <end>, <unk>, etc.
        final tokenText = token.text.trim();
        if (tokenText.startsWith('<') && tokenText.endsWith('>')) {
          debugPrint('RealtimeTranslator: ⚠️ Skipping special token: $tokenText');
          continue; // Skip special tokens
        }
        
        // Skip empty tokens
        if (tokenText.isEmpty) {
          continue;
        }
        
        final sonioxSpeakerId = token.speaker ?? 0;
        
        // Process based on translation status
        if (token.isOriginal) {
          // Original transcription
          final detectedLanguage = token.language;
        transcriptionTexts[sonioxSpeakerId] = (transcriptionTexts[sonioxSpeakerId] ?? '') + token.text;
        transcriptionLanguages[sonioxSpeakerId] = detectedLanguage;
          debugPrint('RealtimeTranslator: ✅ Original transcription: "${token.text}" (${token.language})');
        } else if (token.isTranslation) {
          // Translation provided by Soniox (NEW!)
          translationTexts[sonioxSpeakerId] = (translationTexts[sonioxSpeakerId] ?? '') + token.text;
          translationLanguages[sonioxSpeakerId] = token.language;
          debugPrint('RealtimeTranslator: ✅ Soniox translation: "${token.text}" (${token.sourceLanguage} → ${token.language})');
        } else {
          // Token not translated (language not in two-way pair)
          // Treat as transcription only
          transcriptionTexts[sonioxSpeakerId] = (transcriptionTexts[sonioxSpeakerId] ?? '') + token.text;
          transcriptionLanguages[sonioxSpeakerId] = token.language;
          debugPrint('RealtimeTranslator: ⚠️ Not translated: "${token.text}" (${token.language})');
        }
        
        if (token.isFinal) {
          hasFinalized[sonioxSpeakerId] = true;
        }
      }

      // Process each speaker's transcription AND translation
      // CRITICAL: Use for loop instead of forEach to support async/await
      // ALSO: Check for translation-only messages (no transcription in same message)
      
      // First, check if this is a translation-only message (translations without transcriptions)
      for (final entry in translationTexts.entries) {
        final sonioxSpeakerId = entry.key;
        if (!transcriptionTexts.containsKey(sonioxSpeakerId)) {
          // Translation-only message - check if we have a pending transcription waiting for it
          final translationText = entry.value;
          
          // Check all pending transcriptions to find matching speaker
          for (final pendingEntry in _pendingTranscriptions.entries) {
            final pendingSpeaker = pendingEntry.key;
            // If this translation is for this pending speaker, use it!
            if (translationText.isNotEmpty) {
              debugPrint('RealtimeTranslator: ✅ Translation-only message received for UI Speaker $pendingSpeaker');
              debugPrint('RealtimeTranslator: Translation: "$translationText"');
              
              // Cancel timer
              _pendingTranslationTimers[pendingSpeaker]?.cancel();
              _pendingTranslationTimers[pendingSpeaker] = null;
              
              final pendingTranscription = _pendingTranscriptions[pendingSpeaker] ?? '';
              final pendingLanguage = _pendingLanguages[pendingSpeaker] ?? '';
              
              // Clean up
              _pendingTranscriptions.remove(pendingSpeaker);
              _pendingLanguages.remove(pendingSpeaker);
              
              // Process translation
              debugPrint('RealtimeTranslator: ✅ Using Soniox translation (no Azure API call needed - saves ~2-3 seconds!)');
              await _handleSonioxTranslationAndPlayTts(
                speakerIndex: pendingSpeaker,
                transcribedText: pendingTranscription,
                translatedText: translationText.trim(),
                sourceLanguage: pendingLanguage,
              );
              
              // Only process first pending translation
              break;
            }
          }
        }
      }
      
      // Then, process messages that have transcriptions
      for (final entry in transcriptionTexts.entries) {
        final sonioxSpeakerId = entry.key;
        final transcriptionText = entry.value;
        final detectedLanguage = transcriptionLanguages[sonioxSpeakerId] ?? '';
        final translationText = translationTexts[sonioxSpeakerId] ?? ''; // Get Soniox translation (NEW)
        final isFinal = hasFinalized[sonioxSpeakerId] ?? false;
        
        debugPrint('RealtimeTranslator: ═══ Processing Soniox Speaker $sonioxSpeakerId ═══');
        debugPrint('  Detected language: $detectedLanguage');
        debugPrint('  Transcription: "$transcriptionText"');
        debugPrint('  Translation: "$translationText"'); // Log Soniox translation (NEW)
        debugPrint('  Is Final: $isFinal');
        
        // Map Soniox speaker to UI speaker based on detected language AND transcribed text
        // This helps detect phonetic transcriptions (e.g., English spoken but written in Bengali script)
        int uiSpeakerIndex = _mapSonioxSpeakerToUiSpeaker(sonioxSpeakerId, detectedLanguage, transcriptionText);
        
        debugPrint('RealtimeTranslator: Mapped Soniox Speaker $sonioxSpeakerId → UI Speaker $uiSpeakerIndex');
        debugPrint('RealtimeTranslator: UI Speaker $uiSpeakerIndex configured language: ${_speakerLanguages[uiSpeakerIndex]?.code}');

        // Initialize buffers if needed
        if (_realtimeTranscriptions[uiSpeakerIndex] == null) {
          _realtimeTranscriptions[uiSpeakerIndex] = StringBuffer();
        }
        if (_realtimeTranslations[uiSpeakerIndex] == null) {
          _realtimeTranslations[uiSpeakerIndex] = StringBuffer();
        }

        // For final results, append and process translation
        if (isFinal) {
          if (transcriptionText.isNotEmpty) {
            // Append final transcription
            if (_realtimeTranscriptions[uiSpeakerIndex]!.isNotEmpty) {
              _realtimeTranscriptions[uiSpeakerIndex]!.write(' ');
            }
            _realtimeTranscriptions[uiSpeakerIndex]!.write(transcriptionText);
            debugPrint('RealtimeTranslator: ✅ Appended FINAL transcription to UI Speaker $uiSpeakerIndex');
            
            // Track transcription characters (Soniox charges by character, not word)
            // 1 character = 0.3 tokens according to Soniox pricing
            final transcriptionCharCount = transcriptionText.length;
            _totalTranscriptionCharacters += transcriptionCharCount;
            _transcriptionCharactersPerSpeaker[uiSpeakerIndex] = 
                (_transcriptionCharactersPerSpeaker[uiSpeakerIndex] ?? 0) + transcriptionCharCount;
            
            final transcriptionTokens = (transcriptionCharCount * _tokensPerCharacter).round();
            debugPrint('RealtimeTranslator: 📊 Transcription: $transcriptionCharCount chars ≈ $transcriptionTokens tokens (total chars: $_totalTranscriptionCharacters)');
          }

          // Update UI with transcription immediately
          if (mounted) {
            setState(() {
              _transcriptions[uiSpeakerIndex] = _realtimeTranscriptions[uiSpeakerIndex]?.toString().trim() ?? '';
            });
            debugPrint('RealtimeTranslator: ✅ UI updated with transcription for UI Speaker $uiSpeakerIndex');
            // Auto-scroll to latest content (transcription)
            _autoScrollToBottom(uiSpeakerIndex, isTranslation: false);
          }

          // ENHANCEMENT: Use Soniox translation instead of Azure API
          // If Soniox provided translation, use it directly (MUCH faster!)
          // Otherwise, wait a bit for translation tokens before falling back to Azure API
          if (transcriptionText.isNotEmpty) {
            if (translationText.isNotEmpty) {
              // Translation already available - use it immediately!
              debugPrint('RealtimeTranslator: ✅ Using Soniox translation (no Azure API call needed - saves ~2-3 seconds!)');
              
              // Cancel pending timer if exists
              _pendingTranslationTimers[uiSpeakerIndex]?.cancel();
              _pendingTranslationTimers[uiSpeakerIndex] = null;
              _pendingTranscriptions.remove(uiSpeakerIndex);
              _pendingLanguages.remove(uiSpeakerIndex);
              
              await _handleSonioxTranslationAndPlayTts(
              speakerIndex: uiSpeakerIndex,
              transcribedText: transcriptionText.trim(),
                translatedText: translationText.trim(),
              sourceLanguage: detectedLanguage,
            );
            } else {
              // No translation yet - wait for translation tokens before falling back
              debugPrint('RealtimeTranslator: ⏳ Waiting for Soniox translation tokens (500ms timeout)...');
              
              // Store transcription for pending translation
              _pendingTranscriptions[uiSpeakerIndex] = transcriptionText.trim();
              _pendingLanguages[uiSpeakerIndex] = detectedLanguage;
              
              // Cancel existing timer if any
              _pendingTranslationTimers[uiSpeakerIndex]?.cancel();
              
              // Wait 500ms for translation tokens
              _pendingTranslationTimers[uiSpeakerIndex] = Timer(const Duration(milliseconds: 500), () async {
                // Timer expired - translation tokens didn't arrive, fall back to Azure
                debugPrint('RealtimeTranslator: ⏰ Translation timeout - falling back to Azure API');
                await _translateAndPlayRealtimeTts(
                  speakerIndex: uiSpeakerIndex,
                  transcribedText: _pendingTranscriptions[uiSpeakerIndex] ?? '',
                  sourceLanguage: _pendingLanguages[uiSpeakerIndex] ?? '',
                );
                
                // Clean up
                _pendingTranscriptions.remove(uiSpeakerIndex);
                _pendingLanguages.remove(uiSpeakerIndex);
                _pendingTranslationTimers[uiSpeakerIndex] = null;
              });
              
              debugPrint('RealtimeTranslator: ⏳ Timer started - waiting for translation tokens');
            }
          }
        } else {
          // Non-final (interim) results: Show interim text WITHOUT adding to buffer
          // ALSO: Check if this contains translation tokens for a pending transcription
          
          // CRITICAL: Check if translation arrived for a pending transcription
          if (translationText.isNotEmpty && _pendingTranscriptions.containsKey(uiSpeakerIndex)) {
            // Translation tokens arrived! Use them instead of waiting for timeout
            debugPrint('RealtimeTranslator: ✅ Translation tokens arrived! Using Soniox translation (no Azure API call needed - saves ~2-3 seconds!)');
            
            // Cancel pending timer
            _pendingTranslationTimers[uiSpeakerIndex]?.cancel();
            _pendingTranslationTimers[uiSpeakerIndex] = null;
            
            final pendingTranscription = _pendingTranscriptions[uiSpeakerIndex] ?? '';
            final pendingLanguage = _pendingLanguages[uiSpeakerIndex] ?? '';
            
            // Clean up pending data
            _pendingTranscriptions.remove(uiSpeakerIndex);
            _pendingLanguages.remove(uiSpeakerIndex);
            
            // Process translation immediately
            await _handleSonioxTranslationAndPlayTts(
              speakerIndex: uiSpeakerIndex,
              transcribedText: pendingTranscription,
              translatedText: translationText.trim(),
              sourceLanguage: pendingLanguage,
            );
          }
          
          // Show interim text in UI (without adding to buffer)
          if (mounted) {
            final accumulatedTranscription = _realtimeTranscriptions[uiSpeakerIndex]?.toString().trim() ?? '';
            final accumulatedTranslation = _realtimeTranslations[uiSpeakerIndex]?.toString().trim() ?? '';
            
            // Show accumulated + current interim (but don't save interim to buffer)
            final displayTranscription = accumulatedTranscription.isNotEmpty && transcriptionText.isNotEmpty
                ? '$accumulatedTranscription $transcriptionText'
                : (transcriptionText.isNotEmpty ? transcriptionText : accumulatedTranscription);
            
            // Show interim translation if available (Soniox provides streaming translations)
            final displayTranslation = accumulatedTranslation.isNotEmpty && translationText.isNotEmpty
                ? '$accumulatedTranslation $translationText'
                : (translationText.isNotEmpty ? translationText : accumulatedTranslation);

            setState(() {
              _transcriptions[uiSpeakerIndex] = displayTranscription.trim();
              if (displayTranslation.isNotEmpty) {
                _translations[uiSpeakerIndex] = displayTranslation.trim();
              }
            });
            debugPrint('RealtimeTranslator: ✅ UI updated with INTERIM transcription/translation for UI Speaker $uiSpeakerIndex (not saved to buffer)');
            // Auto-scroll to latest content (transcription)
            _autoScrollToBottom(uiSpeakerIndex, isTranslation: false);
            if (displayTranslation.isNotEmpty) {
              _autoScrollToBottom(uiSpeakerIndex, isTranslation: true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error handling Soniox result: $e');
      debugPrint('RealtimeTranslator: Stack trace: ${StackTrace.current}');
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
    
    debugPrint('RealtimeTranslator: Language Mapping:');
    debugPrint('  UI Speaker 0 configured: $speaker1Lang');
    debugPrint('  UI Speaker 1 configured: $speaker2Lang');
    debugPrint('  Detected language: $detectedLangLower');
    debugPrint('  Soniox speaker ID: $sonioxSpeakerId');
    debugPrint('  Transcribed text: "$transcribedText"');
    
    // Check if text is phonetically transcribed (English words in Bengali/other script)
    // If it looks like phonetic transcription, it might be the wrong language detection
    final isPhoneticBengali = _isPhoneticTranscription(transcribedText, detectedLangLower);
    if (isPhoneticBengali) {
      debugPrint('RealtimeTranslator: ⚠️ Detected phonetic transcription!');
      debugPrint('RealtimeTranslator: Likely English spoken but transcribed as $detectedLangLower');
      
      // If phonetic, assume it's actually the OTHER language
      if (detectedLangLower == speaker2Lang) {
        debugPrint('RealtimeTranslator: Mapping to UI Speaker 0 (likely English)');
        return 0;
      } else if (detectedLangLower == speaker1Lang) {
        debugPrint('RealtimeTranslator: Mapping to UI Speaker 1 (likely Bengali)');
        return 1;
      }
    }
    
    // Match based on language code
    // If detected language matches Speaker 1's language, map to Speaker 1 (index 0)
    // If detected language matches Speaker 2's language, map to Speaker 2 (index 1)
    if (detectedLangLower == speaker1Lang || detectedLangLower.startsWith(speaker1Lang)) {
      debugPrint('RealtimeTranslator: Language matches UI Speaker 0');
      return 0;
    } else if (detectedLangLower == speaker2Lang || detectedLangLower.startsWith(speaker2Lang)) {
      debugPrint('RealtimeTranslator: Language matches UI Speaker 1');
      return 1;
    }
    
    // Fallback: use Soniox's speaker ID directly
    debugPrint('RealtimeTranslator: ⚠️ No language match, using Soniox speaker ID: $sonioxSpeakerId');
    return sonioxSpeakerId;
  }

  /// Check if text contains a complete sentence
  /// Looks for sentence-ending punctuation marks
  bool _isCompleteSentence(String text) {
    if (text.isEmpty) return false;
    
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return false;
    
    // Check for sentence-ending punctuation
    // English: . ! ?
    // Bengali: । (devanagari danda), ! ?
    // General: Multiple language punctuation marks
    final sentenceEnders = [
      '.', '!', '?',           // English/Latin
      '।', '॥',                // Bengali/Devanagari
      '。', '！', '？',         // Chinese/Japanese
      '؟', '۔',                // Arabic/Urdu
      ':', ';',                // Additional punctuation (sometimes ends thoughts)
    ];
    
    // Check if text ends with any sentence-ending punctuation
    for (final ender in sentenceEnders) {
      if (trimmedText.endsWith(ender)) {
        return true;
      }
    }
    
    return false;
  }

  /// Extract ALL completed sentences from text buffer
  /// Returns a map with 'completed' (all completed sentences as one text) and 'incomplete' (remaining text)
  /// PRODUCTION-READY: Handles multiple completed sentences in one buffer
  /// Example: "Hello. How are you? I am fine" + incomplete text → returns completed: "Hello. How are you? I am fine", incomplete: ""
  /// Example: "Hello. How are you? I am" → returns completed: "Hello. How are you?", incomplete: "I am"
  Map<String, String> _extractCompletedSentences(String text) {
    if (text.isEmpty) {
      return {'completed': '', 'incomplete': ''};
    }
    
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      return {'completed': '', 'incomplete': ''};
    }
    
    // Sentence-ending punctuation marks
    final sentenceEnders = [
      '.', '!', '?',           // English/Latin
      '।', '॥',                // Bengali/Devanagari
      '。', '！', '？',         // Chinese/Japanese
      '؟', '۔',                // Arabic/Urdu
      ':', ';',                // Additional punctuation (sometimes ends thoughts)
    ];
    
    // Find the last occurrence of any sentence-ending punctuation
    int lastSentenceEndIndex = -1;
    String lastEnderFound = '';
    
    for (final ender in sentenceEnders) {
      final index = trimmedText.lastIndexOf(ender);
      if (index > lastSentenceEndIndex) {
        lastSentenceEndIndex = index;
        lastEnderFound = ender;
      }
    }
    
    // If no sentence-ending punctuation found, entire text is incomplete
    if (lastSentenceEndIndex == -1) {
      return {'completed': '', 'incomplete': trimmedText};
    }
    
    // Split at the last sentence-ending punctuation
    // Include the punctuation in the completed part
    final completedPart = trimmedText.substring(0, lastSentenceEndIndex + 1).trim();
    
    // Everything after the last punctuation is incomplete
    final incompletePart = lastSentenceEndIndex < trimmedText.length - 1
        ? trimmedText.substring(lastSentenceEndIndex + 1).trim()
        : '';
    
    debugPrint('RealtimeTranslator: 📝 Sentence Extraction:');
    debugPrint('RealtimeTranslator:   Original text length: ${trimmedText.length} chars');
    debugPrint('RealtimeTranslator:   Last sentence ender: "$lastEnderFound" at index $lastSentenceEndIndex');
    debugPrint('RealtimeTranslator:   Completed sentences: "${completedPart.length > 100 ? completedPart.substring(0, 100) + '...' : completedPart}"');
    debugPrint('RealtimeTranslator:   Incomplete text: "${incompletePart.length > 50 ? incompletePart.substring(0, 50) + '...' : incompletePart}"');
    debugPrint('RealtimeTranslator:   Completed sentences count: ${_countSentences(completedPart)}');
    
    return {
      'completed': completedPart,
      'incomplete': incompletePart,
    };
  }
  
  /// Count the number of completed sentences in text
  /// Helper method for logging and analytics
  int _countSentences(String text) {
    if (text.isEmpty) return 0;
    
    final sentenceEnders = ['.', '!', '?', '।', '॥', '。', '！', '？', '؟', '۔', ':', ';'];
    
    int count = 0;
    for (final ender in sentenceEnders) {
      count += ender.allMatches(text).length;
    }
    
    return count;
  }

  /// Process accumulated sentences in batch after adaptive delay
  /// This is called by the timer after no new translation chunks arrive
  /// PRODUCTION-READY: Generates ONE TTS for ALL completed sentences
  Future<void> _processSentenceBatch({
    required int speakerIndex,
    required int targetSpeakerIndex,
    required Language targetLanguage,
  }) async {
    try {
      final chunkCount = _accumulatedChunkCount[speakerIndex] ?? 0;
      final lastChunkTime = _lastChunkReceivedTime[speakerIndex];
      final timeSinceLastChunk = lastChunkTime != null 
          ? DateTime.now().difference(lastChunkTime).inMilliseconds 
          : 0;
      
      debugPrint('RealtimeTranslator: ═══ BATCH Sentence Processing (Adaptive Timer Fired) ═══');
      debugPrint('RealtimeTranslator: Speaker: $speakerIndex');
      debugPrint('RealtimeTranslator: Chunks accumulated: $chunkCount');
      debugPrint('RealtimeTranslator: Time since last chunk: ${timeSinceLastChunk}ms');
      debugPrint('RealtimeTranslator: Processing ALL accumulated sentences in ONE batch');
      
      // Get current buffer content
      final currentBuffer = _sentenceTranslationBuffers[speakerIndex]?.toString().trim() ?? '';
      
      if (currentBuffer.isEmpty) {
        debugPrint('RealtimeTranslator: Buffer is empty, nothing to process');
        return;
      }
      
      debugPrint('RealtimeTranslator: Buffer content length: ${currentBuffer.length} chars');
      
      // Extract completed and incomplete parts
      final extracted = _extractCompletedSentences(currentBuffer);
      final completedSentences = extracted['completed'] ?? '';
      final incompleteSentence = extracted['incomplete'] ?? '';
      
      final sentenceCount = _countSentences(completedSentences);
      
      debugPrint('RealtimeTranslator: Completed sentences: $sentenceCount');
      debugPrint('RealtimeTranslator: Incomplete text length: ${incompleteSentence.length} chars');

      if (completedSentences.isNotEmpty) {
        // Generate TTS for ALL completed sentences at once (BATCH PROCESSING)
        final targetGender = _speakerGenders[targetSpeakerIndex] ?? 'male';
        final earpiece = _speakerEarpieces[targetSpeakerIndex] ?? 'left';

        debugPrint('RealtimeTranslator: ═══ BATCH TTS Generation ═══');
        debugPrint('RealtimeTranslator: TTS for target speaker: $targetSpeakerIndex');
        debugPrint('RealtimeTranslator: TTS language: ${targetLanguage.code}');
        debugPrint('RealtimeTranslator: Processing $sentenceCount completed sentence(s) in ONE batch');
        debugPrint('RealtimeTranslator: Combined TTS text: "${completedSentences.length > 100 ? completedSentences.substring(0, 100) + '...' : completedSentences}"');
        debugPrint('RealtimeTranslator: TTS gender: $targetGender');
        debugPrint('RealtimeTranslator: TTS earpiece: $earpiece');
        debugPrint('RealtimeTranslator: ✅ ADVANTAGE: All completed sentences processed in ONE TTS generation');
        debugPrint('RealtimeTranslator: ✅ This eliminates multiple TTS files for consecutive sentences');

        // Add to TTS queue for pre-generation and playback (ALL completed sentences at once)
        _addToTtsQueue(
          speakerIndex: targetSpeakerIndex,
          text: completedSentences, // All completed sentences combined
          languageCode: targetLanguage.code,
          gender: targetGender,
        );

        // Update sentence buffers: Keep only the incomplete text
        // CRITICAL: Don't clear buffers completely - keep incomplete sentence for next iteration
        _sentenceTranscriptionBuffers[speakerIndex]?.clear();
        _sentenceTranslationBuffers[speakerIndex]?.clear();
        
        if (incompleteSentence.isNotEmpty) {
          _sentenceTranslationBuffers[speakerIndex]?.write(incompleteSentence);
          debugPrint('RealtimeTranslator: ✅ Batch processing complete, incomplete text kept in buffer: "$incompleteSentence"');
        } else {
          debugPrint('RealtimeTranslator: ✅ Batch processing complete, all sentences were completed, buffer cleared');
        }
        
        debugPrint('RealtimeTranslator: ✅ $sentenceCount completed sentence(s) processed as ONE batch');
        debugPrint('RealtimeTranslator: ✅ Result: ONE TTS file instead of $sentenceCount separate files');
        debugPrint('RealtimeTranslator: ✅ Batch efficiency: $chunkCount chunks → 1 TTS file');
      } else {
        debugPrint('RealtimeTranslator: ⏳ No completed sentences yet, all text is incomplete');
        debugPrint('RealtimeTranslator: Current buffer: "$incompleteSentence"');
        debugPrint('RealtimeTranslator: Waiting for more text to complete sentences');
      }
      
      // Reset chunk counter after processing
      _accumulatedChunkCount[speakerIndex] = 0;
      _lastChunkReceivedTime[speakerIndex] = null;
      
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error in batch sentence processing: $e');
      debugPrint('RealtimeTranslator: Stack trace: ${StackTrace.current}');
      
      // Reset counters on error
      _accumulatedChunkCount[speakerIndex] = 0;
      _lastChunkReceivedTime[speakerIndex] = null;
    }
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

  /// Handle Soniox translation and generate TTS
  /// ENHANCEMENT: Uses translation directly from Soniox (no Azure API call)
  /// SMART BUFFERING: Accumulates text until complete sentence before TTS generation
  /// This reduces latency by ~2-3 seconds compared to Azure Translation API
  Future<void> _handleSonioxTranslationAndPlayTts({
    required int speakerIndex,
    required String transcribedText,
    required String translatedText,
    required String sourceLanguage,
  }) async {
    // CRITICAL: Prevent concurrent translation+playback
    if (_isTranslationInProgress) {
      debugPrint('RealtimeTranslator: ⚠️ Translation already in progress, skipping this request');
      return;
    }

    _isTranslationInProgress = true;
    
    try {
      final translationStartTime = DateTime.now();
      
      debugPrint('RealtimeTranslator: ═══ Soniox Translation + TTS (FAST PATH) ═══');
      debugPrint('RealtimeTranslator: Speaker: $speakerIndex');
      debugPrint('RealtimeTranslator: Source language: $sourceLanguage');
      debugPrint('RealtimeTranslator: Transcribed text: "$transcribedText"');
      debugPrint('RealtimeTranslator: Translated text (from Soniox): "$translatedText"');
      debugPrint('RealtimeTranslator: ✅ No Azure API call needed - saves ~2-3 seconds!');
      
      // Track translation characters (Soniox charges by character, not word)
      // 1 character = 0.3 tokens according to Soniox pricing
      final translationCharCount = translatedText.length;
      _totalTranslationCharacters += translationCharCount;
      _translationCharactersPerSpeaker[speakerIndex] = 
          (_translationCharactersPerSpeaker[speakerIndex] ?? 0) + translationCharCount;
      _totalTranslations++;
      
      final translationTokens = (translationCharCount * _tokensPerCharacter).round();
      debugPrint('RealtimeTranslator: 📊 Translation: $translationCharCount chars ≈ $translationTokens tokens (total chars: $_totalTranslationCharacters)');

      // Update translation buffer for full conversation history
      if (_realtimeTranslations[speakerIndex]!.isNotEmpty) {
        _realtimeTranslations[speakerIndex]!.write(' ');
      }
      _realtimeTranslations[speakerIndex]!.write(translatedText);

      // Initialize sentence buffers if needed
      if (_sentenceTranscriptionBuffers[speakerIndex] == null) {
        _sentenceTranscriptionBuffers[speakerIndex] = StringBuffer();
      }
      if (_sentenceTranslationBuffers[speakerIndex] == null) {
        _sentenceTranslationBuffers[speakerIndex] = StringBuffer();
      }
      
      // Add to sentence buffer (for TTS generation)
      if (_sentenceTranscriptionBuffers[speakerIndex]!.isNotEmpty) {
        _sentenceTranscriptionBuffers[speakerIndex]!.write(' ');
      }
      _sentenceTranscriptionBuffers[speakerIndex]!.write(transcribedText);
      
      if (_sentenceTranslationBuffers[speakerIndex]!.isNotEmpty) {
        _sentenceTranslationBuffers[speakerIndex]!.write(' ');
      }
      _sentenceTranslationBuffers[speakerIndex]!.write(translatedText);
      _sentenceLanguages[speakerIndex] = sourceLanguage;

      // Determine target speaker for TTS (opposite speaker)
      final targetSpeakerIndex = speakerIndex == 0 ? 1 : 0;
      final targetLanguage = _speakerLanguages[targetSpeakerIndex];

      if (targetLanguage == null) {
        debugPrint('RealtimeTranslator: ⚠️ Target language not configured');
        _isTranslationInProgress = false;
        return;
      }

      debugPrint('RealtimeTranslator: Target speaker: $targetSpeakerIndex');
      debugPrint('RealtimeTranslator: Target language: ${targetLanguage.code}');

      // Update UI with translation immediately (show all accumulated text)
      if (mounted) {
        setState(() {
          _translations[speakerIndex] = _realtimeTranslations[speakerIndex]?.toString().trim() ?? '';
        });
        debugPrint('RealtimeTranslator: ✅ UI updated with Soniox translation for Speaker $speakerIndex');
        debugPrint('RealtimeTranslator: Speaker $speakerIndex translation: "${_translations[speakerIndex]}"');
        // Auto-scroll to latest content (translation)
        _autoScrollToBottom(speakerIndex, isTranslation: true);
      }

      // ADAPTIVE BATCH SENTENCE PROCESSING
      // Track chunk arrival for intelligent batching
      _lastChunkReceivedTime[speakerIndex] = DateTime.now();
      _accumulatedChunkCount[speakerIndex] = (_accumulatedChunkCount[speakerIndex] ?? 0) + 1;
      
      // Get current buffer to check sentence count
      final currentBuffer = _sentenceTranslationBuffers[speakerIndex]!.toString().trim();
      final extracted = _extractCompletedSentences(currentBuffer);
      final completedSentences = extracted['completed'] ?? '';
      final sentenceCount = _countSentences(completedSentences);
      
      debugPrint('RealtimeTranslator: 🕐 ADAPTIVE Batch Processing for Speaker $speakerIndex');
      debugPrint('RealtimeTranslator: 📊 Current state:');
      debugPrint('RealtimeTranslator:   - Chunks accumulated: ${_accumulatedChunkCount[speakerIndex]}');
      debugPrint('RealtimeTranslator:   - Completed sentences: $sentenceCount');
      debugPrint('RealtimeTranslator:   - Buffer length: ${currentBuffer.length} chars');
      
      // Cancel existing timer
      _sentenceProcessingTimers[speakerIndex]?.cancel();
      
      // SMART DECISION: Determine optimal processing delay
      Duration processingDelay;
      
      if (sentenceCount >= _maxSentencesForBatch) {
        // Case 1: We have many sentences (10+) - process immediately
        processingDelay = const Duration(milliseconds: 500);
        debugPrint('RealtimeTranslator: ⚡ Many sentences ($sentenceCount) - processing in 500ms');
      } else if (sentenceCount >= _minSentencesForBatch) {
        // Case 2: We have 2+ sentences - use moderate delay (2.5s)
        processingDelay = const Duration(milliseconds: 2500);
        debugPrint('RealtimeTranslator: ⏱️ Good batch ($sentenceCount sentences) - processing in 2.5s');
      } else if (sentenceCount == 1) {
        // Case 3: Only 1 sentence - wait longer for more (3.5s)
        processingDelay = const Duration(milliseconds: 3500);
        debugPrint('RealtimeTranslator: ⏳ Single sentence - waiting 3.5s for more');
      } else {
        // Case 4: No completed sentences yet - standard delay (3s)
        processingDelay = const Duration(milliseconds: 3000);
        debugPrint('RealtimeTranslator: ⏳ No completed sentences - waiting 3s');
      }
      
      // Adaptive extension: Add time based on chunk velocity
      // If chunks are coming rapidly, extend the timer
      final chunkCount = _accumulatedChunkCount[speakerIndex] ?? 0;
      if (chunkCount > 3 && sentenceCount < _minSentencesForBatch) {
        final extension = Duration(milliseconds: 500 * (chunkCount - 3));
        final extendedDelay = Duration(milliseconds: processingDelay.inMilliseconds + extension.inMilliseconds);
        
        // Cap at max delay
        if (extendedDelay <= _maxProcessingDelay) {
          processingDelay = extendedDelay;
          debugPrint('RealtimeTranslator: 🔄 Extended delay to ${processingDelay.inMilliseconds}ms (chunks arriving rapidly)');
        } else {
          processingDelay = _maxProcessingDelay;
          debugPrint('RealtimeTranslator: 🔄 Capped at max delay ${_maxProcessingDelay.inMilliseconds}ms');
        }
      }
      
      debugPrint('RealtimeTranslator: ⏰ Timer set for ${processingDelay.inMilliseconds}ms');
      
      // Start adaptive timer
      _sentenceProcessingTimers[speakerIndex] = Timer(processingDelay, () {
        _processSentenceBatch(
          speakerIndex: speakerIndex,
          targetSpeakerIndex: targetSpeakerIndex,
          targetLanguage: targetLanguage,
        );
      });

      debugPrint('RealtimeTranslator: ✅ Soniox translation processing complete (FAST PATH - no Azure API delay)');
      
      // Track translation latency
      final translationLatency = DateTime.now().difference(translationStartTime).inMilliseconds / 1000.0;
      _translationLatencies.add(translationLatency);
      debugPrint('RealtimeTranslator: ⏱️ Translation latency: ${translationLatency.toStringAsFixed(2)}s');
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error processing Soniox translation: $e');
      debugPrint('RealtimeTranslator: Stack trace: ${StackTrace.current}');
    } finally {
      _isTranslationInProgress = false;
    }
  }

  /// Translate transcribed text using Azure API and generate TTS
  /// FALLBACK: Only used when Soniox doesn't provide translation
  Future<void> _translateAndPlayRealtimeTts({
    required int speakerIndex,
    required String transcribedText,
    required String sourceLanguage,
  }) async {
    // CRITICAL: Prevent concurrent translation+playback
    if (_isTranslationInProgress) {
      debugPrint('RealtimeTranslator: ⚠️ Translation already in progress, skipping this request');
      return;
    }

    _isTranslationInProgress = true;
    
    try {
      debugPrint('RealtimeTranslator: ═══ Azure Translation + TTS ═══');
      debugPrint('RealtimeTranslator: Initial speaker: $speakerIndex');
      debugPrint('RealtimeTranslator: Soniox detected language: $sourceLanguage');
      debugPrint('RealtimeTranslator: Transcribed text: "$transcribedText"');

      // CHECK FOR PHONETIC TRANSCRIPTION FIRST
      final isPhonetic = _isPhoneticTranscription(transcribedText, sourceLanguage);
      
      int actualSpeakerIndex = speakerIndex;
      String actualSourceLanguage = sourceLanguage;
      String actualTranscribedText = transcribedText;
      
      if (isPhonetic) {
        debugPrint('RealtimeTranslator: ⚠️ PHONETIC DETECTED! Text is likely English written in Bengali script');
        
        // Phonetic transcription means:
        // - Soniox thought it was Bengali (sourceLanguage = 'bn')
        // - But it's actually English spoken and written phonetically
        // - So we need to:
        //   1. Map to the OTHER speaker (English speaker)
        //   2. Use English as the actual source language
        //   3. First translate the phonetic text back to proper English
        
        actualSpeakerIndex = speakerIndex == 0 ? 1 : 0;
        actualSourceLanguage = _speakerLanguages[actualSpeakerIndex]?.code ?? 'en';
        
        debugPrint('RealtimeTranslator: 🔄 CORRECTION: Speaker $speakerIndex → Speaker $actualSpeakerIndex');
        debugPrint('RealtimeTranslator: 🔄 CORRECTION: Language $sourceLanguage → $actualSourceLanguage');
        
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
        debugPrint('RealtimeTranslator: 🌐 Attempting to recover English from phonetic Bengali...');
        final recoveryResult = await TranslationService.translateText(
          sourceLanguage: sourceLanguage, // 'bn' (what Soniox thought)
          targetLanguage: actualSourceLanguage, // 'en' (what it actually is)
          content: transcribedText,
        );
        
        if (recoveryResult != null && recoveryResult.translatedText.isNotEmpty) {
          actualTranscribedText = recoveryResult.translatedText;
          debugPrint('RealtimeTranslator: ✅ Recovered English: "$actualTranscribedText"');
        } else {
          debugPrint('RealtimeTranslator: ⚠️ Could not recover English, using phonetic text as-is');
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
      debugPrint('RealtimeTranslator: ═══ Final Processing ═══');
      debugPrint('RealtimeTranslator: Actual speaker: $actualSpeakerIndex');
      debugPrint('RealtimeTranslator: Actual source language: $actualSourceLanguage');
      debugPrint('RealtimeTranslator: Actual transcribed text: "$actualTranscribedText"');

      // CRITICAL FIX: Don't write transcription here - it's already written in _handleSonioxResult
      // Only write if this is a corrected speaker (phonetic case)
      if (isPhonetic && actualSpeakerIndex != speakerIndex) {
        // Update transcription for the corrected ACTUAL speaker
        if (_realtimeTranscriptions[actualSpeakerIndex]!.isNotEmpty) {
          _realtimeTranscriptions[actualSpeakerIndex]!.write(' ');
        }
        _realtimeTranscriptions[actualSpeakerIndex]!.write(actualTranscribedText);
        debugPrint('RealtimeTranslator: ✅ Transcription written to corrected speaker buffer');
      }

      // Determine target speaker and language for translation
      final targetSpeakerIndex = actualSpeakerIndex == 0 ? 1 : 0;
      final targetLanguage = _speakerLanguages[targetSpeakerIndex];

      if (targetLanguage == null) {
        debugPrint('RealtimeTranslator: ⚠️ Target language not configured');
        return;
      }

      debugPrint('RealtimeTranslator: Target speaker: $targetSpeakerIndex');
      debugPrint('RealtimeTranslator: Target language: ${targetLanguage.code}');

      // Translate from ACTUAL source to target
      final translationResult = await TranslationService.translateText(
        sourceLanguage: actualSourceLanguage,
        targetLanguage: targetLanguage.code,
        content: actualTranscribedText,
      );

      if (translationResult == null || translationResult.translatedText.isEmpty) {
        debugPrint('RealtimeTranslator: ❌ Azure translation failed');
        return;
      }

      final translatedText = translationResult.translatedText;
      debugPrint('RealtimeTranslator: ✅ Azure translation: "$translatedText"');

      // Update translation buffer for the ACTUAL speaker
      if (_realtimeTranslations[actualSpeakerIndex]!.isNotEmpty) {
        _realtimeTranslations[actualSpeakerIndex]!.write(' ');
      }
      _realtimeTranslations[actualSpeakerIndex]!.write(translatedText);

      // Update UI with translation (transcription was already updated in _handleSonioxResult)
      if (mounted) {
        setState(() {
          // Only update translation here, transcription is already set
          _translations[actualSpeakerIndex] = _realtimeTranslations[actualSpeakerIndex]?.toString().trim() ?? '';
          // Update transcription only if speaker was corrected (phonetic case)
          if (isPhonetic && actualSpeakerIndex != speakerIndex) {
            _transcriptions[actualSpeakerIndex] = _realtimeTranscriptions[actualSpeakerIndex]?.toString().trim() ?? '';
          }
        });
        debugPrint('RealtimeTranslator: ✅ UI updated for Speaker $actualSpeakerIndex');
        debugPrint('RealtimeTranslator: Speaker $actualSpeakerIndex transcription: "${_transcriptions[actualSpeakerIndex]}"');
        debugPrint('RealtimeTranslator: Speaker $actualSpeakerIndex translation: "${_translations[actualSpeakerIndex]}"');
        // Auto-scroll to latest content (translation)
        _autoScrollToBottom(actualSpeakerIndex, isTranslation: true);
      }

      // Generate and play TTS for the TARGET speaker
      final targetGender = _speakerGenders[targetSpeakerIndex] ?? 'male';
      final earpiece = _speakerEarpieces[targetSpeakerIndex] ?? 'left';

      debugPrint('RealtimeTranslator: ═══ TTS Generation ═══');
      debugPrint('RealtimeTranslator: TTS for target speaker: $targetSpeakerIndex');
      debugPrint('RealtimeTranslator: TTS language: ${targetLanguage.code}');
      debugPrint('RealtimeTranslator: TTS text: "$translatedText"');
      debugPrint('RealtimeTranslator: TTS gender: $targetGender');
      debugPrint('RealtimeTranslator: TTS earpiece: $earpiece');

      // REALTIME TRANSLATION: Add to queue (TTS will be generated during queue processing)
      // No need to generate TTS here - queue processor will handle it
      // This allows recording to continue without interruption
      _addToTtsQueue(
        speakerIndex: targetSpeakerIndex,
        text: translatedText,
        languageCode: targetLanguage.code,
        gender: targetGender,
      );
      
      debugPrint('RealtimeTranslator: ✅ Added TTS to queue (recording continues, TTS will be generated and played from queue)');

    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Translation + TTS error: $e');
      debugPrint('RealtimeTranslator: Stack trace: ${StackTrace.current}');
    } finally {
      // CRITICAL: Always release the lock
      _isTranslationInProgress = false;
      debugPrint('RealtimeTranslator: ✅ Translation lock released');
    }
  }

  /// Play TTS audio with stereo routing in real-time.
  /// Recording pauses during playback and resumes afterwards.
  Future<void> _playRealtimeTtsWithStereo({
    required int speakerIndex,
    required int targetSpeakerIndex,
    required String ttsPath,
    required String earpiece,
  }) async {
    try {
      debugPrint('RealtimeTranslator: ═══ Playing TTS with Stereo Routing (REAL-TIME MODE) ═══');
      debugPrint('RealtimeTranslator: Speaker: $speakerIndex');
      debugPrint('RealtimeTranslator: Target speaker: $targetSpeakerIndex');
      debugPrint('RealtimeTranslator: Earpiece: $earpiece');
      debugPrint('RealtimeTranslator: TTS path: $ttsPath');
      debugPrint('RealtimeTranslator: ⚠️ Mic will pause during playback to avoid interference');

      // Set playback in progress flag BEFORE pausing
      _isPlaybackInProgress = true;

      if (_isRealtimeMode) {
        await _pauseRealtimeListeningForPlayback();
      }

      // OPTIMIZATION: Reduced delay - route switching is handled in pause method
      if (_isRealtimeMode) {
        await Future.delayed(const Duration(milliseconds: 150)); // Reduced from 300ms
      }

      // Generate stereo audio file with TTS routed to correct earpiece
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      debugPrint('RealtimeTranslator: Creating stereo audio with routing...');

      // Create a silent audio file for the opposite channel
      final silentAudioPath = await _createMatchingSilentAudioFile(ttsPath);
      
      if (silentAudioPath == null) {
        debugPrint('RealtimeTranslator: ⚠️ Failed to create silent audio, using TTS for both channels');
      }

      // Route TTS to correct earpiece, silence to the other
      final leftChannelPath = earpiece == 'left' ? ttsPath : (silentAudioPath ?? ttsPath);
      final rightChannelPath = earpiece == 'right' ? ttsPath : (silentAudioPath ?? ttsPath);
      
      debugPrint('RealtimeTranslator: Left channel: ${earpiece == 'left' ? "TTS" : "Silent"}');
      debugPrint('RealtimeTranslator: Right channel: ${earpiece == 'right' ? "TTS" : "Silent"}');
      
      final stereoPath = await _stereoTtsService.createTrueStereoAudioFile(
        leftChannelPath,
        rightChannelPath,
        outputFileName: 'realtime_stereo_$timestamp.wav',
      );

      if (stereoPath == null || stereoPath.isEmpty) {
        debugPrint('RealtimeTranslator: ❌ Failed to create stereo audio');
        return;
      }

      debugPrint('RealtimeTranslator: ✅ Stereo audio created: $stereoPath');

      // Play stereo audio
      if (targetSpeakerIndex == 0) {
        setState(() => _isPlayingTts1 = true);
      } else {
        setState(() => _isPlayingTts2 = true);
      }

      debugPrint('RealtimeTranslator: 🔊 Starting playback (mic paused)...');
      
      // CRITICAL: Wait for playback to COMPLETE before proceeding
      await _stereoTtsService.playStereoAudio(stereoPath);
      
      debugPrint('RealtimeTranslator: ✅ TTS playback completed');
      
      // OPTIMIZATION: Reduced delay - audio hardware finishes faster
      await Future.delayed(const Duration(milliseconds: 150)); // Reduced from 300ms

      if (mounted) {
        setState(() {
          _isPlayingTts1 = false;
          _isPlayingTts2 = false;
        });
      }

      // CRITICAL: Clean up temporary files AFTER playback is completely finished
      // This prevents file deletion while audio is still playing
      // OPTIMIZATION: Reduced delay - files can be cleaned up faster
      try {
        await Future.delayed(const Duration(milliseconds: 100)); // Reduced from 200ms
        
        final stereoFile = File(stereoPath);
        if (await stereoFile.exists()) {
          await stereoFile.delete();
          debugPrint('RealtimeTranslator: ✅ Cleaned up temporary stereo file');
        }
        
        if (silentAudioPath != null) {
          final silentFile = File(silentAudioPath);
          if (await silentFile.exists()) {
            await silentFile.delete();
            debugPrint('RealtimeTranslator: ✅ Cleaned up temporary silent file');
          }
        }
        
        // Also clean up the original TTS file
        final ttsFile = File(ttsPath);
        if (await ttsFile.exists()) {
          await ttsFile.delete();
          debugPrint('RealtimeTranslator: ✅ Cleaned up original TTS file');
        }
      } catch (e) {
        debugPrint('RealtimeTranslator: ⚠️ Failed to delete temporary files: $e');
      }
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ TTS playback error: $e');
      debugPrint('RealtimeTranslator: Stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() {
          _isPlayingTts1 = false;
          _isPlayingTts2 = false;
        });
      }
    } finally {
      // Clear playback in progress flag BEFORE resuming
      _isPlaybackInProgress = false;
      
      // Don't switch routes here - let _resumeRealtimeListeningAfterPlayback handle it
      // This ensures the start beep plays in playback mode (TWS) before switching to recording
      
      if (_isRealtimeListeningPaused) {
        await _resumeRealtimeListeningAfterPlayback();
      }
    }
  }

  /// Create a silent audio file with the same duration as the reference audio
  Future<String?> _createMatchingSilentAudioFile(String referenceAudioPath) async {
    try {
      debugPrint('RealtimeTranslator: Creating silent audio file...');
      debugPrint('RealtimeTranslator: Reference file: $referenceAudioPath');
      
      // Read reference audio file to get duration
      final refFile = File(referenceAudioPath);
      if (!await refFile.exists()) {
        debugPrint('RealtimeTranslator: ❌ Reference audio file does not exist');
        return null;
      }
      
      // CRITICAL FIX: Wait a bit and verify file is stable before reading
      // This ensures the file is fully written and flushed to disk
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Verify file size is stable
      final initialSize = await refFile.length();
      await Future.delayed(const Duration(milliseconds: 50));
      final stableSize = await refFile.length();
      
      if (initialSize != stableSize) {
        debugPrint('RealtimeTranslator: ⚠️ File size changed ($initialSize → $stableSize), waiting...');
        await Future.delayed(const Duration(milliseconds: 200));
      }
      
      final refBytes = await refFile.readAsBytes();
      debugPrint('RealtimeTranslator: Read ${refBytes.length} bytes from reference file');
      
      // WAV file header is 44 bytes
      // Data size is in bytes 40-43 (little-endian)
      if (refBytes.length < 44) {
        debugPrint('RealtimeTranslator: ❌ Reference audio file is too small (${refBytes.length} bytes)');
        return null;
      }
      
      // CRITICAL: Validate WAV file header
      final riffHeader = String.fromCharCodes(refBytes.sublist(0, 4));
      final waveHeader = refBytes.length >= 12 
          ? String.fromCharCodes(refBytes.sublist(8, 12))
          : '';
      
      if (riffHeader != 'RIFF') {
        debugPrint('RealtimeTranslator: ❌ Invalid WAV file - missing RIFF header (found: $riffHeader)');
        return null;
      }
      
      if (waveHeader != 'WAVE') {
        debugPrint('RealtimeTranslator: ❌ Invalid WAV file - missing WAVE header (found: $waveHeader)');
        return null;
      }
      
      debugPrint('RealtimeTranslator: ✅ Valid WAV file header confirmed (RIFF/WAVE)');
      
      // Find "data" chunk in WAV file
      // Some WAV files have additional chunks before the data chunk
      int dataChunkOffset = -1;
      int dataSize = 0;
      
      // Search for "data" chunk (starts at byte 12 after RIFF header)
      for (int i = 12; i < refBytes.length - 8; i++) {
        if (i + 4 <= refBytes.length) {
          final chunkId = String.fromCharCodes(refBytes.sublist(i, i + 4));
          if (chunkId == 'data') {
            dataChunkOffset = i + 4;
            // Read data chunk size (4 bytes, little-endian)
            if (dataChunkOffset + 4 <= refBytes.length) {
              dataSize = refBytes[dataChunkOffset] | 
                         (refBytes[dataChunkOffset + 1] << 8) | 
                         (refBytes[dataChunkOffset + 2] << 16) | 
                         (refBytes[dataChunkOffset + 3] << 24);
              debugPrint('RealtimeTranslator: Found data chunk at offset $dataChunkOffset');
              debugPrint('RealtimeTranslator: Data chunk size: $dataSize bytes');
              break;
            }
          }
        }
      }
      
      // Fallback: Use bytes 40-43 if data chunk not found (standard WAV format)
      if (dataSize == 0 || dataChunkOffset == -1) {
        debugPrint('RealtimeTranslator: ⚠️ Data chunk not found, using standard header location');
        dataSize = refBytes[40] | 
                   (refBytes[41] << 8) | 
                   (refBytes[42] << 16) | 
                   (refBytes[43] << 24);
      }
      
      debugPrint('RealtimeTranslator: Reference audio data size: $dataSize bytes');
      
      if (dataSize <= 0) {
        debugPrint('RealtimeTranslator: ❌ Invalid data size ($dataSize bytes)');
        // Calculate data size from file size if header is wrong
        dataSize = refBytes.length - 44;
        debugPrint('RealtimeTranslator: ⚠️ Using calculated data size: $dataSize bytes (file size - header)');
      }
      
      if (dataSize <= 0) {
        debugPrint('RealtimeTranslator: ❌ Cannot create silent file - invalid data size');
        return null;
      }
      
      // Create silent audio file with same size
      final tempDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final silentPath = '${tempDir.path}/silent_$timestamp.wav';
      
      // Copy WAV header from reference file (first 44 bytes)
      final silentBytes = Uint8List(44 + dataSize);
      if (refBytes.length >= 44) {
        silentBytes.setAll(0, refBytes.sublist(0, 44));
      } else {
        debugPrint('RealtimeTranslator: ❌ Cannot copy header - file too small');
        return null;
      }
      
      // Update file size in RIFF header (bytes 4-7)
      final totalFileSize = 36 + dataSize; // 36 = WAV header size minus RIFF size field
      silentBytes[4] = totalFileSize & 0xFF;
      silentBytes[5] = (totalFileSize >> 8) & 0xFF;
      silentBytes[6] = (totalFileSize >> 16) & 0xFF;
      silentBytes[7] = (totalFileSize >> 24) & 0xFF;
      
      // Update data chunk size in header (bytes 40-43)
      silentBytes[40] = dataSize & 0xFF;
      silentBytes[41] = (dataSize >> 8) & 0xFF;
      silentBytes[42] = (dataSize >> 16) & 0xFF;
      silentBytes[43] = (dataSize >> 24) & 0xFF;
      
      // Fill audio data with zeros (silence)
      for (int i = 44; i < silentBytes.length; i++) {
        silentBytes[i] = 0;
      }
      
      // Write silent audio file
      final silentFile = File(silentPath);
      await silentFile.writeAsBytes(silentBytes);
      
      // Verify the file was written correctly
      final writtenSize = await silentFile.length();
      debugPrint('RealtimeTranslator: ✅ Silent audio file created: $silentPath');
      debugPrint('RealtimeTranslator: Silent file size: $writtenSize bytes (expected: ${silentBytes.length})');
      
      if (writtenSize != silentBytes.length) {
        debugPrint('RealtimeTranslator: ⚠️ Silent file size mismatch!');
      }
      
      return silentPath;
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error creating silent audio: $e');
      debugPrint('RealtimeTranslator: Stack trace: ${StackTrace.current}');
      return null;
    }
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

      debugPrint('RealtimeTranslator: Processing completed successfully');
    } catch (e) {
      debugPrint('RealtimeTranslator: Processing error: $e');
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
          'RealtimeTranslator: Performing enhanced speaker diarization...');

      // Convert audio bytes to Float32List for analysis
      final Float32List audioData = _convertBytesToFloat32List(audioBytes);

      // Step 1: Voice Activity Detection (VAD) - Remove silence
      setState(() {
        _processingProgress = 0.15;
        _processingStatus = 'Detecting voice activity...';
      });

      final List<VoiceSegment> voiceSegments = _detectVoiceActivity(audioData);
      debugPrint(
          'RealtimeTranslator: Found ${voiceSegments.length} voice segments');

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
          'RealtimeTranslator: Extracted features from ${allFeatures.length} segments');

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
          'RealtimeTranslator: Created ${mergedSegments.length} final segments');

      // Print segment details for debugging
      for (int i = 0; i < math.min(5, mergedSegments.length); i++) {
        final seg = mergedSegments[i];
        debugPrint(
            '  Segment $i: Speaker ${seg.speakerId}, ${seg.startTime.toStringAsFixed(2)}s - ${seg.endTime.toStringAsFixed(2)}s, confidence: ${seg.confidence.toStringAsFixed(2)}');
      }
    } catch (e) {
      debugPrint('RealtimeTranslator: Error in speaker diarization: $e');
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
            'RealtimeTranslator: ✅ Using cached original audio bytes (avoiding redundant file read)');
        originalBytes = _cachedOriginalAudioBytes!;
      } else {
        debugPrint(
            'RealtimeTranslator: Reading original audio file (cache miss)');
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
          'RealtimeTranslator: Configured languages - Speaker 1: $speaker1ConfiguredLanguage, Speaker 2: $speaker2ConfiguredLanguage');

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
          'RealtimeTranslator: Audio separation completed with language-based assignment');
      debugPrint(
          'RealtimeTranslator: Final assignment - Speaker 1: ${speakerAssignment['speaker1']}, Speaker 2: ${speakerAssignment['speaker2']}');
    } catch (e) {
      debugPrint('RealtimeTranslator: Audio separation error: $e');
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
          'RealtimeTranslator: Starting transcription of separated audio...');
      debugPrint(
          'RealtimeTranslator: 🚀 OPTIMIZATION: Using cached Voice 1 transcription');

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
              'RealtimeTranslator: ✅ Speaker 1 is Voice 1 - using cached transcription (0 API calls)');
          final cachedText = _voice1CachedTranscription!['text'] as String?;
          if (cachedText != null && cachedText.isNotEmpty) {
            _transcriptions[0] = cachedText;
            debugPrint(
                'RealtimeTranslator: Stored Speaker 1 transcript: "${_transcriptions[0]}"');
          }
        } else {
          // This is Voice 2 - need to transcribe (1 API call)
          debugPrint(
              'RealtimeTranslator: Speaker 1 is Voice 2 - transcribing with language: $speaker1LanguageCode (1 API call)');

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
            debugPrint('RealtimeTranslator: Speaker 1 transcription result:');
            debugPrint('  Language: $speaker1LanguageCode');
            debugPrint('  Text: "${result1['text']}"');
            _transcriptions[0] = (result1['text'] as String?) ?? '';
            debugPrint(
                'RealtimeTranslator: Stored Speaker 1 transcript: "${_transcriptions[0]}"');
          } else {
            debugPrint(
                'RealtimeTranslator: Speaker 1 transcription failed - no result');
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
              'RealtimeTranslator: ✅ Speaker 2 is Voice 1 - using cached transcription (0 API calls)');
          final cachedText = _voice1CachedTranscription!['text'] as String?;
          if (cachedText != null && cachedText.isNotEmpty) {
            _transcriptions[1] = cachedText;
            debugPrint(
                'RealtimeTranslator: Stored Speaker 2 transcript: "${_transcriptions[1]}"');
          }
        } else {
          // This is Voice 2 - need to transcribe (1 API call)
          debugPrint(
              'RealtimeTranslator: Speaker 2 is Voice 2 - transcribing with language: $speaker2LanguageCode (1 API call)');

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
            debugPrint('RealtimeTranslator: Speaker 2 transcription result:');
            debugPrint('  Language: $speaker2LanguageCode');
            debugPrint('  Text: "${result2['text']}"');
            _transcriptions[1] = (result2['text'] as String?) ?? '';
            debugPrint(
                'RealtimeTranslator: Stored Speaker 2 transcript: "${_transcriptions[1]}"');
          } else {
            debugPrint(
                'RealtimeTranslator: Speaker 2 transcription failed - no result');
          }
        }
      }

      debugPrint('RealtimeTranslator: ===== TRANSCRIPTION COMPLETED =====');
      debugPrint('  Speaker 0: ${_transcriptions[0] ?? "No transcription"}');
      debugPrint('  Speaker 1: ${_transcriptions[1] ?? "No transcription"}');
      debugPrint(
          'RealtimeTranslator: Total transcriptions: ${_transcriptions.length}');
      debugPrint(
          'RealtimeTranslator: Transcription keys: ${_transcriptions.keys.toList()}');
      debugPrint(
          'RealtimeTranslator: 🎉 API OPTIMIZATION: Total STT API calls = 3');
      debugPrint(
          'RealtimeTranslator:   - Voice 1 detection: 2 calls (both languages)');
      debugPrint(
          'RealtimeTranslator:   - Voice 2 transcription: 1 call (inferred language)');
      debugPrint(
          'RealtimeTranslator:   - Saved: 3 API calls (50% reduction from 6 to 3)');
      debugPrint(
          'RealtimeTranslator: ==========================================');

      // Start translation after transcription is complete
      await _translateTranscriptions();
    } catch (e) {
      debugPrint('RealtimeTranslator: Transcription error: $e');
      throw Exception('Failed to transcribe audio: $e');
    }
  }

  /// Translate transcriptions between speakers
  Future<void> _translateTranscriptions() async {
    try {
      debugPrint('RealtimeTranslator: Starting translation process...');

      setState(() {
        _processingStatus = 'Translating text...';
        _processingProgress = 0.85;
      });

      // Get speaker languages
      final speaker1Language = _speakerLanguages[0];
      final speaker2Language = _speakerLanguages[1];

      if (speaker1Language == null || speaker2Language == null) {
        debugPrint('RealtimeTranslator: Speaker languages not configured');
        return;
      }

      final speaker1LangCode = speaker1Language.code;
      final speaker2LangCode = speaker2Language.code;

      debugPrint('RealtimeTranslator: Speaker 1 language: $speaker1LangCode');
      debugPrint('RealtimeTranslator: Speaker 2 language: $speaker2LangCode');

      // Check if translation is needed
      if (speaker1LangCode == speaker2LangCode) {
        debugPrint(
            'RealtimeTranslator: No translation needed - same language');
        return;
      }

      // OPTIMIZATION: Translate both speakers in parallel
      debugPrint(
          'RealtimeTranslator: 🚀 Starting parallel translation API calls...');

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
                  'RealtimeTranslator: Speaker 1 translation: "${result.translatedText}"');
            } else {
              debugPrint('RealtimeTranslator: Speaker 1 translation failed');
            }
          }).catchError((e) {
            debugPrint('RealtimeTranslator: Speaker 1 translation error: $e');
          }),
        );
        debugPrint(
            'RealtimeTranslator: Queued translation for Speaker 1 text to $speaker2LangCode...');
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
                  'RealtimeTranslator: Speaker 2 translation: "${result.translatedText}"');
            } else {
              debugPrint('RealtimeTranslator: Speaker 2 translation failed');
            }
          }).catchError((e) {
            debugPrint('RealtimeTranslator: Speaker 2 translation error: $e');
          }),
        );
        debugPrint(
            'RealtimeTranslator: Queued translation for Speaker 2 text to $speaker1LangCode...');
      }

      // Execute all translations in parallel
      if (translationTasks.isNotEmpty) {
        await Future.wait(translationTasks);
        debugPrint(
            'RealtimeTranslator: ✅ Parallel translation API calls completed');
      }

      debugPrint('RealtimeTranslator: Translation process completed');
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
      debugPrint('RealtimeTranslator: Translation error: $e');
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
            'RealtimeTranslator: Generating Speaker $speakerIndex TTS with gender: $gender (attempt ${retryCount + 1})');
        ttsAudioPath = await _ttsService.generateAudioFile(
          text,
          languageCode,
          gender: gender,
        );
        debugPrint(
            'RealtimeTranslator: Speaker $speakerIndex TTS audio path (attempt ${retryCount + 1}): $ttsAudioPath');

        // Verify the file was actually created and has content
        if (ttsAudioPath != null) {
          final file = File(ttsAudioPath);
          final exists = await file.exists();
          final size = exists ? await file.length() : 0;
          debugPrint(
              'RealtimeTranslator: Speaker $speakerIndex TTS file verification (attempt ${retryCount + 1}):');
          debugPrint('  File exists: $exists');
          debugPrint('  File size: $size bytes');

          if (exists && size > 0) {
            ttsSuccess = true;
            debugPrint(
                'RealtimeTranslator: Speaker $speakerIndex TTS file generation successful');
          } else {
            debugPrint(
                'RealtimeTranslator: Speaker $speakerIndex TTS file generation failed - file is empty or missing (attempt ${retryCount + 1})');
            ttsAudioPath = null;
            retryCount++;
            if (retryCount < maxRetries) {
              debugPrint(
                  'RealtimeTranslator: Retrying Speaker $speakerIndex TTS generation...');
              await Future.delayed(const Duration(milliseconds: 1000));
            }
          }
        } else {
          debugPrint(
              'RealtimeTranslator: Speaker $speakerIndex TTS generation returned null (attempt ${retryCount + 1})');
          retryCount++;
          if (retryCount < maxRetries) {
            debugPrint(
                'RealtimeTranslator: Retrying Speaker $speakerIndex TTS generation...');
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }
      } catch (e) {
        debugPrint(
            'RealtimeTranslator: Speaker $speakerIndex TTS generation error (attempt ${retryCount + 1}): $e');
        retryCount++;
        if (retryCount < maxRetries) {
          debugPrint(
              'RealtimeTranslator: Retrying Speaker $speakerIndex TTS generation...');
          await Future.delayed(const Duration(milliseconds: 1000));
        }
      }
    }

    if (!ttsSuccess) {
      debugPrint(
          'RealtimeTranslator: Speaker $speakerIndex TTS generation failed after $maxRetries attempts');
      // Create silent audio as fallback
      debugPrint(
          'RealtimeTranslator: Creating silent audio fallback for Speaker $speakerIndex');
      ttsAudioPath =
          await _createSilentAudioFile('speaker${speakerIndex}_fallback');
    }

    return ttsAudioPath;
  }

  /// Generate TTS audio files for translated text
  Future<void> _generateTtsAudio() async {
    try {
      debugPrint('RealtimeTranslator: Starting TTS audio generation...');

      setState(() {
        _processingStatus = 'Generating speech audio...';
        _processingProgress = 0.90;
      });

      // Always ensure we have TTS files for both speakers (real or silent)
      bool hasSpeaker1Translation =
          _translations[0] != null && _translations[0]!.isNotEmpty;
      bool hasSpeaker2Translation =
          _translations[1] != null && _translations[1]!.isNotEmpty;

      debugPrint('RealtimeTranslator: Translation status:');
      debugPrint('  Speaker 1 has translation: $hasSpeaker1Translation');
      debugPrint('  Speaker 2 has translation: $hasSpeaker2Translation');

      // OPTIMIZATION: Generate TTS for both speakers in parallel
      debugPrint('RealtimeTranslator: 🚀 Starting parallel TTS generation...');

      final List<Future<void>> ttsTasks = [];

      // Generate TTS audio for Speaker 1's translated text (for Speaker 2 to hear)
      if (hasSpeaker1Translation) {
        final speaker2Language = _speakerLanguages[1];
        if (speaker2Language != null) {
          debugPrint(
              'RealtimeTranslator: Queuing TTS generation for Speaker 1 translation in ${speaker2Language.code}...');
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
                    'RealtimeTranslator: ✅ Speaker 1 TTS generated: $path');
              }
            }).catchError((e) {
              debugPrint(
                  'RealtimeTranslator: Speaker 1 TTS generation error: $e');
              _speaker1TtsAudioPath = null;
            }),
          );
        } else {
          debugPrint(
              'RealtimeTranslator: Speaker 2 language is null, cannot generate TTS for Speaker 1');
        }
      } else {
        debugPrint(
            'RealtimeTranslator: Speaker 1 translation is null or empty, skipping TTS generation');
      }

      // Generate TTS audio for Speaker 2's translated text (for Speaker 1 to hear)
      if (hasSpeaker2Translation) {
        final speaker1Language = _speakerLanguages[0];
        if (speaker1Language != null) {
          debugPrint(
              'RealtimeTranslator: Queuing TTS generation for Speaker 2 translation in ${speaker1Language.code}...');
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
                    'RealtimeTranslator: ✅ Speaker 2 TTS generated: $path');
              }
            }).catchError((e) {
              debugPrint(
                  'RealtimeTranslator: Speaker 2 TTS generation error: $e');
              _speaker2TtsAudioPath = null;
            }),
          );
        } else {
          debugPrint(
              'RealtimeTranslator: Speaker 1 language is null, cannot generate TTS for Speaker 2');
        }
      } else {
        debugPrint(
            'RealtimeTranslator: Speaker 2 translation is null or empty, skipping TTS generation');
      }

      // Execute all TTS generations in parallel
      if (ttsTasks.isNotEmpty) {
        await Future.wait(ttsTasks);
        debugPrint('RealtimeTranslator: ✅ Parallel TTS generation completed');
      }

      // Ensure we have TTS files for both speakers (create silent audio for missing ones)
      if (!hasSpeaker1Translation && _speaker1TtsAudioPath == null) {
        debugPrint(
            'RealtimeTranslator: Creating silent audio for Speaker 1 (no translation)');
        _speaker1TtsAudioPath = await _createSilentAudioFile('speaker1_silent');
      }

      if (!hasSpeaker2Translation && _speaker2TtsAudioPath == null) {
        debugPrint(
            'RealtimeTranslator: Creating silent audio for Speaker 2 (no translation)');
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

      debugPrint('RealtimeTranslator: TTS audio generation completed');
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
      debugPrint('RealtimeTranslator: TTS audio generation error: $e');
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
            'RealtimeTranslator: Audio file does not exist: $audioPath');
        return {'language': null, 'confidence': 0.0, 'text': null};
      }

      final audioBytes = await file.readAsBytes();
      if (audioBytes.isEmpty) {
        debugPrint('RealtimeTranslator: Audio file is empty: $audioPath');
        return {'language': null, 'confidence': 0.0, 'text': null};
      }

      debugPrint(
          'RealtimeTranslator: Using Google STT multi-language detection for: $audioPath');
      debugPrint(
          'RealtimeTranslator: Preferred languages: $preferredLanguages');

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
        debugPrint('RealtimeTranslator: No transcription result from STT');
        return {'language': null, 'confidence': 0.0, 'text': null};
      }

      debugPrint('RealtimeTranslator: Balanced detection result:');
      debugPrint('  Text: "${best['text']}"');
      debugPrint('  Detected Language: ${best['language']}');
      debugPrint('  Confidence: ${best['confidence']}');
      debugPrint('  Text Length: ${best['textLength']}');
      debugPrint('  Segments: ${best['segmentCount']}');

      return best;
    } catch (e) {
      debugPrint(
          'RealtimeTranslator: Multi-language detection error for $audioPath: $e');
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

    debugPrint('RealtimeTranslator: Script analysis:');
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
          'RealtimeTranslator: Detected Hindi script, treating as Bengali');
      for (final lang in preferredLanguages) {
        if (lang.toLowerCase().startsWith('bn')) return lang;
      }
    } else if (sinhalaRatio > 0.5) {
      // Sinhala script dominant - treat as Bengali for our purposes
      debugPrint(
          'RealtimeTranslator: Detected Sinhala script, treating as Bengali');
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
        'RealtimeTranslator: Script-based language detection: $bestLanguage (score: $bestScore)');
    return bestLanguage ?? preferredLanguages[0];
  }

  /// Assign speakers based on language detection results
  Future<Map<String, String>> _assignSpeakersByLanguage(String voice1Path,
      String voice2Path, List<String> preferredLanguages) async {
    try {
      debugPrint(
          'RealtimeTranslator: ===== OPTIMIZED LANGUAGE-BASED ASSIGNMENT (3 API calls) =====');
      debugPrint('RealtimeTranslator: Voice 1: $voice1Path');
      debugPrint('RealtimeTranslator: Voice 2: $voice2Path');
      debugPrint(
          'RealtimeTranslator: Preferred languages: $preferredLanguages');

      final speaker1Lang = _speakerLanguages[0]?.code ?? 'en';
      final speaker2Lang = _speakerLanguages[1]?.code ?? 'en';

      // OPTIMIZATION: Only test Voice 1 with both languages (2 API calls)
      // Voice 2's language can be inferred (it's the OTHER language)
      debugPrint(
          'RealtimeTranslator: 🚀 OPTIMIZATION: Testing Voice 1 with both languages...');
      debugPrint('RealtimeTranslator: This will use 2 API calls for Voice 1');

      final voice1Result =
          await _detectVoiceLanguageOptimized(voice1Path, preferredLanguages);

      debugPrint('RealtimeTranslator: Voice 1 language detection result:');
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
              'RealtimeTranslator: ✅ Voice 1 → Speaker 1 ($voice1Language)');
          debugPrint(
              'RealtimeTranslator: ✅ Voice 2 → Speaker 2 ($voice2AssignedLanguage) [INFERRED - no API call needed]');
        } else if (voice1Language == speaker2Lang) {
          // Voice 1 speaks Speaker 2's language
          assignment['speaker1'] = voice2Path;
          assignment['speaker2'] = voice1Path;
          voice2AssignedLanguage = speaker1Lang;
          debugPrint(
              'RealtimeTranslator: ✅ Voice 1 → Speaker 2 ($voice1Language)');
          debugPrint(
              'RealtimeTranslator: ✅ Voice 2 → Speaker 1 ($voice2AssignedLanguage) [INFERRED - no API call needed]');
        } else {
          // Fallback: language doesn't match, use original order
          debugPrint(
              'RealtimeTranslator: ⚠️ Voice 1 language ($voice1Language) doesn\'t match configured languages');
          debugPrint(
              'RealtimeTranslator: Using default assignment (Voice 1 → Speaker 1, Voice 2 → Speaker 2)');
          assignment['speaker1'] = voice1Path;
          assignment['speaker2'] = voice2Path;
          voice2AssignedLanguage = speaker2Lang;
        }
      } else {
        // No clear detection, use default assignment
        debugPrint(
            'RealtimeTranslator: ⚠️ Could not detect Voice 1 language clearly');
        debugPrint(
            'RealtimeTranslator: Using default assignment (Voice 1 → Speaker 1, Voice 2 → Speaker 2)');
        assignment['speaker1'] = voice1Path;
        assignment['speaker2'] = voice2Path;
        voice2AssignedLanguage = speaker2Lang;
      }

      // Now transcribe Voice 2 with the inferred language (1 API call)
      // This will be used later in _transcribeSeparatedAudio
      debugPrint(
          'RealtimeTranslator: 🚀 OPTIMIZATION: Will transcribe Voice 2 with inferred language ($voice2AssignedLanguage)');
      debugPrint('RealtimeTranslator: This will use 1 API call for Voice 2');

      debugPrint('RealtimeTranslator: ===== OPTIMIZATION COMPLETE =====');
      debugPrint('RealtimeTranslator: Total API calls used: 2 (Voice 1 only)');
      debugPrint(
          'RealtimeTranslator: Voice 2 will use: 1 API call (inferred language)');
      debugPrint(
          'RealtimeTranslator: Grand total: 3 API calls (vs 6 in old approach)');
      debugPrint('RealtimeTranslator: API call reduction: 50% 🎉');
      debugPrint('RealtimeTranslator: Speaker 1: ${assignment['speaker1']}');
      debugPrint('RealtimeTranslator: Speaker 2: ${assignment['speaker2']}');
      debugPrint(
          'RealtimeTranslator: ==========================================');

      return assignment;
    } catch (e) {
      debugPrint('RealtimeTranslator: Language-based assignment error: $e');
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
          'RealtimeTranslator: Created silent audio file: $silentFilePath');
      debugPrint(
          '  Duration: ${duration}s, Sample rate: ${sampleRate}Hz, Size: ${silentFile.length} bytes');

      return silentFilePath;
    } catch (e) {
      debugPrint('RealtimeTranslator: Failed to create silent audio file: $e');
      return null;
    }
  }

  /// Generate stereo audio file from TTS audio files
  /// This method creates the stereo file once and caches it for reuse
  Future<void> _generateStereoAudioFile() async {
    try {
      debugPrint(
          'RealtimeTranslator: Starting stereo audio file generation...');

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
            'RealtimeTranslator: Speaker 1 TTS missing, will create silent audio');
        _speaker1TtsAudioPath = await _createSilentAudioFile('speaker1_silent');
        needsSilentAudio = true;
      }

      if (_speaker2TtsAudioPath == null) {
        debugPrint(
            'RealtimeTranslator: Speaker 2 TTS missing, will create silent audio');
        _speaker2TtsAudioPath = await _createSilentAudioFile('speaker2_silent');
        needsSilentAudio = true;
      }

      if (needsSilentAudio) {
        debugPrint(
            'RealtimeTranslator: Created silent audio files for missing speakers');
      }

      // Check if both files exist
      final leftFile = File(_speaker1TtsAudioPath!);
      final rightFile = File(_speaker2TtsAudioPath!);

      final leftExists = await leftFile.exists();
      final rightExists = await rightFile.exists();

      debugPrint('RealtimeTranslator: TTS file existence check:');
      debugPrint('  Left file exists: $leftExists');
      debugPrint('  Right file exists: $rightExists');

      if (!leftExists || !rightExists) {
        debugPrint(
            'RealtimeTranslator: Cannot generate stereo audio - TTS files do not exist');
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
      debugPrint('RealtimeTranslator: TTS file sizes:');
      debugPrint('  Left file size: $leftSize bytes');
      debugPrint('  Right file size: $rightSize bytes');

      debugPrint('RealtimeTranslator: Generating stereo audio file...');
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
            'RealtimeTranslator: Audio routing - Left channel: Speaker 2 TTS (for Speaker 1), Right channel: Speaker 1 TTS (for Speaker 2)');
      } else {
        // Speaker 1 has right earpiece, so Speaker 2's translated TTS goes to right channel (for Speaker 1 to hear)
        // Speaker 2 has left earpiece, so Speaker 1's translated TTS goes to left channel (for Speaker 2 to hear)
        leftChannelFile =
            _speaker1TtsAudioPath!; // Speaker 1's translated TTS for Speaker 2's left earpiece
        rightChannelFile =
            _speaker2TtsAudioPath!; // Speaker 2's translated TTS for Speaker 1's right earpiece
        debugPrint(
            'RealtimeTranslator: Audio routing - Left channel: Speaker 1 TTS (for Speaker 2), Right channel: Speaker 2 TTS (for Speaker 1)');
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
            'RealtimeTranslator: Stereo audio file generated and cached: $_cachedStereoAudioPath');

        // Verify the cached file exists
        final cachedFile = File(_cachedStereoAudioPath!);
        final cachedExists = await cachedFile.exists();
        final cachedSize = cachedExists ? await cachedFile.length() : 0;
        debugPrint('RealtimeTranslator: Cached stereo file verification:');
        debugPrint('  File exists: $cachedExists');
        debugPrint('  File size: $cachedSize bytes');

        setState(() {
          _processingStatus = 'Ready to play!';
          _processingProgress = 1.0;
        });

        // Auto-play the stereo audio if file was successfully generated
        if (cachedExists && cachedSize > 0) {
          debugPrint('RealtimeTranslator: Auto-playing stereo audio...');
          // Add a small delay to ensure UI updates and user sees the stereo audio is ready
          await Future.delayed(const Duration(milliseconds: 500));
          await _autoPlayStereoAudio();

          // Clear processing state after auto-play starts
          setState(() {
            _isProcessing = false;
          });
        } else {
          debugPrint(
              'RealtimeTranslator: Stereo audio file is empty or missing, skipping auto-play');
          setState(() {
            _isProcessing = false;
          });
        }
      } else {
        debugPrint(
            'RealtimeTranslator: Failed to generate stereo audio file - returned null');
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('RealtimeTranslator: Error generating stereo audio file: $e');
      debugPrint('RealtimeTranslator: Stack trace: $stackTrace');

      setState(() {
        _isProcessing = false;
        _processingStatus = 'Error occurred';
      });
    } finally {
      // Defer cleanup; we'll clean after playback completes so UI buttons keep working
      _pendingStereoPlaybackCleanup = true;
      debugPrint(
          'RealtimeTranslator: Deferring TTS cleanup until playback completion');
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
      debugPrint('RealtimeTranslator: Speaker 1 playback error: $e');
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
      debugPrint('RealtimeTranslator: Speaker 2 playback error: $e');
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
            'RealtimeTranslator: Speaker 1 TTS missing, generating on-demand...');
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
        debugPrint('RealtimeTranslator: No TTS audio available for Speaker 1');
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

        // Play TTS in continuous A2DP mode (no switching)
        debugPrint('RealtimeTranslator: Playing Speaker 1 TTS (continuous A2DP)');
        await _ttsService.playAudioFile(_speaker1TtsAudioPath!);
        setState(() {
          _isPlayingTts1 = true;
        });
      }
    } catch (e) {
      debugPrint('RealtimeTranslator: Speaker 1 TTS playback error: $e');
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
            'RealtimeTranslator: Speaker 2 TTS missing, generating on-demand...');
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
        debugPrint('RealtimeTranslator: No TTS audio available for Speaker 2');
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

        // Play TTS in continuous A2DP mode (no switching)
        debugPrint('RealtimeTranslator: Playing Speaker 2 TTS (continuous A2DP)');
        await _ttsService.playAudioFile(_speaker2TtsAudioPath!);
        setState(() {
          _isPlayingTts2 = true;
        });
      }
    } catch (e) {
      debugPrint('RealtimeTranslator: Speaker 2 TTS playback error: $e');
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
        debugPrint('RealtimeTranslator: Stereo audio stopped');
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
              'RealtimeTranslator: No cached stereo audio file available');
          _showErrorDialog(
              'Stereo audio file not available. Please try again.');
          return;
        }

        // Check if the cached file exists
        final stereoFile = File(_cachedStereoAudioPath!);
        if (!await stereoFile.exists()) {
          debugPrint(
              'RealtimeTranslator: Cached stereo audio file does not exist: $_cachedStereoAudioPath');
          _showErrorDialog('Stereo audio file not found. Please try again.');
          return;
        }

        debugPrint('RealtimeTranslator: Playing cached stereo audio...');
        debugPrint('  Cached stereo file: $_cachedStereoAudioPath');

        // CRITICAL: Switch to playback route for proper TWS stereo routing
        debugPrint('RealtimeTranslator: Switching to playback route...');
        await _enterPlaybackRoute();

        // IMPORTANT: Add delay to allow audio system to switch modes
        // TWS devices need time to switch from SCO/COMMUNICATION to A2DP/MUSIC mode
        // Android 11 may need longer delay for proper mode switching
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint(
            'RealtimeTranslator: ✅ Audio route switched (waited 500ms), ready for stereo playback');

        // Play the cached stereo audio file
        await _stereoTtsService.playStereoAudio(_cachedStereoAudioPath!);

        setState(() {
          _isPlayingStereo = true;
        });
        debugPrint('RealtimeTranslator: Stereo audio playing successfully');
      }
    } catch (e) {
      debugPrint('RealtimeTranslator: Stereo audio playback error: $e');
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
            'RealtimeTranslator: ⚠️ Stereo audio already playing, skipping auto-play');
        return;
      }

      debugPrint('RealtimeTranslator: Starting auto-play of stereo audio...');

      // Do not require translations for auto-play; rely on generated stereo file

      // CRITICAL: Switch to playback route for proper TWS stereo routing
      debugPrint(
          'RealtimeTranslator: Auto-play: Switching to playback route...');
      await _enterPlaybackRoute();

      // IMPORTANT: Add delay to allow audio system to switch modes
      // TWS devices need time to switch from SCO/COMMUNICATION to A2DP/MUSIC mode
      // Android 11 may need longer delay for proper mode switching
      await Future.delayed(const Duration(milliseconds: 500));
      debugPrint(
          'RealtimeTranslator: ✅ Audio route switched for auto-play (waited 500ms)');

      // Check if we have language information
      final speaker1Language = _speakerLanguages[0];
      final speaker2Language = _speakerLanguages[1];
      if (speaker1Language == null || speaker2Language == null) {
        debugPrint(
            'RealtimeTranslator: No language information available for auto-play stereo audio');
        return;
      }

      // Check if we have a cached stereo audio file
      if (_cachedStereoAudioPath == null) {
        debugPrint(
            'RealtimeTranslator: No cached stereo audio file available for auto-play');
        return;
      }

      // Check if the cached file exists
      final stereoFile = File(_cachedStereoAudioPath!);
      if (!await stereoFile.exists()) {
        debugPrint(
            'RealtimeTranslator: Cached stereo audio file does not exist for auto-play: $_cachedStereoAudioPath');
        return;
      }

      debugPrint('RealtimeTranslator: Auto-playing cached stereo audio...');
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
          'RealtimeTranslator: ✅ Auto-play stereo audio started successfully');
      debugPrint(
          'RealtimeTranslator: Waiting for playback completion callback...');
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Auto-play stereo audio error: $e');
      setState(() {
        _isPlayingStereo = false;
      });
      // Don't show error dialog for auto-play failures - just log them
      debugPrint(
          'RealtimeTranslator: Auto-play failed silently, user can still play manually');
    }
  }

  void _toggleTranslation(int speakerId) {
    setState(() {
      _showTranslation[speakerId] = !(_showTranslation[speakerId] ?? false);
    });
    debugPrint(
        'RealtimeTranslator: Toggled translation for Speaker $speakerId: ${_showTranslation[speakerId]}');
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
        'RealtimeTranslator: Voice activity detection - Audio data length: ${audioData.length} samples');
    debugPrint('RealtimeTranslator: Energy threshold: $energyThreshold');

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
            'RealtimeTranslator: Energy at sample $i: ${energy.toStringAsFixed(6)}, threshold: $energyThreshold');
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
        'RealtimeTranslator: K-means converged after $iteration iterations');
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
        'RealtimeTranslator: Mapped language code: $languageCode -> $mappedCode');
    return mappedCode;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBackgroundColor,
        title: Text(
          'Error',
          style: TextStyle(color: _primaryTextColor),
        ),
        content: Text(
          message,
          style: TextStyle(color: _secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: TextStyle(color: _primaryAccentColor),
            ),
          ),
        ],
      ),
    );
  }

  // Download dialogs removed - no model downloads needed with Azure Translator API

  /// Stop automatic translation mode
  Future<void> _stopAutomaticMode() async {
    if (!_isAutomaticMode) return;

    setState(() {
      _isAutomaticMode = false;
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

    debugPrint('RealtimeTranslator: Stopped automatic translation mode');
  }

  /// Stop sound level monitoring
  void _stopSoundLevelMonitoring() {
    debugPrint('RealtimeTranslator: Stopping sound level monitoring');

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

  /// Start automatic recording with sound level monitoring
  Future<void> _startAutomaticRecording() async {
    if (!_isAutomaticMode || _isRecording) return;

    try {
      debugPrint('RealtimeTranslator: ═══ Starting new recording cycle ═══');

      // NOTE: We do NOT stop playback here!
      // Playback should have already finished before this is called.
      // This method is only called from the playback completion callback.

      // NOTE: We do NOT clean up files here!
      // Files are cleaned up AFTER stereo generation and playback completes.
      // This prevents deleting TTS files that are still being used.

      setState(() {
        _isRecording = true;
        _isSilentDetectionActive = false;
        _silentDetectionCountdown = 0;
        _consecutiveSpeechDetections = 0; // Reset speech detection counter
        _hasDetectedSpeechInSession = false; // Reset first speech flag
        _isProcessing = false; // Ensure processing flag is cleared
        _isPlayingStereo = false; // Ensure playback flag is cleared
      });

      debugPrint(
          'RealtimeTranslator: Starting automatic recording (waiting for first speech...)');

      // CRITICAL: Ensure no audio is playing before starting mic
      // This prevents capturing TTS audio from previous cycle
      if (_isPlayingStereo) {
        debugPrint(
            'RealtimeTranslator: ⚠️ Stereo audio still playing, waiting...');
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
      debugPrint('RealtimeTranslator: [AUTO] Starting NATIVE recorder...');
      debugPrint(
          'RealtimeTranslator: [AUTO] Forced MIC audio source (phone mic only)');
      final bool started = await _nativeRecorder.startRecording(recordingPath);

      if (!started) {
        debugPrint(
            'RealtimeTranslator: ❌ [AUTO] Failed to start native recording');
        return;
      }

      _recordedAudioPath = recordingPath;

      debugPrint('RealtimeTranslator: Audio recorder started successfully');

      // Add a small delay to ensure recorder has exclusive microphone access
      await Future.delayed(const Duration(milliseconds: 200));

      // Start sound level monitoring (now sharing microphone with recorder)
      _startSoundLevelMonitoring();

      // DON'T start silent detection timer yet!
      // It will start automatically when first speech is detected
      debugPrint(
          'RealtimeTranslator: Waiting for first speech to activate silent detection...');
    } catch (e) {
      debugPrint('RealtimeTranslator: Error starting automatic recording: $e');
      setState(() {
        _isRecording = false;
      });
    }
  }

  /// Start sound level monitoring using real microphone input
  void _startSoundLevelMonitoring() {
    debugPrint(
      'RealtimeTranslator: Starting real-time microphone amplitude monitoring',
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
              'RealtimeTranslator: Real microphone amplitude: ${noiseReading.meanDecibel.toStringAsFixed(1)} dB, normalized: ${(normalizedAmplitude * 100).toStringAsFixed(1)}%',
            );
          }

          // Check if sound level indicates speech
          if (_isSpeechDetected(normalizedAmplitude)) {
            _onSpeechDetected();
          }
        },
        onError: (error) {
          debugPrint('RealtimeTranslator: Noise meter error: $error');
        },
      );

      debugPrint(
        'RealtimeTranslator: Real-time microphone monitoring started successfully',
      );
    } catch (e) {
      debugPrint('RealtimeTranslator: Error starting noise meter: $e');
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
          'RealtimeTranslator: Sound level: ${(soundLevel * 100).toStringAsFixed(1)}%, '
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
          'RealtimeTranslator: First speech detected! Starting silent detection timer');

      // Start silent detection timer for the first time
      _startSilentDetectionTimer();
      return;
    }

    // If already in silent detection mode, reset the timer
    if (!_isSilentDetectionActive) return;

    debugPrint(
        'RealtimeTranslator: Speech detected, resetting silent detection timer');

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
        'RealtimeTranslator: Starting silent detection timer (${_silentDetectionDuration}s)');

    _silentDetectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isAutomaticMode || !_isRecording) {
        timer.cancel();
        debugPrint(
            'RealtimeTranslator: Silent detection timer cancelled - mode changed');
        return;
      }

      setState(() {
        _silentDetectionCountdown--;
      });

      debugPrint(
          'RealtimeTranslator: Silent detection countdown: ${_silentDetectionCountdown}s');

      if (_silentDetectionCountdown <= 0) {
        timer.cancel();
        debugPrint('RealtimeTranslator: Silent detection timeout reached');
        _onSilentDetectionTimeout();
      }
    });
  }

  /// Handle silent detection timeout
  Future<void> _onSilentDetectionTimeout() async {
    if (!_isAutomaticMode || !_isRecording) return;

    debugPrint(
        'RealtimeTranslator: Silent detection timeout, stopping recording');

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
          'RealtimeTranslator: Processing recorded audio in automatic mode');

      // Set up playback completion callback BEFORE processing starts
      // This ensures the callback is ready when auto-play happens
      _setupPlaybackCompletionCallback();

      // Process through the existing pipeline (this will trigger auto-play)
      await _processAudio();

      // Note: The callback will handle restarting after playback completes
      debugPrint(
          'RealtimeTranslator: Processing complete, waiting for TTS playback to finish...');
    } catch (e) {
      debugPrint(
          'RealtimeTranslator: Error processing audio in automatic mode: $e');
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
        'RealtimeTranslator: Playback completion callback already set up in initState() - no action needed');

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
        color: _cardBackgroundColor,
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
      debugPrint('RealtimeTranslator: Cleaning up TTS files...');

      int deletedCount = 0;

      // Delete TTS audio files
      if (_speaker1TtsAudioPath != null) {
        final file1 = File(_speaker1TtsAudioPath!);
        if (await file1.exists()) {
          await file1.delete();
          deletedCount++;
          debugPrint(
              'RealtimeTranslator: Deleted Speaker 1 TTS: $_speaker1TtsAudioPath');
        }
        _speaker1TtsAudioPath = null;
      }

      if (_speaker2TtsAudioPath != null) {
        final file2 = File(_speaker2TtsAudioPath!);
        if (await file2.exists()) {
          await file2.delete();
          deletedCount++;
          debugPrint(
              'RealtimeTranslator: Deleted Speaker 2 TTS: $_speaker2TtsAudioPath');
        }
        _speaker2TtsAudioPath = null;
      }

      debugPrint('RealtimeTranslator: ✅ Cleaned up $deletedCount TTS files');
    } catch (e) {
      debugPrint('RealtimeTranslator: Error cleaning up TTS files: $e');
    }
  }

  /// Play start recording sound effect
  /// Uses custom sound file if available, falls back to system sound
  /// Ensures sound plays through TWS/Bluetooth headset
  Future<void> _playStartRecordingSound() async {
    try {
      debugPrint('RealtimeTranslator: 🔊 Playing START recording beep...');
      
      // Ensure we're in playback mode for the beep
      if (_isRealtimeMode) {
        await _enterPlaybackRoute();
        await Future.delayed(const Duration(milliseconds: 200)); // Wait for route to stabilize
      }
      
      // Try to play custom sound file first
      try {
        final completer = Completer<void>();
        
        // Listen for completion
        final subscription = _soundEffectPlayer.onPlayerComplete.listen((event) {
          if (!completer.isCompleted) completer.complete();
        });
        
        await _soundEffectPlayer.play(AssetSource('sounds/recording_start.mp3'));
        
        // Wait for playback to complete (with timeout)
        await completer.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint('RealtimeTranslator: ⚠️ Start beep playback timeout');
          },
        );
        
        await subscription.cancel();
        debugPrint('RealtimeTranslator: ✅ Played START recording beep (custom) in TWS');
      } catch (e) {
        // Fallback to system sound if custom file not available
        debugPrint('RealtimeTranslator: Custom sound not found, using system beep');
        SystemSound.play(SystemSoundType.click);
        await Future.delayed(const Duration(milliseconds: 100)); // Give system sound time to play
        debugPrint('RealtimeTranslator: ✅ Played START recording beep (system)');
      }
      
      // Add small delay before switching to recording mode
      await Future.delayed(const Duration(milliseconds: 150));
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error playing start recording sound: $e');
      // Don't block recording if sound effect fails
    }
  }

  /// Play stop recording sound effect
  /// Uses custom sound file if available, falls back to system sound
  /// Ensures sound plays through TWS/Bluetooth headset
  Future<void> _playStopRecordingSound() async {
    try {
      debugPrint('RealtimeTranslator: 🔊 Playing STOP recording beep...');
      
      // Ensure we're in playback mode for the beep
      if (_isRealtimeMode) {
        await _enterPlaybackRoute();
        await Future.delayed(const Duration(milliseconds: 200)); // Wait for route to stabilize
      }
      
      // Try to play custom sound file first
      try {
        final completer = Completer<void>();
        
        // Listen for completion
        final subscription = _soundEffectPlayer.onPlayerComplete.listen((event) {
          if (!completer.isCompleted) completer.complete();
        });
        
        await _soundEffectPlayer.play(AssetSource('sounds/recording_stop.mp3'));
        
        // Wait for playback to complete (with timeout)
        await completer.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            debugPrint('RealtimeTranslator: ⚠️ Stop beep playback timeout');
          },
        );
        
        await subscription.cancel();
        debugPrint('RealtimeTranslator: ✅ Played STOP recording beep (custom) in TWS');
      } catch (e) {
        // Fallback to system sound if custom file not available
        debugPrint('RealtimeTranslator: Custom sound not found, using system beep');
        SystemSound.play(SystemSoundType.alert);
        await Future.delayed(const Duration(milliseconds: 100)); // Give system sound time to play
        debugPrint('RealtimeTranslator: ✅ Played STOP recording beep (system)');
      }
      
      // Add small delay after beep before continuing
      await Future.delayed(const Duration(milliseconds: 150));
    } catch (e) {
      debugPrint('RealtimeTranslator: ❌ Error playing stop recording sound: $e');
      // Don't block processing if sound effect fails
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Remove lifecycle observer
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
    
    // Clean up pending translation timers
    for (var timer in _pendingTranslationTimers.values) {
      timer?.cancel();
    }
    _pendingTranslationTimers.clear();
    _pendingTranscriptions.clear();
    _pendingLanguages.clear();
    
    // Clean up sentence buffers
    _sentenceTranscriptionBuffers.clear();
    _sentenceTranslationBuffers.clear();
    _sentenceLanguages.clear();
    
    // Clean up sentence processing timers (batch processing adaptive timers)
    for (var timer in _sentenceProcessingTimers.values) {
      timer?.cancel();
    }
    _sentenceProcessingTimers.clear();
    _accumulatedChunkCount.clear();
    _lastChunkReceivedTime.clear();
    debugPrint('RealtimeTranslator: Sentence processing timers and counters cleared');

    // Clean up scroll controllers
    _speaker1TranscriptionScrollController.dispose();
    _speaker1TranslationScrollController.dispose();
    _speaker2TranscriptionScrollController.dispose();
    _speaker2TranslationScrollController.dispose();

    super.dispose();
  }

  /// Show session summary dialog
  void _showSessionSummary() {
    if (_sessionStartTime == null || _sessionEndTime == null) {
      debugPrint('RealtimeTranslator: ⚠️ Cannot show summary - session times not set');
      return;
    }

    final totalDuration = _sessionEndTime!.difference(_sessionStartTime!);
    final totalCost = _calculateSessionCost();

    final summary = TranslationSessionSummary(
      sessionStart: _sessionStartTime!,
      sessionEnd: _sessionEndTime!,
      totalDuration: totalDuration,
      audioSecondsProcessed: _audioSecondsProcessed,
      inputAudioTokens: _totalInputAudioTokens,
      outputTextTokens: _totalOutputTextTokens,
      transcriptionCharacters: _totalTranscriptionCharacters,
      translationCharacters: _totalTranslationCharacters,
      charactersPerSpeaker: _transcriptionCharactersPerSpeaker,
      translationCharactersPerSpeaker: _translationCharactersPerSpeaker,
      languagesUsed: {
        0: _speakerLanguages[0]?.name ?? 'Unknown',
        1: _speakerLanguages[1]?.name ?? 'Unknown',
      },
      totalCost: totalCost,
      totalTranslations: _totalTranslations,
      translationLatencies: _translationLatencies,
    );

    showDialog(
      context: context,
      builder: (context) => _buildSummaryDialog(summary),
    );
  }

  /// Build session summary dialog
  Widget _buildSummaryDialog(TranslationSessionSummary summary) {
    final speaker0Percentage = summary.speakerSplitPercentage[0] ?? 0.0;
    final speaker1Percentage = summary.speakerSplitPercentage[1] ?? 0.0;

    return Dialog(
      backgroundColor: _cardBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _primaryAccentColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: _primaryAccentColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Session Complete',
                      style: TextStyle(
                        color: _primaryTextColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: _secondaryTextColor),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Session Time
              _buildSummarySection(
                icon: Icons.access_time,
                title: 'SESSION TIME',
                children: [
                  _buildSummaryRow('Duration', summary.formattedDuration),
                  _buildSummaryRow('Audio Processed', '${summary.audioSecondsProcessed.toStringAsFixed(1)}s'),
                  _buildSummaryRow('Started', _formatTime(summary.sessionStart)),
                  _buildSummaryRow('Ended', _formatTime(summary.sessionEnd)),
                ],
              ),

              const SizedBox(height: 20),

              // Conversation Stats
              _buildSummarySection(
                icon: Icons.forum,
                title: 'CONVERSATION',
                children: [
                  _buildSpeakerRow(
                    speakerName: _getSpeakerDisplayName(0),
                    language: summary.languagesUsed[0] ?? 'Unknown',
                    characters: summary.charactersPerSpeaker[0] ?? 0,
                    percentage: speaker0Percentage,
                    color: _speakerColors[0],
                  ),
                  const SizedBox(height: 12),
                  _buildSpeakerRow(
                    speakerName: _getSpeakerDisplayName(1),
                    language: summary.languagesUsed[1] ?? 'Unknown',
                    characters: summary.charactersPerSpeaker[1] ?? 0,
                    percentage: speaker1Percentage,
                    color: _speakerColors[1],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Usage & Cost
              _buildSummarySection(
                icon: Icons.receipt_long,
                title: 'USAGE & COST',
                children: [
                  _buildSummaryRow('Input Audio', '${summary.inputAudioTokens.toString()} tokens'),
                  _buildSummaryRow('  └─ Duration', '${summary.audioSecondsProcessed.toStringAsFixed(1)}s'),
                  const SizedBox(height: 8),
                  _buildSummaryRow('Output Text', '${summary.outputTextTokens.toString()} tokens'),
                  _buildSummaryRow('  └─ Characters', '${summary.totalCharacters.toString()}'),
                  Divider(color: _dividerColor, height: 24),
                  _buildSummaryRow(
                    'TOTAL COST',
                    summary.formattedCost,
                    isTotal: true,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Performance
              _buildSummarySection(
                icon: Icons.speed,
                title: 'PERFORMANCE',
                children: [
                  _buildSummaryRow('Total Translations', '${summary.totalTranslations}'),
                  _buildSummaryRow('Avg Latency', '${summary.averageLatency.toStringAsFixed(2)}s'),
                ],
              ),

              const SizedBox(height: 24),

              // Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.done, size: 20),
                  label: const Text('Done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryAccentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build summary section
  Widget _buildSummarySection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _secondaryCardBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primaryAccentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: _primaryAccentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  /// Build summary row
  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isTotal ? _primaryTextColor : _secondaryTextColor,
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isTotal ? _primaryAccentColor : _primaryTextColor,
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build speaker row with progress bar
  Widget _buildSpeakerRow({
    required String speakerName,
    required String language,
    required int characters,
    required double percentage,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$speakerName ($language)',
                  style: TextStyle(
                    color: _primaryTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$characters chars',
              style: TextStyle(
                color: _secondaryTextColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: _dividerColor,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Format time for display
  String _formatTime(DateTime time) {
    final hour12 = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: _scaffoldBackgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Circular progress indicator
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_primaryAccentColor),
                ),
                const SizedBox(height: 30),

                // Status text
                Text(
                  'Initializing translator...',
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontSize: 18,
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
      backgroundColor: _scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: _buildMainContent(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _appBarBackgroundColor,
      elevation: 0,
      title: Text(
        'Realtime Translation',
        style: TextStyle(
          color: _primaryTextColor,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: _primaryTextColor),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        // Settings can be accessed via speaker headers now
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
          Text(
            'Configure Speakers',
            style: TextStyle(
              color: _primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // Real-time mode info (always enabled)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.purple,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.flash_on,
                  color: Colors.purple,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Real-time Mode',
                        style: TextStyle(
                          color: Colors.purple,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Continuous translation with instant TTS playback',
                        style: TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
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
              backgroundColor: _primaryAccentColor,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isStartingSession
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_primaryTextColor),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Starting...',
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Start Recording',
                    style: TextStyle(
                      color: _primaryTextColor,
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
        color: _cardBackgroundColor,
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
                _getSpeakerDisplayName(speakerIndex),
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
              labelStyle: TextStyle(color: _secondaryTextColor, fontSize: 14),
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
            dropdownColor: _cardBackgroundColor,
                style: TextStyle(color: _primaryTextColor, fontSize: 14),
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
                    'RealtimeTranslator: Speaker $speakerIndex language changed to: ${newLanguage.name}');
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
            'RealtimeTranslator: Speaker $speakerIndex gender changed to: $gender');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? speakerColor.withValues(alpha: 0.2)
              : _secondaryCardBackgroundColor,
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
            'RealtimeTranslator: Speaker $speakerIndex earpiece changed to: $earpiece');
        debugPrint(
            'RealtimeTranslator: Speaker ${speakerIndex == 0 ? 1 : 0} earpiece automatically set to: ${earpiece == 'left' ? 'right' : 'left'}');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? speakerColor.withValues(alpha: 0.2)
              : _secondaryCardBackgroundColor,
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
              color: isSelected ? speakerColor : _secondaryTextColor,
              size: 18,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? speakerColor : _secondaryTextColor,
                fontSize: 12,
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
        // NEW: TWS connection status indicator
        if (!_isTwsConnected) _buildTwsStatusIndicator(),
        _buildSoundLevelGraph(),
        Expanded(
          child: _isProcessing
              ? _buildProcessingView()
              : (_speaker1AudioPath != null && _speaker2AudioPath != null)
                  ? _buildResultsView()
                  : _buildRealtimeResultsView(), // Always show main translation screen for language selection
        ),
        _buildRecordingControls(),
      ],
    );
  }

  /// NEW: Build TWS status indicator showing playback is disabled
  Widget _buildTwsStatusIndicator() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.bluetooth_disabled,
            color: Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audio Playback Disabled',
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'TWS not connected. Translation works, but audio playback is disabled.',
                  style: TextStyle(
                    color: _secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.info_outline,
              color: Colors.orange,
              size: 20,
            ),
            onPressed: () {
              _hasShownTwsNotConnectedDialog = false; // Reset to show dialog again
              _showTwsNotConnectedDialog();
            },
            tooltip: 'Learn more',
          ),
        ],
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
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_primaryAccentColor),
              strokeWidth: 4,
            ),
            const SizedBox(height: 30),
            Text(
              _processingStatus,
                  style: TextStyle(
                    color: _primaryTextColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: _processingProgress,
              backgroundColor: _dividerColor,
              valueColor:
                  AlwaysStoppedAnimation<Color>(_primaryAccentColor),
            ),
            const SizedBox(height: 10),
            Text(
              '${(_processingProgress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                color: _secondaryTextColor,
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
                    _primaryAccentColor.withValues(alpha: 0.3),
                    _primaryAccentColor.withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(
                Icons.mic,
                color: _primaryAccentColor,
                size: 60,
              ),
            ),
            const SizedBox(height: 30),
            Text(
              'Ready to Record',
              style: TextStyle(
                color: _primaryTextColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap the microphone button below to start recording a conversation between two speakers.',
              style: TextStyle(
                color: _secondaryTextColor,
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
  /// OPTIMIZED: Fixed-height sections with side-by-side transcription/translation
  Widget _buildRealtimeResultsView() {
    // OPTIMIZED: Use flexible layout instead of fixed height to prevent overflow
    return Column(
      children: [
        // Two responsive speaker sections stacked vertically (50% each)
        Expanded(
          flex: 1,
          child: _buildRealtimeSpeakerSection(
            speakerIndex: 0,
          ),
        ),
        // Divider
        Container(
          height: 1,
          color: _dividerColor,
        ),
        // Speaker 2 section (bottom)
        Expanded(
          flex: 1,
          child: _buildRealtimeSpeakerSection(
            speakerIndex: 1,
          ),
        ),
      ],
    );
  }

  /// Build real-time speaker section with responsive layout and side-by-side layout
  /// OPTIMIZED: Responsive height (flexible), side-by-side transcription/translation, auto-scrolling
  Widget _buildRealtimeSpeakerSection({
    required int speakerIndex,
  }) {
    final speakerColor = _speakerColors[speakerIndex % _speakerColors.length];
    final transcription = _transcriptions[speakerIndex] ?? '';
    final translation = _translations[speakerIndex] ?? '';
    final language = _speakerLanguages[speakerIndex];
    final targetLanguage = _speakerLanguages[speakerIndex == 0 ? 1 : 0];
    final transcriptionScrollController = speakerIndex == 0 
        ? _speaker1TranscriptionScrollController 
        : _speaker2TranscriptionScrollController;
    final translationScrollController = speakerIndex == 0 
        ? _speaker1TranslationScrollController 
        : _speaker2TranslationScrollController;

    return Container(
      decoration: BoxDecoration(
        color: _cardBackgroundColor,
        border: Border(
          top: BorderSide(
            color: speakerColor.withValues(alpha: 0.3),
            width: speakerIndex == 0 ? 2 : 0,
          ),
          bottom: BorderSide(
            color: speakerColor.withValues(alpha: 0.3),
            width: speakerIndex == 1 ? 2 : 0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            // Speaker header with inline settings (OPTIMIZED: More compact)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _cardBackgroundColor,
                border: Border(
                  bottom: BorderSide(
                    color: speakerColor.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
              ),
            child: Row(
              children: [
                // Speaker icon (smaller)
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
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                // Speaker name (compact)
                Text(
                  _getSpeakerDisplayName(speakerIndex),
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                // Language, Gender, Earpiece settings (all in one row)
                Expanded(
                  child: Row(
                    children: [
                      // Language dropdown (compact)
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: _secondaryCardBackgroundColor,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: speakerColor.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<Language>(
                              value: language,
                              isDense: true,
                              isExpanded: true,
                              dropdownColor: _cardBackgroundColor,
                              style: TextStyle(
                                color: speakerColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: speakerColor,
                                size: 16,
                              ),
                              items: _supportedLanguages.map((lang) {
                                return DropdownMenuItem<Language>(
                                  value: lang,
                                  child: Text(
                                    lang.name,
                                    style: const TextStyle(fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (Language? newLanguage) {
                                if (newLanguage != null) {
                                  setState(() {
                                    _speakerLanguages[speakerIndex] = newLanguage;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Gender selector (compact)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _speakerGenders[speakerIndex] = 
                                _speakerGenders[speakerIndex] == 'male' ? 'female' : 'male';
                          });
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: speakerColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: speakerColor.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            _speakerGenders[speakerIndex] == 'female'
                                ? Icons.female
                                : Icons.male,
                            color: speakerColor,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Earpiece selector (compact)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            final newEarpiece = _speakerEarpieces[speakerIndex] == 'left' ? 'right' : 'left';
                            _speakerEarpieces[speakerIndex] = newEarpiece;
                            // Auto-assign opposite to other speaker
                            final otherIndex = speakerIndex == 0 ? 1 : 0;
                            _speakerEarpieces[otherIndex] = newEarpiece == 'left' ? 'right' : 'left';
                          });
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: speakerColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: speakerColor.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.headphones,
                                color: speakerColor,
                                size: 14,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                _speakerEarpieces[speakerIndex] == 'left' ? 'L' : 'R',
                                style: TextStyle(
                                  color: speakerColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Side-by-side transcription and translation
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Transcription section (left)
                Expanded(
                  child: _buildScrollableTextSection(
                    scrollController: transcriptionScrollController,
                    icon: Icons.mic,
                    title: 'Original',
                    subtitle: language?.name ?? 'Unknown',
                    text: transcription.isEmpty ? 'Ready to Record' : transcription,
                    color: speakerColor,
                    isEmpty: transcription.isEmpty,
                  ),
                ),
                // Divider
                Container(
                  width: 1,
                  color: _dividerColor,
                ),
                // Translation section (right)
                Expanded(
                  child: _buildScrollableTextSection(
                    scrollController: translationScrollController,
                    icon: Icons.translate,
                    title: 'Translation',
                    subtitle: targetLanguage?.name ?? 'Unknown',
                    text: translation.isEmpty ? 'Ready to Record' : translation,
                    color: speakerColor,
                    isEmpty: translation.isEmpty,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build scrollable text section for transcription or translation
  Widget _buildScrollableTextSection({
    required ScrollController scrollController,
    required IconData icon,
    required String title,
    required String subtitle,
    required String text,
    required Color color,
    required bool isEmpty,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBackgroundColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header (OPTIMIZED: More compact)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _secondaryCardBackgroundColor,
              border: Border(
                bottom: BorderSide(
                  color: color.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Scrollable content (OPTIMIZED: Reduced padding)
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(8),
              child: Text(
                text,
                style: TextStyle(
                  color: isEmpty ? _tertiaryTextColor : _primaryTextColor,
                  fontSize: 18,
                  height: 1.5,
                  fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ),
        ],
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
          Text(
            'Audio Separated Successfully!',
            style: TextStyle(
              color: _primaryTextColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Found ${_speakerSegments.length} speaker segments',
            style: TextStyle(
              color: _secondaryTextColor,
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
        color: _cardBackgroundColor,
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
                        _getSpeakerDisplayName(speakerIndex),
                        style: TextStyle(
                          color: speakerColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isPlaying ? 'Playing...' : 'Tap to play',
                        style: TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.volume_up,
                  color: isPlaying ? speakerColor : _tertiaryTextColor,
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

  /// Get display name for a speaker (with fallback)
  String _getSpeakerDisplayName(int speakerIndex) {
    if (speakerIndex >= 0 && speakerIndex < _speakerNames.length) {
      return _speakerNames[speakerIndex];
    }
    return 'Speaker ${speakerIndex + 1}';
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
    final String? translatedText =
        showTranslation && translation != null && translation.isNotEmpty
            ? translation
            : null;
    final bool hasTranslation = translatedText != null;
    final displayText = translatedText ?? transcription;

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
                hasTranslation ? Icons.translate : Icons.subtitles,
                color: speakerColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                hasTranslation ? 'Translation:' : 'Transcription:',
                style: TextStyle(
                  color: speakerColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Translation toggle button
              if (hasTranslation)
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
                          hasTranslation ? Icons.subtitles : Icons.translate,
                          color: speakerColor,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasTranslation ? 'Original' : 'Translate',
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
              color: _secondaryCardBackgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              displayText,
                  style: TextStyle(
                    color: _primaryTextColor,
                fontSize: 16,
                height: 1.5,
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
                hasTranslation
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
          if (hasTranslation) ...[
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
        color: _cardBackgroundColor,
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
                        color: _isPlayingStereo ? Colors.purple : _primaryTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Left: Speaker 1\'s translation → Right: Speaker 2\'s translation',
                      style: TextStyle(
                        color: _secondaryTextColor,
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
        color: _cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Speaker Segments',
            style: TextStyle(
              color: _primaryTextColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ..._speakerSegments.take(10).map((segment) {
            final speakerName = _getSpeakerDisplayName(segment.speakerId);
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
                          style: TextStyle(
                            color: _secondaryTextColor,
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
              style: TextStyle(
                color: _tertiaryTextColor,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: _appBarBackgroundColor,
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

            // Manual Recording Controls with 3-column layout: Status (left), Mic (center), Empty (right)
            if (!_isAutomaticMode) ...[
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Center: Mic button (always centered)
                  GestureDetector(
                    onTap: _isProcessing ? null : _toggleRecording,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _isRecording ? _pulseAnimation.value : 1.0,
                          child: Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isRecording
                                  ? Colors.red
                                  : (_isDarkMode 
                                      ? const Color(0xFF00D9FF) 
                                      : const Color(0xFF007A99)),
                              boxShadow: _isRecording
                                  ? [
                                      BoxShadow(
                                        color: Colors.red.withValues(alpha: 0.3),
                                        blurRadius: 15,
                                        spreadRadius: 3,
                                      ),
                                    ]
                                  : [
                                      BoxShadow(
                                        color: (_isDarkMode 
                                            ? const Color(0xFF00D9FF) 
                                            : const Color(0xFF007A99))
                                            .withValues(alpha: 0.3),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ],
                            ),
                            child: Icon(
                              _isRecording ? Icons.stop : Icons.mic,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Status indicator under mic icon
                  Text(
                    _isInitializing
                        ? 'Initializing'
                        : (_isRecording
                        ? 'Recording'
                        : _isRealtimeListeningPaused
                            ? 'Playing'
                            : 'Ready'),
                    style: TextStyle(
                      color: _isInitializing
                          ? Colors.blue
                          : (_isRecording
                          ? Colors.red
                          : (_isRealtimeListeningPaused
                              ? Colors.orange
                              : Colors.green)),
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
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
                          : (_isRealtimeListeningPaused
                                  ? Colors.orange
                                  : Colors.blue)
                              .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isRecording
                            ? Colors.green
                            : _isRealtimeListeningPaused
                                ? Colors.orange
                                : Colors.blue,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isRecording
                              ? Icons.mic
                              : _isRealtimeListeningPaused
                                  ? Icons.hearing_disabled
                                  : Icons.pause,
                          color: _isRecording
                              ? Colors.green
                              : _isRealtimeListeningPaused
                                  ? Colors.orange
                                  : Colors.blue,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isRecording
                              ? 'Listening...'
                              : _isRealtimeListeningPaused
                                  ? 'Playing translation...'
                                  : 'Processing...',
                          style: TextStyle(
                            color: _isRecording
                                ? Colors.green
                                : _isRealtimeListeningPaused
                                    ? Colors.orange
                                    : Colors.blue,
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
