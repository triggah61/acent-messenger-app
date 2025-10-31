import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'dart:io';

/// On-device translation service using Google ML Kit
/// Replaces Gemini API with local translation models
class OnDeviceTranslationService {
  static final OnDeviceTranslationService _instance =
      OnDeviceTranslationService._internal();
  factory OnDeviceTranslationService() => _instance;
  OnDeviceTranslationService._internal();

  // Cache for translators to avoid recreating them
  final Map<String, OnDeviceTranslator> _translators = {};

  // Model manager for downloading language models
  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();

  /// Language code mapping for ML Kit (only core supported languages)
  static final Map<String, TranslateLanguage> _languageMap = {
    'en': TranslateLanguage.english,
    'bn': TranslateLanguage.bengali,
    'hi': TranslateLanguage.hindi,
    'es': TranslateLanguage.spanish,
    'fr': TranslateLanguage.french,
    'de': TranslateLanguage.german,
    'it': TranslateLanguage.italian,
    'pt': TranslateLanguage.portuguese,
    'ru': TranslateLanguage.russian,
    'ja': TranslateLanguage.japanese,
    'ko': TranslateLanguage.korean,
    'zh': TranslateLanguage.chinese,
    'ar': TranslateLanguage.arabic,
    'th': TranslateLanguage.thai,
    'vi': TranslateLanguage.vietnamese,
    'tr': TranslateLanguage.turkish,
    'pl': TranslateLanguage.polish,
    'nl': TranslateLanguage.dutch,
    'sv': TranslateLanguage.swedish,
    'da': TranslateLanguage.danish,
    'no': TranslateLanguage.norwegian,
    'fi': TranslateLanguage.finnish,
    'cs': TranslateLanguage.czech,
    'hu': TranslateLanguage.hungarian,
    'ro': TranslateLanguage.romanian,
    'bg': TranslateLanguage.bulgarian,
    'hr': TranslateLanguage.croatian,
    'sk': TranslateLanguage.slovak,
    'sl': TranslateLanguage.slovenian,
    'et': TranslateLanguage.estonian,
    'lv': TranslateLanguage.latvian,
    'lt': TranslateLanguage.lithuanian,
    'el': TranslateLanguage.greek,
    'he': TranslateLanguage.hebrew,
    'uk': TranslateLanguage.ukrainian,
    'be': TranslateLanguage.belarusian,
    'ka': TranslateLanguage.georgian,
    'kn': TranslateLanguage.kannada,
    'ta': TranslateLanguage.tamil,
    'te': TranslateLanguage.telugu,
    'gu': TranslateLanguage.gujarati,
    'mr': TranslateLanguage.marathi,
    'ur': TranslateLanguage.urdu,
  };

  /// Initialize the translation service
  /// Downloads required language models if not already present
  Future<void> initialize() async {
    try {
      print(
          'OnDeviceTranslationService: Initializing on-device translation...');

      // Check if we're online for initial model download
      bool isOnline = await _checkInternetConnection();

      if (isOnline) {
        print(
            'OnDeviceTranslationService: Internet available, downloading models...');
        await _downloadRequiredModels();
      } else {
        print(
            'OnDeviceTranslationService: No internet, using cached models if available');
      }

      print('OnDeviceTranslationService: ✅ Initialization complete');
    } catch (e) {
      print('OnDeviceTranslationService: ❌ Initialization failed: $e');
      rethrow;
    }
  }

  /// Check internet connection
  Future<bool> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Callback for download progress updates
  Function(String languageName, bool isDownloading)? _onModelDownloadProgress;

  /// Set callback for model download progress
  void setModelDownloadProgressCallback(
      Function(String languageName, bool isDownloading)? callback) {
    _onModelDownloadProgress = callback;
  }

  /// Download required language models
  Future<void> _downloadRequiredModels() async {
    try {
      // Download models for commonly used languages
      final commonLanguages = ['en', 'bn', 'hi', 'es', 'fr', 'de', 'ar', 'ko'];
      final languageNames = getLanguageInfo();

      for (final langCode in commonLanguages) {
        final language = _languageMap[langCode];
        if (language != null) {
          try {
            // Check if model is already downloaded
            final isDownloaded =
                await _modelManager.isModelDownloaded(language.bcpCode);
            if (isDownloaded) {
              print(
                  'OnDeviceTranslationService: ✅ Model already exists for $langCode');
              continue;
            }

            // Notify UI about download start
            final languageName = languageNames[langCode] ?? langCode;
            _onModelDownloadProgress?.call(languageName, true);

            await _modelManager.downloadModel(language.bcpCode);
            print(
                'OnDeviceTranslationService: ✅ Downloaded model for $langCode');

            // Notify UI about download completion
            _onModelDownloadProgress?.call(languageName, false);
          } catch (e) {
            print(
                'OnDeviceTranslationService: ⚠️ Failed to download model for $langCode: $e');
            // Notify UI about download failure
            final languageName = languageNames[langCode] ?? langCode;
            _onModelDownloadProgress?.call(languageName, false);
          }
        }
      }
    } catch (e) {
      print('OnDeviceTranslationService: Error downloading models: $e');
    }
  }

  /// Get or create a translator for the given language pair
  Future<OnDeviceTranslator> _getTranslator(
      String sourceLanguage, String targetLanguage) async {
    final key = '${sourceLanguage}_$targetLanguage';

    if (_translators.containsKey(key)) {
      return _translators[key]!;
    }

    final sourceLang = _languageMap[sourceLanguage];
    final targetLang = _languageMap[targetLanguage];

    if (sourceLang == null) {
      throw Exception('Unsupported source language: $sourceLanguage');
    }
    if (targetLang == null) {
      throw Exception('Unsupported target language: $targetLanguage');
    }

    // Check if models are available
    final sourceModelAvailable =
        await _modelManager.isModelDownloaded(sourceLang.bcpCode);
    final targetModelAvailable =
        await _modelManager.isModelDownloaded(targetLang.bcpCode);

    if (!sourceModelAvailable || !targetModelAvailable) {
      throw Exception(
          'Required translation models not available. Please check internet connection.');
    }

    final translator = OnDeviceTranslator(
      sourceLanguage: sourceLang,
      targetLanguage: targetLang,
    );

    _translators[key] = translator;
    return translator;
  }

  /// Translate text from source language to target language
  Future<String> translateText(
      String text, String sourceLanguage, String targetLanguage) async {
    try {
      if (text.trim().isEmpty) {
        return text;
      }

      print('OnDeviceTranslationService: Translating text...');
      print('  Source: $sourceLanguage');
      print('  Target: $targetLanguage');
      print(
          '  Text: "${text.substring(0, text.length > 50 ? 50 : text.length)}${text.length > 50 ? '...' : ''}"');

      final translator = await _getTranslator(sourceLanguage, targetLanguage);
      final translatedText = await translator.translateText(text);

      print('OnDeviceTranslationService: ✅ Translation successful');
      print(
          '  Result: "${translatedText.substring(0, translatedText.length > 50 ? 50 : translatedText.length)}${translatedText.length > 50 ? '...' : ''}"');

      return translatedText;
    } catch (e) {
      print('OnDeviceTranslationService: ❌ Translation failed: $e');
      throw Exception('Translation failed: $e');
    }
  }

  /// Check if translation is supported for the given language pair
  bool isTranslationSupported(String sourceLanguage, String targetLanguage) {
    return _languageMap.containsKey(sourceLanguage) &&
        _languageMap.containsKey(targetLanguage);
  }

  /// Get list of supported languages
  List<String> getSupportedLanguages() {
    return _languageMap.keys.toList();
  }

  /// Get detailed language information
  Map<String, String> getLanguageInfo() {
    return {
      'en': 'English',
      'bn': 'Bengali',
      'hi': 'Hindi',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'ja': 'Japanese',
      'ko': 'Korean',
      'zh': 'Chinese',
      'ar': 'Arabic',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'tr': 'Turkish',
      'pl': 'Polish',
      'nl': 'Dutch',
      'sv': 'Swedish',
      'da': 'Danish',
      'no': 'Norwegian',
      'fi': 'Finnish',
      'cs': 'Czech',
      'hu': 'Hungarian',
      'ro': 'Romanian',
      'bg': 'Bulgarian',
      'hr': 'Croatian',
      'sk': 'Slovak',
      'sl': 'Slovenian',
      'et': 'Estonian',
      'lv': 'Latvian',
      'lt': 'Lithuanian',
      'el': 'Greek',
      'he': 'Hebrew',
      'uk': 'Ukrainian',
      'be': 'Belarusian',
      'ka': 'Georgian',
      'kn': 'Kannada',
      'ta': 'Tamil',
      'te': 'Telugu',
      'gu': 'Gujarati',
      'mr': 'Marathi',
      'ur': 'Urdu',
    };
  }

  /// Check if a language model is downloaded
  Future<bool> isModelDownloaded(String languageCode) async {
    final language = _languageMap[languageCode];
    if (language == null) return false;

    return await _modelManager.isModelDownloaded(language.bcpCode);
  }

  /// Download a specific language model
  Future<void> downloadModel(String languageCode) async {
    final language = _languageMap[languageCode];
    if (language == null) {
      throw Exception('Unsupported language: $languageCode');
    }

    await _modelManager.downloadModel(language.bcpCode);
  }

  /// Dispose all translators and free resources
  Future<void> dispose() async {
    try {
      print('OnDeviceTranslationService: Disposing translators...');

      for (final translator in _translators.values) {
        await translator.close();
      }

      _translators.clear();
      print('OnDeviceTranslationService: ✅ Disposed successfully');
    } catch (e) {
      print('OnDeviceTranslationService: ❌ Error during disposal: $e');
    }
  }

  /// Get translation statistics
  Map<String, dynamic> getStats() {
    return {
      'cached_translators': _translators.length,
      'supported_languages': _languageMap.length,
      'translator_keys': _translators.keys.toList(),
    };
  }
}
