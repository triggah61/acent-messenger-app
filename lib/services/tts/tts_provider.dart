/// Abstract interface for Text-to-Speech providers
/// This allows easy switching between different TTS services
abstract class TTSProvider {
  /// Provider name for identification
  String get providerName;

  /// Initialize the TTS provider
  Future<void> initialize();

  /// Convert text to speech and return audio URL or play directly
  /// Returns the audio URL for remote providers or null for direct playback
  Future<String?> speak({
    required String text,
    required String languageCode,
    String? voiceId,
    double? speed,
    double? pitch,
  });

  /// Stop current speech playback
  Future<void> stop();

  /// Get available voices for a language
  Future<List<TTSVoice>> getVoicesForLanguage(String languageCode);

  /// Check if provider is available/configured
  Future<bool> isAvailable();

  /// Dispose resources
  Future<void> dispose();
}

/// Voice information for TTS
class TTSVoice {
  final String id;
  final String name;
  final String languageCode;
  final String? gender;
  final String? description;
  final bool isDefault;

  TTSVoice({
    required this.id,
    required this.name,
    required this.languageCode,
    this.gender,
    this.description,
    this.isDefault = false,
  });

  factory TTSVoice.fromJson(Map<String, dynamic> json) {
    return TTSVoice(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      languageCode: json['languageCode'] ?? json['language_code'] ?? '',
      gender: json['gender'],
      description: json['description'],
      isDefault: json['isDefault'] ?? json['is_default'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'languageCode': languageCode,
      'gender': gender,
      'description': description,
      'isDefault': isDefault,
    };
  }

  @override
  String toString() => '$name ($languageCode)';
}

/// TTS Configuration
class TTSConfig {
  final String provider;
  final Map<String, dynamic> settings;

  TTSConfig({
    required this.provider,
    required this.settings,
  });

  factory TTSConfig.fromJson(Map<String, dynamic> json) {
    return TTSConfig(
      provider: json['provider'] ?? 'elevenlabs',
      settings: json['settings'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'settings': settings,
    };
  }
}
