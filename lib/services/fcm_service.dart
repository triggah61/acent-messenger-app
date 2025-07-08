import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../constants/config.dart';
import '../firebase_options.dart';
import '../services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'navigation_service.dart';

/// Firebase Cloud Messaging (FCM) Service
/// Handles push notifications, token registration, and local notifications
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  static FCMService get instance => _instance;

  FirebaseMessaging? _messaging;
  FlutterLocalNotificationsPlugin? _localNotifications;
  final AuthService _authService = AuthService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _isInitialized = false;
  String? _currentToken;
  String? _deviceId;

  // Stream controllers for notification events
  final StreamController<RemoteMessage> _messageStreamController =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<String> _tokenRefreshStreamController =
      StreamController<String>.broadcast();

  // Getters for streams
  Stream<RemoteMessage> get onMessage => _messageStreamController.stream;
  Stream<String> get onTokenRefresh => _tokenRefreshStreamController.stream;

  bool get isInitialized => _isInitialized;
  String? get currentToken => _currentToken;

  /// Initialize FCM service
  Future<bool> initialize() async {
    try {
      if (_isInitialized) {
        debugPrint('FCMService: Already initialized');
        return true;
      }

      debugPrint('FCMService: Starting initialization...');

      // Initialize Firebase
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('FCMService: Firebase initialized successfully');
      } catch (e) {
        debugPrint('FCMService: Firebase initialization error: $e');
        // Try to continue anyway, Firebase might already be initialized
      }

      _messaging = FirebaseMessaging.instance;
      debugPrint('FCMService: FirebaseMessaging instance created');

      // Request permissions first
      final permissionGranted = await _requestPermissions();
      if (!permissionGranted) {
        debugPrint('FCMService: Permission denied, but continuing...');
        // Continue anyway, permissions might be granted later
      }

      // Get device info (optional)
      try {
        await _getDeviceInfo();
      } catch (e) {
        debugPrint('FCMService: Device info error (continuing): $e');
        _deviceId = 'unknown';
      }

      // Initialize local notifications (optional)
      try {
        await _initializeLocalNotifications();
      } catch (e) {
        debugPrint('FCMService: Local notifications error (continuing): $e');
      }

      // Setup message handlers
      try {
        _setupMessageHandlers();
      } catch (e) {
        debugPrint('FCMService: Message handlers error (continuing): $e');
      }

      // Get initial token (most important part)
      try {
        await _getAndStoreToken();
      } catch (e) {
        debugPrint('FCMService: Token retrieval error: $e');
      }

      // Listen for token refresh
      try {
        _messaging!.onTokenRefresh.listen((token) {
          debugPrint('FCMService: Token refreshed: $token');
          _currentToken = token;
          _tokenRefreshStreamController.add(token);
          _updateTokenOnServer(token);
        });
      } catch (e) {
        debugPrint('FCMService: Token refresh listener error: $e');
      }

      _isInitialized = true;
      debugPrint('FCMService: Initialized successfully');
      return true;
    } catch (e) {
      debugPrint('FCMService: Error initializing: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications!.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    // Set up iOS notification categories
    if (Platform.isIOS) {
      await _setupIOSNotificationCategories();
    }

    // Create notification channels for Android
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications!
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // Channel for regular messages
      const messagesChannel = AndroidNotificationChannel(
        'acent_messages',
        'Acent Messages',
        description: 'Notification channel for Acent Messenger',
        importance: Importance.high,
      );

      // Channel for incoming calls with ringtone
      final callsChannel = AndroidNotificationChannel(
        'acent_calls',
        'Acent Calls',
        description: 'Notification channel for incoming calls',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        enableLights: true,
        showBadge: true,
      );

      await androidPlugin?.createNotificationChannel(messagesChannel);
      await androidPlugin?.createNotificationChannel(callsChannel);
    }
  }

  /// Set up iOS notification categories with actions
  Future<void> _setupIOSNotificationCategories() async {
    try {
      final iosPlugin = _localNotifications!
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();

      if (iosPlugin != null) {
        await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      debugPrint(
          'FCMService: Error setting up iOS notification categories: $e');
    }
  }

  /// Handle local notification tap
  void _onLocalNotificationTapped(NotificationResponse response) {
    debugPrint('FCMService: Local notification tapped: ${response.payload}');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        // Only handle navigation (no action buttons anymore)
        _handleNotificationNavigation(data);
      } catch (e) {
        debugPrint('FCMService: Error parsing notification payload: $e');
      }
    }
  }

  // /// Handle call action button presses (DISABLED - removed action buttons)
  // void _handleCallAction(String actionId, Map<String, dynamic> data) {
  //   debugPrint('FCMService: Handling call action: $actionId');

  //   final callId = data['call_id'] as String? ?? data['callId'] as String?;

  //   if (callId == null) {
  //     debugPrint('FCMService: No call ID found in notification data');
  //     return;
  //   }

  //   switch (actionId) {
  //     case 'answer_call':
  //       debugPrint('FCMService: Answer call action for call: $callId');
  //       _handleAnswerCall(callId, data);
  //       break;
  //     case 'decline_call':
  //       debugPrint('FCMService: Decline call action for call: $callId');
  //       _handleDeclineCall(callId, data);
  //       break;
  //     default:
  //       debugPrint('FCMService: Unknown action: $actionId');
  //       break;
  //   }
  // }

  // /// Handle answer call action (DISABLED - removed action buttons)
  // void _handleAnswerCall(String callId, Map<String, dynamic> data) {
  //   debugPrint('FCMService: Answering call: $callId');

  //   // Clear the call notification
  //   _clearCallNotification(callId);

  //   // Navigate to the call screen
  //   NavigationService.instance.navigateToCall(
  //     callId: callId,
  //     callType: data['callType'] as String? ?? 'voice',
  //     additionalData: data,
  //   );
  // }

  // /// Handle decline call action (DISABLED - removed action buttons)
  // void _handleDeclineCall(String callId, Map<String, dynamic> data) async {
  //   debugPrint('FCMService: Declining call: $callId');

  //   // Clear the call notification
  //   _clearCallNotification(callId);

  //   try {
  //     // Call the decline API
  //     final token = await _authService.getToken();
  //     if (token != null) {
  //       final response = await http.post(
  //         Uri.parse('${Config.baseApiUrl}/user/call/decline/$callId'),
  //         headers: {
  //           'Content-Type': 'application/json',
  //           'Authorization': 'Bearer $token',
  //         },
  //       );

  //       if (response.statusCode == 200) {
  //         debugPrint('FCMService: Call declined successfully');
  //       } else {
  //         debugPrint(
  //             'FCMService: Failed to decline call: ${response.statusCode}');
  //       }
  //     }
  //   } catch (e) {
  //     debugPrint('FCMService: Error declining call: $e');
  //   }
  // }

  /// Clear call notification
  void _clearCallNotification(String callId) {
    _localNotifications?.cancel(callId.hashCode);
  }

  /// Handle notification navigation
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    debugPrint('FCMService: Handling notification navigation with data: $data');

    // Use the navigation service to handle the routing
    NavigationService.instance.handleNotificationData(data);
  }

  /// Request notification permissions
  Future<bool> _requestPermissions() async {
    final settings = await _messaging!.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint(
        'FCMService: Permission status: ${settings.authorizationStatus}');

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Get device information
  Future<void> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
      }

      debugPrint('FCMService: Device ID: $_deviceId');
    } catch (e) {
      debugPrint('FCMService: Error getting device info: $e');
      _deviceId = 'unknown';
    }
  }

  /// Setup message handlers
  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
          'FCMService: Foreground message received: ${message.messageId}');
      _messageStreamController.add(message);
      _showLocalNotification(message);
    });

    // Handle background messages
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
          'FCMService: App opened from notification: ${message.messageId}');
      _handleNotificationNavigation(message.data);
    });
  }

  /// Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    if (_localNotifications == null) return;

    final notification = message.notification;
    if (notification == null) return;

    final notificationType = message.data['type'] as String?;
    final callId = message.data['callId'] as String?;

    // Check if this is an incoming call notification
    if (notificationType == 'incoming_call' && callId != null) {
      await _showIncomingCallNotification(message, callId);
    } else {
      await _showRegularNotification(message);
    }
  }

  /// Show incoming call notification with ringtone (no action buttons)
  Future<void> _showIncomingCallNotification(
      RemoteMessage message, String callId) async {
    final notification = message.notification;
    if (notification == null) return;

    final androidDetails = AndroidNotificationDetails(
      'acent_calls',
      'Acent Calls',
      channelDescription: 'Notification channel for incoming calls',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      vibrationPattern:
          Int64List.fromList([0, 1000, 500, 1000, 500, 1000]), // Ring pattern
      enableLights: true,
      timeoutAfter: 30000, // Auto-dismiss after 30 seconds
      // Remove action buttons to avoid confusion
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default', // Use default iOS ringtone
      interruptionLevel: InterruptionLevel.critical,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications!.show(
      callId.hashCode,
      notification.title,
      notification.body,
      notificationDetails,
      payload: jsonEncode({
        ...message.data,
        'notification_type': 'incoming_call',
        'call_id': callId,
      }),
    );
  }

  /// Show regular notification
  Future<void> _showRegularNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'acent_messages',
      'Acent Messages',
      channelDescription: 'Notification channel for Acent Messenger',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications!.show(
      message.hashCode,
      notification.title,
      notification.body,
      notificationDetails,
      payload: jsonEncode(message.data),
    );
  }

  /// Get FCM token (public method)
  Future<String?> getToken() async {
    return await _getAndStoreToken();
  }

  /// Get and store FCM token
  Future<String?> _getAndStoreToken() async {
    try {
      if (_messaging == null) {
        debugPrint('FCMService: Messaging instance is null, cannot get token');
        return null;
      }

      final token = await _messaging!.getToken();
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        await _storage.write(key: 'fcm_token', value: token);
        debugPrint('FCMService: Token obtained: ${token.substring(0, 20)}...');
        return token;
      } else {
        debugPrint('FCMService: Token is null or empty');
      }
    } catch (e) {
      debugPrint('FCMService: Error getting token: $e');
    }
    return null;
  }

  /// Register FCM token with server
  Future<bool> registerToken() async {
    try {
      if (_currentToken == null) {
        await _getAndStoreToken();
      }

      if (_currentToken == null) {
        debugPrint('FCMService: No token available for registration');
        return false;
      }

      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('FCMService: No auth token available');
        return false;
      }

      final platform = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
              ? 'ios'
              : 'web';

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/notification/register-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'token': _currentToken,
          'platform': platform,
          'deviceId': _deviceId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('FCMService: Token registered successfully');
        await _storage.write(key: 'fcm_token_registered', value: 'true');
        return true;
      } else {
        final data = jsonDecode(response.body);
        debugPrint('FCMService: Token registration failed: ${data['message']}');
        return false;
      }
    } catch (e) {
      debugPrint('FCMService: Error registering token: $e');
      return false;
    }
  }

  /// Update token on server (called on token refresh)
  Future<void> _updateTokenOnServer(String newToken) async {
    _currentToken = newToken;
    await _storage.write(key: 'fcm_token', value: newToken);
    await registerToken();
  }

  /// Remove FCM token from server
  Future<bool> removeToken() async {
    try {
      if (_currentToken == null) {
        _currentToken = await _storage.read(key: 'fcm_token');
      }

      if (_currentToken == null) {
        debugPrint('FCMService: No token to remove');
        return true;
      }

      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('FCMService: No auth token available');
        return false;
      }

      final response = await http.delete(
        Uri.parse('${Config.baseApiUrl}/user/notification/remove-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'token': _currentToken,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('FCMService: Token removed successfully');
        await _storage.delete(key: 'fcm_token');
        await _storage.delete(key: 'fcm_token_registered');
        _currentToken = null;
        return true;
      } else {
        final data = jsonDecode(response.body);
        debugPrint('FCMService: Token removal failed: ${data['message']}');
        return false;
      }
    } catch (e) {
      debugPrint('FCMService: Error removing token: $e');
      return false;
    }
  }

  /// Get notification settings from server
  Future<Map<String, dynamic>?> getNotificationSettings() async {
    try {
      final token = await _authService.getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/notification/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'];
      }
    } catch (e) {
      debugPrint('FCMService: Error getting notification settings: $e');
    }
    return null;
  }

  /// Update notification settings on server
  Future<bool> updateNotificationSettings(Map<String, bool> settings) async {
    try {
      final token = await _authService.getToken();
      if (token == null) return false;

      final response = await http.put(
        Uri.parse('${Config.baseApiUrl}/user/notification/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(settings),
      );

      if (response.statusCode == 200) {
        debugPrint('FCMService: Notification settings updated');
        return true;
      } else {
        final data = jsonDecode(response.body);
        debugPrint('FCMService: Settings update failed: ${data['message']}');
        return false;
      }
    } catch (e) {
      debugPrint('FCMService: Error updating settings: $e');
      return false;
    }
  }

  /// Send test notification
  Future<bool> sendTestNotification() async {
    try {
      final token = await _authService.getToken();
      if (token == null) return false;

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/notification/test'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': 'Test Notification',
          'body': 'This is a test notification from Acent Messenger',
          'data': {'type': 'test'},
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('FCMService: Error sending test notification: $e');
      return false;
    }
  }

  /// Check if token needs registration
  Future<bool> needsTokenRegistration() async {
    final registered = await _storage.read(key: 'fcm_token_registered');
    final currentToken = await _storage.read(key: 'fcm_token');

    return registered != 'true' ||
        currentToken != _currentToken ||
        _currentToken == null;
  }

  /// Dispose resources
  void dispose() {
    _messageStreamController.close();
    _tokenRefreshStreamController.close();
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCMService: Background message received: ${message.messageId}');
}
