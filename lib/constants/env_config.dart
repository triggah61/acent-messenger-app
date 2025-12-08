import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  // Ensure the environment is loaded
  static bool _isLoaded = false;

  static Future<void> initialize() async {
    if (!_isLoaded) {
      await dotenv.load(fileName: ".env");
      _isLoaded = true;
    }
  }

  // API Configuration
  static String get baseApiUrl =>
      dotenv.env['BASE_API_URL'] ?? 'http://localhost:8000/api';
  static String get awsS3Url => dotenv.env['AWS_S3_URL'] ?? '';

  // Pusher Configuration
  static String get pusherKey => dotenv.env['PUSHER_KEY'] ?? '';
  static String get pusherCluster => dotenv.env['PUSHER_CLUSTER'] ?? 'mt1';
  static bool get pusherUseTLS =>
      (dotenv.env['PUSHER_USE_TLS'] ?? 'true').toLowerCase() == 'true';

  // Firebase Web Configuration
  static String get firebaseWebApiKey =>
      dotenv.env['FIREBASE_WEB_API_KEY'] ?? '';
  static String get firebaseWebAppId => dotenv.env['FIREBASE_WEB_APP_ID'] ?? '';
  static String get firebaseWebMessagingSenderId =>
      dotenv.env['FIREBASE_WEB_MESSAGING_SENDER_ID'] ?? '';
  static String get firebaseWebProjectId =>
      dotenv.env['FIREBASE_WEB_PROJECT_ID'] ?? '';
  static String get firebaseWebAuthDomain =>
      dotenv.env['FIREBASE_WEB_AUTH_DOMAIN'] ?? '';
  static String get firebaseWebStorageBucket =>
      dotenv.env['FIREBASE_WEB_STORAGE_BUCKET'] ?? '';
  static String get firebaseWebMeasurementId =>
      dotenv.env['FIREBASE_WEB_MEASUREMENT_ID'] ?? '';

  // Firebase Android Configuration
  static String get firebaseAndroidApiKey =>
      dotenv.env['FIREBASE_ANDROID_API_KEY'] ?? '';
  static String get firebaseAndroidAppId =>
      dotenv.env['FIREBASE_ANDROID_APP_ID'] ?? '';

  // Firebase iOS Configuration
  static String get firebaseIosApiKey =>
      dotenv.env['FIREBASE_IOS_API_KEY'] ?? '';
  static String get firebaseIosAppId => dotenv.env['FIREBASE_IOS_APP_ID'] ?? '';
  static String get firebaseIosClientId =>
      dotenv.env['FIREBASE_IOS_CLIENT_ID'] ?? '';
  static String get firebaseIosBundleId =>
      dotenv.env['FIREBASE_IOS_BUNDLE_ID'] ?? '';

  // Firebase macOS Configuration (usually same as iOS)
  static String get firebaseMacosApiKey =>
      dotenv.env['FIREBASE_MACOS_API_KEY'] ?? firebaseIosApiKey;
  static String get firebaseMacosAppId =>
      dotenv.env['FIREBASE_MACOS_APP_ID'] ?? firebaseIosAppId;
  static String get firebaseMacosClientId =>
      dotenv.env['FIREBASE_MACOS_CLIENT_ID'] ?? firebaseIosClientId;
  static String get firebaseMacosBundleId =>
      dotenv.env['FIREBASE_MACOS_BUNDLE_ID'] ?? firebaseIosBundleId;

  // Agora Configuration
  static String get agoraAppId =>
      dotenv.env['AGORA_APP_ID'] ?? '7ee53c636c6a4572a2c799c95f1f4f34';
  static String get agoraAppCertificate =>
      dotenv.env['AGORA_APP_CERTIFICATE'] ?? '';

  // Call Configuration
  static int get callTimeoutSeconds =>
      int.tryParse(dotenv.env['CALL_TIMEOUT_SECONDS'] ?? '30') ?? 30;
  static int get tokenRefreshThresholdSeconds =>
      int.tryParse(dotenv.env['TOKEN_REFRESH_THRESHOLD_SECONDS'] ?? '300') ??
      300;

  // Google Play Billing Configuration
  static bool get useGooglePlaySandbox =>
      (dotenv.env['GOOGLE_PLAY_USE_SANDBOX'] ?? 'true').toLowerCase() == 'true';
  static String get googlePlayPackageName =>
      dotenv.env['GOOGLE_PLAY_PACKAGE_NAME'] ?? 'com.qmessenger.app';
  static String get googlePlayTopUpProductId =>
      dotenv.env['GOOGLE_PLAY_TOPUP_PRODUCT_ID'] ?? 'com.qmessenger.app.topup';
  static String get googlePlayTopUpSandboxProductId =>
      dotenv.env['GOOGLE_PLAY_TOPUP_SANDBOX_PRODUCT_ID'] ?? 'com.qmessenger.app.topup.test';

  // Helper method to get full photo URL
  static String getPhotoUrl(String? photoPath) {
    if (photoPath == null || photoPath.isEmpty) {
      // Return a placeholder image URL instead of empty string
      return 'https://via.placeholder.com/150/CCCCCC/FFFFFF?text=No+Image';
    }
    if (awsS3Url.isEmpty) {
      return 'https://via.placeholder.com/150/CCCCCC/FFFFFF?text=No+Image';
    }
    return '$awsS3Url/$photoPath';
  }

  static String wordToUpperCase(String? value) {
    if (value == null || value.isEmpty) return '';
    return value[0].toUpperCase() + value.substring(1);
  }
}
