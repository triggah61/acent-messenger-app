class Config {
  static const String awsS3Url =
      'https://chingu.s3.ap-northeast-2.amazonaws.com';
  static const String baseApiUrl = 'http://192.168.0.104:8000/api';
  // static const String baseApiUrl = 'http://109.123.230.44:8000/api';

  // Pusher Configuration
  static const String pusherKey = '68cd330ba1a5ca82a2bb';
  static const String pusherCluster = 'mt1';
  static const bool pusherUseTLS = true;

  // Helper method to get full photo URL
  static String getPhotoUrl(String? photoPath) {
    if (photoPath == null || photoPath.isEmpty) return '';
    return '$awsS3Url/$photoPath';
  }

  static String wordToUpperCase(String? value) {
    if (value == null || value.isEmpty) return '';
    return value[0].toUpperCase() + value.substring(1);
  }
}
