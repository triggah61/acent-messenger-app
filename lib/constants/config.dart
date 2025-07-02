import 'env_config.dart';

class Config {
  static String get awsS3Url => EnvConfig.awsS3Url;
  static String get baseApiUrl => EnvConfig.baseApiUrl;

  // Pusher Configuration
  static String get pusherKey => EnvConfig.pusherKey;
  static String get pusherCluster => EnvConfig.pusherCluster;
  static bool get pusherUseTLS => EnvConfig.pusherUseTLS;

  // Helper method to get full photo URL
  static String getPhotoUrl(String? photoPath) =>
      EnvConfig.getPhotoUrl(photoPath);

  static String wordToUpperCase(String? value) =>
      EnvConfig.wordToUpperCase(value);
}
