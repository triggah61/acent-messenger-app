import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

/// Location detection result with status and language code
class LocationResult {
  final String languageCode;
  final LocationStatus status;
  final String? message;

  LocationResult({
    required this.languageCode,
    required this.status,
    this.message,
  });
}

/// Status of location detection
enum LocationStatus {
  success,              // Location detected successfully
  serviceDisabled,      // Location services are OFF
  permissionDenied,     // User denied permission
  permissionDeniedForever, // User permanently denied permission
  error,                // Other error occurred
}

/// Service for getting device location and determining language based on country
class GeolocationService {
  static final GeolocationService _instance = GeolocationService._internal();
  factory GeolocationService() => _instance;
  GeolocationService._internal();

  static GeolocationService get instance => _instance;

  /// Country to primary language code mapping
  /// Maps ISO country codes to language codes (ISO 639-1)
  static const Map<String, String> _countryToLanguage = {
    // Asia
    'JP': 'ja', // Japan → Japanese
    'CN': 'zh', // China → Chinese (Simplified)
    'TW': 'zh', // Taiwan → Chinese (Traditional)
    'KR': 'ko', // South Korea → Korean
    'TH': 'th', // Thailand → Thai
    'VN': 'vi', // Vietnam → Vietnamese
    'ID': 'id', // Indonesia → Indonesian
    'MY': 'ms', // Malaysia → Malay
    'PH': 'fil', // Philippines → Filipino
    'IN': 'hi', // India → Hindi
    'PK': 'ur', // Pakistan → Urdu
    'BD': 'bn', // Bangladesh → Bengali
    'TR': 'tr', // Turkey → Turkish
    'SA': 'ar', // Saudi Arabia → Arabic
    'AE': 'ar', // UAE → Arabic
    'IL': 'he', // Israel → Hebrew

    // Europe
    'GB': 'en', // United Kingdom → English
    'IE': 'en', // Ireland → English
    'FR': 'fr', // France → French
    'DE': 'de', // Germany → German
    'IT': 'it', // Italy → Italian
    'ES': 'es', // Spain → Spanish
    'PT': 'pt', // Portugal → Portuguese
    'NL': 'nl', // Netherlands → Dutch
    'BE': 'nl', // Belgium → Dutch (also French)
    'SE': 'sv', // Sweden → Swedish
    'NO': 'no', // Norway → Norwegian
    'DK': 'da', // Denmark → Danish
    'FI': 'fi', // Finland → Finnish
    'PL': 'pl', // Poland → Polish
    'RU': 'ru', // Russia → Russian
    'UA': 'uk', // Ukraine → Ukrainian
    'GR': 'el', // Greece → Greek
    'CZ': 'cs', // Czech Republic → Czech
    'RO': 'ro', // Romania → Romanian
    'HU': 'hu', // Hungary → Hungarian

    // Americas
    'US': 'en', // United States → English
    'CA': 'en', // Canada → English (also French)
    'MX': 'es', // Mexico → Spanish
    'BR': 'pt', // Brazil → Portuguese
    'AR': 'es', // Argentina → Spanish
    'CL': 'es', // Chile → Spanish
    'CO': 'es', // Colombia → Spanish
    'PE': 'es', // Peru → Spanish
    'VE': 'es', // Venezuela → Spanish

    // Africa
    'ZA': 'en', // South Africa → English
    'EG': 'ar', // Egypt → Arabic
    'MA': 'ar', // Morocco → Arabic
    'NG': 'en', // Nigeria → English
    'KE': 'en', // Kenya → English
    'ET': 'am', // Ethiopia → Amharic

    // Oceania
    'AU': 'en', // Australia → English
    'NZ': 'en', // New Zealand → English

    // Default fallback
    'DEFAULT': 'en', // Default to English
  };

  /// Get current location and determine language based on country
  /// Returns LocationResult with language code and status
  Future<LocationResult> getLanguageFromLocation() async {
    try {
      debugPrint('GeolocationService: Getting language from current location...');

      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('GeolocationService: ⚠️ Location services are disabled');
        return LocationResult(
          languageCode: _countryToLanguage['DEFAULT']!,
          status: LocationStatus.serviceDisabled,
          message: 'Location services are disabled',
        );
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        debugPrint('GeolocationService: Requesting location permission...');
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          debugPrint('GeolocationService: ❌ Location permission denied');
          return LocationResult(
            languageCode: _countryToLanguage['DEFAULT']!,
            status: LocationStatus.permissionDenied,
            message: 'Location permission denied',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('GeolocationService: ❌ Location permission permanently denied');
        return LocationResult(
          languageCode: _countryToLanguage['DEFAULT']!,
          status: LocationStatus.permissionDeniedForever,
          message: 'Location permission permanently denied',
        );
      }

      // Get current position
      debugPrint('GeolocationService: Fetching current position...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      debugPrint('GeolocationService: Position: ${position.latitude}, ${position.longitude}');

      // Get address from coordinates (reverse geocoding)
      debugPrint('GeolocationService: Reverse geocoding coordinates...');
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final countryCode = place.isoCountryCode?.toUpperCase();

        debugPrint('GeolocationService: Country detected: ${place.country} ($countryCode)');

        if (countryCode != null && _countryToLanguage.containsKey(countryCode)) {
          final languageCode = _countryToLanguage[countryCode]!;
          debugPrint('GeolocationService: ✅ Language selected: $languageCode');
          return LocationResult(
            languageCode: languageCode,
            status: LocationStatus.success,
            message: 'Location detected: ${place.country}',
          );
        }
      }

      debugPrint('GeolocationService: Country not mapped, returning default language');
      return LocationResult(
        languageCode: _countryToLanguage['DEFAULT']!,
        status: LocationStatus.success,
        message: 'Location detected but country not mapped',
      );
    } catch (e) {
      debugPrint('GeolocationService: ❌ Error getting location: $e');
      return LocationResult(
        languageCode: _countryToLanguage['DEFAULT']!,
        status: LocationStatus.error,
        message: 'Error: $e',
      );
    }
  }

  /// Get language code from country code (for manual country selection)
  static String getLanguageFromCountryCode(String countryCode) {
    return _countryToLanguage[countryCode.toUpperCase()] ??
        _countryToLanguage['DEFAULT']!;
  }

  /// Check if a country code is supported
  static bool isCountrySupported(String countryCode) {
    return _countryToLanguage.containsKey(countryCode.toUpperCase());
  }
}
