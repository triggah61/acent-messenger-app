import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/config.dart';

/// Language model for supported languages
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
      nativeName: json['nativeName'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'nativeName': nativeName,
    };
  }

  @override
  String toString() => nativeName;
}

/// Service for fetching application configuration from the backend
class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  static ConfigService get instance => _instance;

  // Cache for configuration data
  Map<String, dynamic>? _configCache;
  List<Language>? _supportedLanguages;

  /// Fetches the configuration from the backend
  Future<Map<String, dynamic>> getConfig() async {
    if (_configCache != null) {
      return _configCache!;
    }

    try {
      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/config/get'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _configCache = data['data'];

        // Parse supported languages
        if (_configCache!['supportedLanguages'] != null) {
          _supportedLanguages = (_configCache!['supportedLanguages'] as List)
              .map((lang) => Language.fromJson(lang))
              .toList();
        }

        return _configCache!;
      } else {
        throw Exception('Failed to fetch config: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching config: $e');
    }
  }

  /// Gets the list of supported languages
  Future<List<Language>> getSupportedLanguages() async {
    if (_supportedLanguages != null) {
      return _supportedLanguages!;
    }

    await getConfig();
    return _supportedLanguages ?? [];
  }

  /// Finds a language by its code
  Future<Language?> getLanguageByCode(String code) async {
    final languages = await getSupportedLanguages();
    try {
      return languages.firstWhere((lang) => lang.code == code);
    } catch (e) {
      return null;
    }
  }

  /// Clears the configuration cache
  void clearCache() {
    _configCache = null;
    _supportedLanguages = null;
  }

  /// Checks if maintenance mode is enabled
  /// Returns true if MAINTENANCE_MODE is "true", "1", or true
  Future<bool> isMaintenanceModeEnabled() async {
    try {
      final config = await getConfig();
      final maintenanceMode = config['MAINTENANCE_MODE'];
      
      // Handle different possible values
      if (maintenanceMode == null) {
        return false;
      }
      
      if (maintenanceMode is bool) {
        return maintenanceMode;
      }
      
      if (maintenanceMode is String) {
        return maintenanceMode.toLowerCase() == 'true' || maintenanceMode == '1';
      }
      
      if (maintenanceMode is int) {
        return maintenanceMode == 1;
      }
      
      return false;
    } catch (e) {
      // If there's an error fetching config, assume maintenance mode is off
      // This allows the app to continue functioning if config service fails
      print('ConfigService: Error checking maintenance mode: $e');
      return false;
    }
  }

  /// Force refresh config (clears cache and fetches fresh data)
  Future<Map<String, dynamic>> refreshConfig() async {
    clearCache();
    return await getConfig();
  }
}
