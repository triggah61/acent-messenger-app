import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';

/// Simplified FCM Service for token retrieval only
class SimpleFCMService {
  static final SimpleFCMService _instance = SimpleFCMService._internal();
  factory SimpleFCMService() => _instance;
  SimpleFCMService._internal();

  static SimpleFCMService get instance => _instance;

  FirebaseMessaging? _messaging;
  String? _currentToken;
  bool _isInitialized = false;

  /// Initialize Firebase and get messaging instance
  Future<bool> initialize() async {
    try {
      if (_isInitialized) {
        debugPrint('SimpleFCMService: Already initialized');
        return true;
      }

      debugPrint('SimpleFCMService: Starting initialization...');

      // Initialize Firebase if not already done
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
          debugPrint('SimpleFCMService: Firebase initialized');
        } else {
          debugPrint('SimpleFCMService: Firebase already initialized');
        }
      } catch (e) {
        debugPrint('SimpleFCMService: Firebase init error: $e');
        return false;
      }

      // Get messaging instance
      try {
        _messaging = FirebaseMessaging.instance;
        debugPrint('SimpleFCMService: Messaging instance created');
      } catch (e) {
        debugPrint('SimpleFCMService: Messaging instance error: $e');
        return false;
      }

      // Request basic permission
      try {
        final settings = await _messaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint(
            'SimpleFCMService: Permission status: ${settings.authorizationStatus}');
      } catch (e) {
        debugPrint('SimpleFCMService: Permission error: $e');
        // Continue anyway
      }

      _isInitialized = true;
      debugPrint('SimpleFCMService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('SimpleFCMService: Initialization failed: $e');
      return false;
    }
  }

  /// Get FCM token
  Future<String?> getToken() async {
    try {
      if (!_isInitialized) {
        debugPrint(
            'SimpleFCMService: Not initialized, attempting to initialize...');
        final success = await initialize();
        if (!success) {
          debugPrint(
              'SimpleFCMService: Failed to initialize for token retrieval');
          return null;
        }
      }

      if (_messaging == null) {
        debugPrint('SimpleFCMService: Messaging instance is null');
        return null;
      }

      debugPrint('SimpleFCMService: Requesting token...');
      final token = await _messaging!.getToken();

      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        debugPrint(
            'SimpleFCMService: Token obtained: ${token.substring(0, 20)}...');
        return token;
      } else {
        debugPrint('SimpleFCMService: Token is null or empty');
        return null;
      }
    } catch (e) {
      debugPrint('SimpleFCMService: Error getting token: $e');
      return null;
    }
  }

  /// Get current token without making network call
  String? get currentToken => _currentToken;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get platform string
  String getPlatform() {
    if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    } else {
      return 'web';
    }
  }
}
