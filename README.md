# 🚀 Acent Messenger - Community Edition




## 🚀 Project Overview


A comprehensive feature-rich, secure messaging and cryptocurrency wallet application built with Flutter for a modern messaging platform with integrated Bitcoin wallet functionality, real-time communication, and social features.

---

## 📱 Features

### 🔐 **Authentication & Security**
- **Phone-based Authentication** with OTP verification
- **Secure JWT Token Management** with Flutter Secure Storage
- **Password Reset** with email/SMS verification
- **Biometric Authentication** (Fingerprint, Face ID)
- **Two-Factor Authentication** support

### 💬 **Real-time Messaging**
- **Instant Messaging** with Socket.IO integration
- **Group Chats** with unlimited participants
- **Message Reactions** (👍 ❤️ 😂 😢 😠 😮 😭)
- **Message Replies** and threading
- **Typing Indicators** in real-time
- **Message Status** (Sent, Delivered, Read)
- **File Attachments** (Images, Documents, Media)

### 📞 **Audio & Video Calling**
- **WebRTC Integration** for high-quality calls
- **Audio Calls** with crystal clear sound
- **Video Calls** with HD quality
- **Group Calling** support
- **Call Recording** capabilities
- **Screen Sharing** functionality

### 🏦 **Cryptocurrency Wallet**
- **Bitcoin Wallet** with full functionality
- **Send & Receive** Bitcoin transactions
- **Transaction History** with detailed records
- **QR Code** generation and scanning
- **Multiple Fee Options** (Low, Medium, High priority)
- **Real-time Balance** updates
- **Security Features** for crypto storage

### 👥 **Contact Management**
- **Phone Contacts** synchronization
- **Add Friends** via phone number/QR code
- **Contact Search** and filtering
- **Profile Management** with photos
- **Status Updates** and activity


---

## 🚀 Quick Start

### Prerequisites

```bash
# Flutter SDK (>=3.2.3)
flutter --version

# Dart SDK
dart --version

# iOS development (macOS only)
xcode-select --install

# Android development
# Install Android Studio with Android SDK
```

### Installation

1. **Clone the Repository**
```bash
git clone https://github.com/triggah61/acent-messenger-app.git
cd acent-messenger-app
```

2. **Install Dependencies**
```bash
flutter pub get
```

3. **Configure Environment**
```bash
# Update API endpoint in lib/constants/config.dart
# Set your backend server URL
static const String baseApiUrl = 'http://your-server:8000/api';
```

4. **Run the Application**
```bash
# iOS Simulator
flutter run -d ios

# Android Emulator
flutter run -d android

# Web Browser
flutter run -d chrome
```

### Build for Production

```bash
# iOS Release Build
flutter build ios --release

# Android APK
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release
```

---

## 🏗️ Architecture

### **State Management**
- **Provider Pattern** for application state
- **Service Layer** for business logic
- **Repository Pattern** for data access

### **Project Structure**
```
lib/
├── constants/          # App-wide constants
│   ├── colors.dart    # Color schemes
│   └── config.dart    # API configuration
├── models/            # Data models
│   ├── message.dart   # Chat message model
│   ├── chat_session.dart  # Chat session model
│   ├── wallet.dart    # Cryptocurrency wallet
│   └── profile.dart   # User profile model
├── providers/         # State management
│   ├── auth_provider.dart     # Authentication state
│   ├── chat_provider.dart     # Chat state
│   ├── wallet_provider.dart   # Wallet state
│   └── contacts_provider.dart # Contacts state
├── services/          # Business logic layer
│   ├── auth_service.dart      # Authentication API
│   ├── socket_service.dart    # Real-time messaging
│   ├── wallet_service.dart    # Cryptocurrency operations
│   └── chat_service.dart      # Chat API integration
├── views/             # UI screens
│   ├── authentication/       # Login, signup, OTP
│   ├── chats/               # Chat interfaces
│   ├── wallet/              # Cryptocurrency wallet
│   ├── profile/             # User profile management
│   ├── contacts/            # Contact management
│   └── settings/            # App settings
├── widgets/           # Reusable UI components
├── commonwidgets/     # Shared widget library
└── main.dart         # Application entry point
```

### **Key Technologies**
- **Flutter** 3.2.3+ (Cross-platform UI framework)
- **Dart** 3.0+ (Programming language)
- **Provider** (State management)
- **Socket.IO** (Real-time communication)
- **HTTP** (REST API integration)
- **Flutter Secure Storage** (Secure data storage)
- **Cached Network Image** (Image optimization)

---

## 🔧 Development

### **Development Setup**

1. **Configure IDE**
```bash
# VS Code extensions
code --install-extension dart-code.flutter
code --install-extension dart-code.dart-code

# Android Studio plugins
# Install Flutter and Dart plugins
```

2. **Environment Variables**
```dart
// lib/constants/config.dart
class Config {
  static const String baseApiUrl = 'http://localhost:8000/api';
  static const String awsS3Url = 'https://your-bucket.s3.amazonaws.com';
}
```

3. **Debug Configuration**
```bash
# Enable debug logging
flutter run --debug

# Performance profiling
flutter run --profile

# Release testing
flutter run --release
```

### **Code Style & Standards**

- **Dart Style Guide** compliance
- **Null Safety** implementation
- **Widget Testing** for UI components
- **Unit Testing** for business logic
- **Integration Testing** for user flows

### **Dependencies Management**

```yaml
# Core Dependencies
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2              # State management
  http: ^1.2.2                  # HTTP client
  socket_io_client: ^2.0.3+1    # Real-time messaging
  flutter_secure_storage: ^9.0.0 # Secure storage
  
# UI & UX
  cached_network_image: ^3.4.1  # Image caching
  photo_view: ^0.14.0           # Image viewer
  emoji_picker_flutter: ^4.3.0  # Emoji support
  
# Device Features
  image_picker: ^1.0.4          # Camera/gallery access
  permission_handler: ^11.3.0   # Device permissions
  qr_flutter: ^4.1.0           # QR code generation
  mobile_scanner: ^3.5.7       # QR code scanning
  
# Utilities
  timeago: ^3.7.1              # Time formatting
  intl: ^0.19.0                # Internationalization
  url_launcher: ^6.2.4         # External URLs
```

### **Socket.IO Events**
```dart
// Real-time messaging
join_chat              # Join chat session
leave_chat             # Leave chat session
new_message            # Receive new message
typing                 # Typing indicator
message_reactions_updated  # Message reaction updates

```

---

## 📱 Platform-Specific Configuration

### **iOS Configuration**

```xml
<!-- ios/Runner/Info.plist -->
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls and photo sharing</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice calls and messages</string>
<key>NSContactsUsageDescription</key>
<string>This app needs contacts access to find friends</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access for location sharing</string>
```

### **Android Configuration**

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.READ_CONTACTS" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

---

## 🚀 Deployment

### **App Store Deployment (iOS)**

1. **Configure Signing**
```bash
# Update ios/Runner.xcodeproj
# Set Development Team and Bundle Identifier
```

2. **Build Archive**
```bash
flutter build ios --release
open ios/Runner.xcworkspace
# Archive in Xcode and upload to App Store Connect
```

### **Google Play Store (Android)**

1. **Generate Signing Key**
```bash
keytool -genkey -v -keystore ~/key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias key
```

2. **Configure Signing**
```properties
# android/key.properties
storePassword=<store_password>
keyPassword=<key_password>
keyAlias=key
storeFile=<path_to_key.jks>
```

3. **Build Release**
```bash
flutter build appbundle --release
# Upload to Google Play Console
```

### **Web Deployment**

```bash
# Build for web
flutter build web --release

# Deploy to Firebase Hosting
firebase deploy

# Deploy to Netlify
# Upload build/web folder to Netlify
```

---

## 🔧 Configuration

### **Backend Requirements**

The app requires a compatible backend server with the following features:
- **REST API** for user management and data operations
- **Socket.IO Server** for real-time messaging
- **WebRTC Signaling Server** for audio/video calls
- **Bitcoin Integration** for cryptocurrency operations
- **File Upload Service** for media attachments

### **Environment Setup**

```dart
// lib/constants/config.dart
class Config {
  // Update these URLs to match your backend
  static const String baseApiUrl = 'https://your-api-server.com/api';
  static const String awsS3Url = 'https://your-s3-bucket.amazonaws.com';
  
  static String getPhotoUrl(String? photoPath) {
    if (photoPath == null || photoPath.isEmpty) return '';
    return '$awsS3Url/$photoPath';
  }
}
```

---

## 🧪 Testing

### **Run Tests**
```bash
# Unit tests
flutter test

# Integration tests
flutter test integration_test/

# Widget tests
flutter test test/widget_test.dart
```

### **Code Coverage**
```bash
# Generate coverage report
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

---

## 📖 Documentation

### **Additional Resources**
- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Language Guide](https://dart.dev/guides)
- [Provider State Management](https://pub.dev/packages/provider)
- [Socket.IO Client](https://pub.dev/packages/socket_io_client)
- [WebRTC Implementation Guide](https://webrtc.org/getting-started/)

---

## 🤝 Contributing

1. **Fork the Repository**
2. **Create Feature Branch** (`git checkout -b feature/amazing-feature`)
3. **Commit Changes** (`git commit -m 'Add amazing feature'`)
4. **Push to Branch** (`git push origin feature/amazing-feature`)
5. **Open Pull Request**

### **Development Guidelines**
- Follow Dart/Flutter style guidelines
- Write comprehensive tests
- Update documentation
- Ensure cross-platform compatibility

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🆘 Support

### **Getting Help**
- 📧 **Email Support**: support@acentmessenger.com
- 💬 **Community Chat**: [Join our Discord](https://discord.gg/acentmessenger)
- 📚 **Documentation**: [Wiki Pages](https://github.com/your-org/acent-messenger/wiki)
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/your-org/acent-messenger/issues)

### **System Requirements**
- **iOS**: 12.0+
- **Android**: API level 21+ (Android 5.0)
- **Flutter**: 3.2.3+
- **Dart**: 3.0+

---

**Built with ❤️ by the Acent Team**