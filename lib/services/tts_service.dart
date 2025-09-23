import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/config.dart';
import 'auth_service.dart';
import 'tts/tts_provider.dart';
import 'tts/elevenlabs_tts_provider.dart';

/// Main TTS service that manages different TTS providers
/// Supports easy switching between providers (ElevenLabs, Google, Azure, etc.)
class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  static TTSService get instance => _instance;

  TTSProvider? _currentProvider;
  TTSConfig? _config;
  bool _isInitialized = false;

  final AuthService _authService = AuthService();

  /// Initialize the TTS service with backend configuration
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('TTSService: Initializing...');

      // Get TTS configuration from backend
      await _loadConfig();

      // Initialize the appropriate provider
      await _initializeProvider();

      _isInitialized = true;
      print(
          'TTSService: Initialized successfully with provider: ${_currentProvider?.providerName}');
    } catch (e) {
      print('TTSService: Initialization failed: $e');
      // Don't throw - allow app to continue without TTS
      _isInitialized = false;
    }
  }

  /// Load TTS configuration from backend
  Future<void> _loadConfig() async {
    try {
      print('TTSService: Getting authentication token...');
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token');
      }
      print('TTSService: Token obtained successfully');

      print(
          'TTSService: Fetching config from: ${Config.baseApiUrl}/config/get');
      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/config/get'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('TTSService: Config response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final configData = data['data'] as Map<String, dynamic>;
        print('TTSService: Config data keys: ${configData.keys.toList()}');

        // Extract TTS configuration
        _config = TTSConfig(
          provider: configData['ttsProvider'] ?? 'elevenlabs',
          settings: {
            'apiKey': configData['elevenlabsApiKey'] ?? '',
            'baseUrl': configData['elevenlabsBaseUrl'] ??
                'https://api.elevenlabs.io/v1',
            ...configData['ttsSettings'] ?? {},
          },
        );

        print('TTSService: ✅ Config loaded - Provider: ${_config!.provider}');
        print(
            'TTSService: API Key present: ${_config!.settings['apiKey']?.isNotEmpty ?? false}');
      } else {
        print('TTSService: ❌ Failed to load config: ${response.statusCode}');
        print('TTSService: Response body: ${response.body}');
        throw Exception('Failed to load config: ${response.statusCode}');
      }
    } catch (e) {
      print('TTSService: ❌ Error loading config: $e');
      // Use default configuration
      _config = TTSConfig(
        provider: 'elevenlabs',
        settings: {
          'apiKey': 'sk_d44d556a3efa7e2a9f2b8ab4af2ab4aafa2ce047ea90e4ff',
          'baseUrl': 'https://api.elevenlabs.io/v1',
        },
      );
      print('TTSService: Using default configuration');
    }
  }

  /// Initialize the appropriate TTS provider based on configuration
  Future<void> _initializeProvider() async {
    if (_config == null) {
      throw Exception('TTS configuration not loaded');
    }

    try {
      print('TTSService: Initializing provider: ${_config!.provider}');
      switch (_config!.provider.toLowerCase()) {
        case 'elevenlabs':
          print('TTSService: Creating ElevenLabs provider...');
          _currentProvider = ElevenLabsTTSProvider(
            apiKey: _config!.settings['apiKey'] ?? '',
            baseUrl:
                _config!.settings['baseUrl'] ?? 'https://api.elevenlabs.io/v1',
          );
          print('TTSService: ElevenLabs provider created');
          break;

        // Future providers can be added here:
        // case 'google':
        //   _currentProvider = GoogleTTSProvider(config: _config!.settings);
        //   break;
        // case 'azure':
        //   _currentProvider = AzureTTSProvider(config: _config!.settings);
        //   break;

        default:
          throw Exception('Unsupported TTS provider: ${_config!.provider}');
      }

      print('TTSService: Calling provider.initialize()...');
      await _currentProvider!.initialize();
      print('TTSService: Provider initialized successfully');

      // Verify provider is available
      print('TTSService: Checking provider availability...');
      final isAvailable = await _currentProvider!.isAvailable();
      print('TTSService: Provider available: $isAvailable');
      if (!isAvailable) {
        throw Exception('TTS provider ${_config!.provider} is not available');
      }
    } catch (e) {
      print('TTSService: ❌ Provider initialization failed: $e');
      _currentProvider = null;
      rethrow;
    }
  }

  /// Convert text to speech using the current provider
  Future<bool> speak({
    required String text,
    required String languageCode,
    String? voiceId,
    double? speed,
    double? pitch,
  }) async {
    print(
        'TTSService: speak() called with text: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');
    print('TTSService: _isInitialized: $_isInitialized');
    print('TTSService: _currentProvider: ${_currentProvider?.providerName}');

    if (!_isInitialized || _currentProvider == null) {
      print('TTSService: ❌ Service not initialized or provider unavailable');
      print(
          'TTSService: _isInitialized: $_isInitialized, _currentProvider: $_currentProvider');
      return false;
    }

    try {
      print('TTSService: ✅ Speaking text in $languageCode');

      await _currentProvider!.speak(
        text: text,
        languageCode: languageCode,
        voiceId: voiceId,
        speed: speed,
        pitch: pitch,
      );

      print('TTSService: ✅ Speech completed successfully');
      return true;
    } catch (e) {
      print('TTSService: ❌ Error in speak: $e');
      return false;
    }
  }

  /// Stop current speech
  Future<void> stop() async {
    if (_currentProvider != null) {
      await _currentProvider!.stop();
    }
  }

  /// Get available voices for a language
  Future<List<TTSVoice>> getVoicesForLanguage(String languageCode) async {
    if (!_isInitialized || _currentProvider == null) {
      return [];
    }

    try {
      return await _currentProvider!.getVoicesForLanguage(languageCode);
    } catch (e) {
      print('TTSService: Error getting voices: $e');
      return [];
    }
  }

  /// Check if TTS is available and working
  Future<bool> isAvailable() async {
    if (!_isInitialized || _currentProvider == null) {
      return false;
    }

    return await _currentProvider!.isAvailable();
  }

  /// Get current provider name
  String? get currentProvider => _currentProvider?.providerName;

  /// Switch to a different TTS provider
  Future<void> switchProvider(
      String providerName, Map<String, dynamic> settings) async {
    try {
      print('TTSService: Switching to provider: $providerName');

      // Dispose current provider
      if (_currentProvider != null) {
        await _currentProvider!.dispose();
      }

      // Update configuration
      _config = TTSConfig(
        provider: providerName,
        settings: settings,
      );

      // Initialize new provider
      await _initializeProvider();

      print('TTSService: Successfully switched to $providerName');
    } catch (e) {
      print('TTSService: Error switching provider: $e');
      throw Exception('Failed to switch TTS provider: $e');
    }
  }

  /// Dispose the TTS service
  Future<void> dispose() async {
    if (_currentProvider != null) {
      await _currentProvider!.dispose();
      _currentProvider = null;
    }
    _isInitialized = false;
    print('TTSService: Disposed successfully');
  }

  /// Reload configuration from backend
  Future<void> reloadConfig() async {
    try {
      await _loadConfig();
      if (_config != null) {
        await _initializeProvider();
      }
    } catch (e) {
      print('TTSService: Error reloading config: $e');
    }
  }
}
