class Config {
  static const String awsS3Url = 'https://chingu.s3.ap-northeast-2.amazonaws.com';
  
  // Helper method to get full photo URL
  static String getPhotoUrl(String? photoPath) {
    if (photoPath == null || photoPath.isEmpty) return '';
    return '$awsS3Url/$photoPath';
  }
} 