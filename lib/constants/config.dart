class Config {
  static const String awsS3Url = 'https://chingu.s3.ap-northeast-2.amazonaws.com';
  static const String baseApiUrl = 'http://192.168.0.104:8000/api';
  // static const String baseApiUrl = 'http://109.123.230.44:8000/api';
  
  
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