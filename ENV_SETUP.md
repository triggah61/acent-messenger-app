# Environment Variables Setup for Acent Messenger

This guide explains how to set up and manage environment variables for the Acent Messenger Flutter app to keep sensitive API keys and configurations secure.

## Overview

The app now uses environment variables to manage sensitive configuration data including:
- Firebase API keys for all platforms
- Pusher realtime messaging configuration
- API endpoints
- AWS S3 configuration

## Setup Instructions

### 1. Copy Environment Template

Copy the example environment file to create your own:

```bash
cd acent-app
cp .env.example .env
```

### 2. Update Environment Variables

Edit the `.env` file with your actual API keys and configuration:

```bash
nano .env
# or
code .env
```

### 3. Required Environment Variables

#### API Configuration
- `BASE_API_URL`: Your backend API endpoint
- `AWS_S3_URL`: AWS S3 bucket URL for file storage

#### Pusher Configuration
- `PUSHER_KEY`: Pusher application key
- `PUSHER_CLUSTER`: Pusher cluster (e.g., 'mt1')
- `PUSHER_USE_TLS`: Whether to use TLS (true/false)

#### Firebase Configuration
**Web Platform:**
- `FIREBASE_WEB_API_KEY`
- `FIREBASE_WEB_APP_ID`
- `FIREBASE_WEB_MESSAGING_SENDER_ID`
- `FIREBASE_WEB_PROJECT_ID`
- `FIREBASE_WEB_AUTH_DOMAIN`
- `FIREBASE_WEB_STORAGE_BUCKET`
- `FIREBASE_WEB_MEASUREMENT_ID`

**Android Platform:**
- `FIREBASE_ANDROID_API_KEY`
- `FIREBASE_ANDROID_APP_ID`

**iOS Platform:**
- `FIREBASE_IOS_API_KEY`
- `FIREBASE_IOS_APP_ID`
- `FIREBASE_IOS_CLIENT_ID`
- `FIREBASE_IOS_BUNDLE_ID`

**macOS Platform:**
- `FIREBASE_MACOS_API_KEY`
- `FIREBASE_MACOS_APP_ID`
- `FIREBASE_MACOS_CLIENT_ID`
- `FIREBASE_MACOS_BUNDLE_ID`

### 4. Install Dependencies

Make sure to run `flutter pub get` to install the new `flutter_dotenv` dependency:

```bash
flutter pub get
```

## Security Notes

### ⚠️ Important Security Considerations

1. **Never commit `.env` files**: The `.env` file is already added to `.gitignore` to prevent accidental commits
2. **Use `.env.example`**: Always update the example file when adding new environment variables
3. **Team Setup**: Each team member needs their own `.env` file with their own API keys
4. **Production Deployment**: Use platform-specific environment variable management for production

### GitIgnore Protection

The `.env` file is automatically ignored by git to prevent accidentally committing sensitive data:

```gitignore
# Environment variables (contains sensitive API keys)
.env
```

## How It Works

### Environment Loading

The app loads environment variables during startup in `main.dart`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize environment configuration
  await EnvConfig.initialize();
  
  // Rest of app initialization...
}
```

### Configuration Access

Environment variables are accessed through the `EnvConfig` class:

```dart
// API endpoints
String apiUrl = EnvConfig.baseApiUrl;

// Firebase configuration
String firebaseKey = EnvConfig.firebaseWebApiKey;

// Pusher configuration
String pusherKey = EnvConfig.pusherKey;
```

### Fallback Values

Each environment variable has a sensible fallback value to prevent crashes if a variable is missing.

## Troubleshooting

### Common Issues

1. **App crashes on startup**: Check that your `.env` file exists and has all required variables
2. **Firebase not working**: Verify all Firebase environment variables are correctly set
3. **API calls failing**: Check that `BASE_API_URL` is correctly configured

### Debugging

Add debug prints to verify environment loading:

```dart
print('API URL: ${EnvConfig.baseApiUrl}');
print('Pusher Key: ${EnvConfig.pusherKey}');
```

## Development vs Production

### Development
- Use `.env` file for local development
- Each developer maintains their own `.env` file
- Use development/staging API endpoints

### Production
- Configure environment variables through your deployment platform
- Use production API endpoints and keys
- Ensure all sensitive data is properly secured

## Migration from Hardcoded Values

The following files were updated to use environment variables:
- `lib/constants/config.dart` - Now uses `EnvConfig`
- `lib/firebase_options.dart` - Uses environment variables for Firebase config
- `lib/main.dart` - Initializes environment configuration

All existing functionality remains the same, but configuration is now loaded from environment variables instead of hardcoded values. 