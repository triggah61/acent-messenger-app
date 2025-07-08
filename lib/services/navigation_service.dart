import 'package:flutter/material.dart';
import '../views/consversations/chatdetailsscreen.dart';
import '../views/calls/incoming_call_screen.dart';
import '../models/chat_session.dart';
import '../models/call.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../constants/config.dart';

/// Navigation service for handling navigation from anywhere in the app
/// Especially useful for FCM notification clicks
class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  static NavigationService get instance => _instance;

  /// Global navigator key to access navigation context from anywhere
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Get the current navigation context
  BuildContext? get context => navigatorKey.currentContext;

  /// Navigate to a specific chat session
  Future<void> navigateToChat({
    required String chatSessionId,
    String? messageId,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      // Clean the session ID by removing any surrounding quotes
      final cleanSessionId = _cleanId(chatSessionId);
      debugPrint('NavigationService: Original session ID: $chatSessionId');
      debugPrint('NavigationService: Cleaned session ID: $cleanSessionId');
      debugPrint('NavigationService: Additional data: $additionalData');

      if (cleanSessionId.isEmpty) {
        debugPrint('NavigationService: Empty session ID provided');
        final context = this.context;
        if (context != null) {
          _showErrorMessage(context, 'Invalid chat session ID');
        }
        return;
      }

      final context = this.context;
      if (context == null) {
        debugPrint('NavigationService: No navigation context available');
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // Fetch the chat session details
        final authService = AuthService();
        final chatService = ChatService(authService);
        debugPrint(
            'NavigationService: Fetching chat session with ID: $cleanSessionId');

        final session = await chatService.getChatSession(cleanSessionId);

        // Hide loading indicator
        Navigator.of(context).pop();

        if (session != null) {
          debugPrint(
              'NavigationService: Found session: ${session.id}, type: ${session.type}, title: ${session.title}');

          // Navigate to the chat details screen
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => Conversations(session: session),
            ),
          );

          debugPrint(
            'NavigationService: Successfully navigated to chat session',
          );
        } else {
          debugPrint(
            'NavigationService: Chat session not found: $cleanSessionId',
          );
          _showErrorMessage(context, 'Chat session not found');
        }
      } catch (e) {
        // Hide loading indicator if still showing
        Navigator.of(context).pop();
        debugPrint('NavigationService: Error loading chat session: $e');
        debugPrint(
            'NavigationService: Session ID that failed: $cleanSessionId');
        _showErrorMessage(context, 'Error opening chat: ${e.toString()}');
      }
    } catch (e) {
      debugPrint('NavigationService: Navigation error: $e');
      debugPrint('NavigationService: Failed session ID: $chatSessionId');
    }
  }

  /// Navigate to call screen
  Future<void> navigateToCall({
    required String callId,
    required String callType, // 'voice' or 'video'
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      debugPrint(
        'NavigationService: Navigating to call: $callId, type: $callType',
      );

      final context = this.context;
      if (context == null) {
        debugPrint('NavigationService: No navigation context available');
        return;
      }

      // Import the required services and screens
      final callService = CallService(AuthService());

      // Show loading while fetching call details
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // Get the specific call by ID (much more efficient than searching history)
        final call = await callService.getCallById(callId);

        // Hide loading
        Navigator.of(context).pop();

        if (call != null) {
          debugPrint('NavigationService: Successfully found call: ${call.id}');
          // Navigate to incoming call screen
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => IncomingCallScreen(
                call: call,
                notificationData: additionalData,
              ),
            ),
          );
        } else {
          debugPrint('NavigationService: Call not found or expired: $callId');
          _showErrorMessage(context, 'Call not found or expired');
        }
      } catch (e) {
        // Hide loading if still showing
        Navigator.of(context).pop();
        debugPrint('NavigationService: Error loading call details: $e');
        _showErrorMessage(context, 'Error loading call: ${e.toString()}');
      }
    } catch (e) {
      debugPrint('NavigationService: Call navigation error: $e');
    }
  }

  /// Handle notification data and route to appropriate screen
  Future<void> handleNotificationData(Map<String, dynamic> data) async {
    try {
      final type = data['type'] as String?;
      debugPrint('NavigationService: Handling notification type: $type');
      debugPrint('NavigationService: Notification data: $data');

      // Try multiple field names for the session ID to handle different notification formats
      String sessionId = '';

      // Check all possible field names for session ID
      final possibleFields = [
        'chatSessionId',
        'chatSession',
        'groupId',
        'sessionId',
        '_id'
      ];
      for (final field in possibleFields) {
        final value = _cleanId(data[field]?.toString() ?? '');
        if (value.isNotEmpty) {
          sessionId = value;
          debugPrint(
              'NavigationService: Found session ID in field "$field": $sessionId');
          break;
        }
      }

      final messageId = _cleanId(data['messageId']?.toString() ?? '');

      debugPrint('NavigationService: Using session ID: $sessionId');
      debugPrint('NavigationService: Using message ID: $messageId');

      switch (type) {
        case 'new_message':
        case 'group_message':
          // Both personal and group messages use the same navigation logic
          if (sessionId.isNotEmpty) {
            await navigateToChat(
              chatSessionId: sessionId,
              messageId: messageId.isNotEmpty ? messageId : null,
              additionalData: data,
            );
          } else {
            debugPrint(
                'NavigationService: No valid session ID found in notification data');
            final context = this.context;
            if (context != null) {
              _showErrorMessage(context, 'Invalid message notification data');
            }
          }
          break;

        case 'incoming_call':
          await navigateToCall(
            callId: _cleanId(data['callId']?.toString() ?? ''),
            callType: data['callType'] ?? 'voice',
            additionalData: data,
          );
          break;

        default:
          debugPrint('NavigationService: Unknown notification type: $type');
          final context = this.context;
          if (context != null) {
            _showInfoMessage(
              context,
              'Notification received: ${data['title'] ?? 'Unknown'}',
            );
          }
      }
    } catch (e) {
      debugPrint('NavigationService: Error handling notification data: $e');
    }
  }

  /// Navigate to home screen (useful for resetting navigation state)
  Future<void> navigateToHome() async {
    try {
      final context = this.context;
      if (context == null) return;

      // Navigate to home and clear stack
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      debugPrint('NavigationService: Error navigating to home: $e');
    }
  }

  /// Check if user is authenticated before navigation
  bool _isUserAuthenticated() {
    // This should check if user is logged in
    // For now, return true - can be enhanced later
    return true;
  }

  /// Show error message to user
  void _showErrorMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show info message to user
  void _showInfoMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Clean ID by removing quotes and trimming whitespace
  /// Also handles different data types that might come from notification payload
  String _cleanId(String id) {
    if (id.isEmpty) return '';
    return id.replaceAll('"', '').replaceAll("'", "").trim();
  }

  /// Get chat session by ID (helper method)
  static Future<ChatSession?> getChatSessionById(String sessionId) async {
    try {
      final authService = AuthService();
      final chatService = ChatService(authService);
      // Clean the session ID before making the request
      final cleanSessionId =
          sessionId.replaceAll('"', '').replaceAll("'", "").trim();
      return await chatService.getChatSession(cleanSessionId);
    } catch (e) {
      debugPrint('NavigationService: Error getting chat session: $e');
      return null;
    }
  }
}
