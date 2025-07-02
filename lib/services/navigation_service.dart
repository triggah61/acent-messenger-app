import 'package:flutter/material.dart';
import '../views/consversations/chatdetailsscreen.dart';
import '../models/chat_session.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
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

      final context = this.context;
      if (context == null) {
        debugPrint('NavigationService: No navigation context available');
        return;
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // Fetch the chat session details
        final authService = AuthService();
        final chatService = ChatService(authService);
        final session = await chatService.getChatSession(cleanSessionId);

        // Hide loading indicator
        Navigator.of(context).pop();

        if (session != null) {
          // Navigate to the chat details screen
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => Conversations(
                session: session,
              ),
            ),
          );

          debugPrint(
              'NavigationService: Successfully navigated to chat session');
        } else {
          debugPrint(
              'NavigationService: Chat session not found: $cleanSessionId');
          _showErrorMessage(context, 'Chat session not found');
        }
      } catch (e) {
        // Hide loading indicator if still showing
        Navigator.of(context).pop();
        debugPrint('NavigationService: Error loading chat session: $e');
        _showErrorMessage(context, 'Error opening chat: ${e.toString()}');
      }
    } catch (e) {
      debugPrint('NavigationService: Navigation error: $e');
    }
  }

  /// Navigate to group chat
  Future<void> navigateToGroupChat({
    required String groupId,
    String? messageId,
    Map<String, dynamic>? additionalData,
  }) async {
    // Group chats also use the same chat session structure
    await navigateToChat(
      chatSessionId: groupId,
      messageId: messageId,
      additionalData: additionalData,
    );
  }

  /// Navigate to call screen
  Future<void> navigateToCall({
    required String callId,
    required String callType, // 'voice' or 'video'
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      debugPrint(
          'NavigationService: Navigating to call: $callId, type: $callType');

      final context = this.context;
      if (context == null) {
        debugPrint('NavigationService: No navigation context available');
        return;
      }

      // TODO: Implement call screen navigation when call screens are available
      // For now, show a placeholder
      _showInfoMessage(context, 'Call feature coming soon!');
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

      // Clean the session IDs from notification data
      final chatSessionId = _cleanId(data['chatSessionId'] ?? '');
      final groupId = _cleanId(data['groupId'] ?? '');
      final messageId = _cleanId(data['messageId'] ?? '');

      switch (type) {
        case 'new_message':
          await navigateToChat(
            chatSessionId: chatSessionId,
            messageId: messageId.isNotEmpty ? messageId : null,
            additionalData: data,
          );
          break;

        case 'group_message':
          await navigateToGroupChat(
            groupId: chatSessionId.isNotEmpty ? chatSessionId : groupId,
            messageId: messageId.isNotEmpty ? messageId : null,
            additionalData: data,
          );
          break;

        case 'incoming_call':
          await navigateToCall(
            callId: _cleanId(data['callId'] ?? ''),
            callType: data['callType'] ?? 'voice',
            additionalData: data,
          );
          break;

        default:
          debugPrint('NavigationService: Unknown notification type: $type');
          final context = this.context;
          if (context != null) {
            _showInfoMessage(context,
                'Notification received: ${data['title'] ?? 'Unknown'}');
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
  String _cleanId(String id) {
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
