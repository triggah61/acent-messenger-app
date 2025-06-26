import 'package:flutter/foundation.dart';
import 'package:acent_messenger/services/global_socket_service.dart';
import 'package:acent_messenger/services/sound_notification_service.dart';
import 'package:acent_messenger/models/message.dart';
import 'package:acent_messenger/models/chat_session.dart';
import 'dart:async';

class GlobalEventProvider with ChangeNotifier {
  final GlobalSocketService _globalSocketService = GlobalSocketService.instance;
  final SoundNotificationService _soundService =
      SoundNotificationService.instance;

  // Global event data
  List<Map<String, dynamic>> _notifications = [];
  Map<String, dynamic>? _latestMessage;
  Map<String, dynamic>? _incomingCall;
  bool _hasNewNotifications = false;
  int _unreadMessageCount = 0;
  Map<String, String> _userStatusMap = {}; // userId -> status

  // Connection status
  bool _isGlobalConnected = false;
  bool _isInitialized = false; // Track if global events are initialized
  String? _currentUserId; // Track current user ID

  // Current active session tracking
  String? _currentActiveSessionId;

  // Connection health check timer
  Timer? _connectionHealthTimer;

  // Callbacks for refreshing session lists
  Function()? _refreshChatSessionsCallback;
  Function()? _refreshGroupSessionsCallback;

  // Getters
  List<Map<String, dynamic>> get notifications => _notifications;
  Map<String, dynamic>? get latestMessage => _latestMessage;
  Map<String, dynamic>? get incomingCall => _incomingCall;
  bool get hasNewNotifications => _hasNewNotifications;
  int get unreadMessageCount => _unreadMessageCount;
  bool get isGlobalConnected => _isGlobalConnected;
  bool get isInitialized => _isInitialized;
  Map<String, String> get userStatusMap => _userStatusMap;
  String? get currentActiveSessionId => _currentActiveSessionId;

  // Initialize global event listeners
  Future<void> initializeGlobalEvents(String userId) async {
    try {
      debugPrint('GlobalEventProvider: Initializing for user $userId');

      // If already initialized for the same user, just reconnect if needed
      if (_isInitialized && _currentUserId == userId) {
        debugPrint(
            'GlobalEventProvider: Already initialized for user $userId, checking connection');
        if (!_isGlobalConnected) {
          debugPrint('GlobalEventProvider: Reconnecting global socket');
          await _globalSocketService.initializeGlobalSocket(userId);
        }
        return;
      }

      // If initialized for different user, disconnect first
      if (_isInitialized && _currentUserId != userId) {
        debugPrint(
            'GlobalEventProvider: Switching user from $_currentUserId to $userId');
        await disconnectGlobalEvents();
      }

      _currentUserId = userId;

      // Initialize sound service first
      await _soundService.initialize();

      // Initialize global socket
      await _globalSocketService.initializeGlobalSocket(userId);

      // Setup event listeners
      _setupEventListeners();

      _isInitialized = true;
      debugPrint(
          'GlobalEventProvider: Initialized successfully for user $userId');

      // Start connection health check
      _startConnectionHealthCheck();
    } catch (e) {
      debugPrint('GlobalEventProvider: Failed to initialize - $e');
      _isInitialized = false;
    }
  }

  // Handle app lifecycle changes (call this when app comes to foreground)
  Future<void> handleAppResume() async {
    debugPrint('GlobalEventProvider: handleAppResume called');
    debugPrint(
        'GlobalEventProvider: Current state - _currentUserId: $_currentUserId, _isInitialized: $_isInitialized');

    if (_currentUserId != null) {
      if (_isInitialized) {
        debugPrint(
            'GlobalEventProvider: App resumed, checking connection status');

        // Always force reconnection on app resume to ensure proper room membership
        debugPrint('GlobalEventProvider: Force reconnecting after app resume');
        try {
          await _globalSocketService.initializeGlobalSocket(_currentUserId!);
          debugPrint(
              'GlobalEventProvider: Reconnection successful after app resume');
        } catch (e) {
          debugPrint(
              'GlobalEventProvider: Reconnection failed after app resume: $e');
          // Try to reinitialize from scratch
          await initializeGlobalEvents(_currentUserId!);
        }
      } else {
        // If not initialized but we have a user ID, initialize from scratch
        debugPrint(
            'GlobalEventProvider: App resumed but not initialized, initializing from scratch');
        await initializeGlobalEvents(_currentUserId!);
      }
    } else {
      debugPrint(
          'GlobalEventProvider: App resumed but no current user ID available');
    }
  }

  // Handle app going to background
  Future<void> handleAppPause() async {
    debugPrint('GlobalEventProvider: handleAppPause called');

    // Don't disconnect on pause, just update status
    // The connection should remain active to receive notifications
    if (_currentUserId != null && _isInitialized) {
      debugPrint(
          'GlobalEventProvider: App paused, keeping connection but updating status');
      updateUserStatus('away');
    }
  }

  // Handle app being terminated/detached
  Future<void> handleAppDetached() async {
    debugPrint('GlobalEventProvider: handleAppDetached called');

    if (_currentUserId != null && _isInitialized) {
      debugPrint(
          'GlobalEventProvider: App detached, updating status to offline');
      updateUserStatus('offline');
      // Don't fully disconnect here as the app is closing anyway
    }
  }

  // Check if we need to reinitialize (for app restart scenarios)
  Future<void> ensureInitialized(String userId) async {
    debugPrint(
        'GlobalEventProvider: ensureInitialized called for user $userId');
    logCurrentStatus();

    // Always try to initialize/reconnect if:
    // 1. Not initialized
    // 2. Different user
    // 3. Not connected
    // 4. Connection seems stale (no recent activity)

    final shouldReinitialize = !_isInitialized ||
        _currentUserId != userId ||
        !_isGlobalConnected ||
        _connectionHealthTimer ==
            null; // Health timer not running indicates stale state

    if (shouldReinitialize) {
      debugPrint('GlobalEventProvider: Conditions met for initialization:');
      debugPrint('  - _isInitialized: $_isInitialized');
      debugPrint('  - _currentUserId == userId: ${_currentUserId == userId}');
      debugPrint('  - _isGlobalConnected: $_isGlobalConnected');
      debugPrint('  - health timer running: ${_connectionHealthTimer != null}');
      debugPrint(
          'GlobalEventProvider: Ensuring initialization for user $userId');
      await initializeGlobalEvents(userId);
    } else {
      debugPrint(
          'GlobalEventProvider: Already properly initialized for user $userId, checking connection health');
      // Even if initialized, perform a health check
      _checkConnectionHealth();
    }
  }

  void _setupEventListeners() {
    // Connection status
    _globalSocketService.addEventListener('connection_status', (data) {
      _isGlobalConnected = data['connected'] ?? false;
      debugPrint(
          'GlobalEventProvider: Connection status changed - $_isGlobalConnected');
      notifyListeners();
    });

    // Global new message
    _globalSocketService.addEventListener('global_new_message', (data) {
      _handleNewMessage(data);
    });

    // Global new conversation
    _globalSocketService.addEventListener('global_new_conversation', (data) {
      _handleNewConversation(data);
    });

    // Global new group
    _globalSocketService.addEventListener('global_new_group', (data) {
      _handleNewGroup(data);
    });

    // Global notification
    _globalSocketService.addEventListener('global_notification', (data) {
      _handleNotification(data);
    });

    // Incoming call
    _globalSocketService.addEventListener('global_incoming_call', (data) {
      _handleIncomingCall(data);
    });

    // User status changes
    _globalSocketService.addEventListener('global_user_status', (data) {
      _handleUserStatusChange(data);
    });

    // Message read status
    _globalSocketService.addEventListener('global_message_read', (data) {
      _handleMessageRead(data);
    });

    // Contact updates
    _globalSocketService.addEventListener('global_contact_update', (data) {
      _handleContactUpdate(data);
    });

    // Group member updates
    _globalSocketService.addEventListener('global_group_member_update', (data) {
      _handleGroupMemberUpdate(data);
    });

    // Profile updates
    _globalSocketService.addEventListener('global_profile_update', (data) {
      _handleProfileUpdate(data);
    });
  }

  // Handle new message
  void _handleNewMessage(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: New message received - $data');
    debugPrint(
        'GlobalEventProvider: Available keys in message data: ${data.keys.toList()}');

    _latestMessage = data;
    _unreadMessageCount++;

    // Since backend sends same structure as regular new_message, use 'chatSession' field
    final messageChatSessionId = data['chatSession'] as String?;

    debugPrint(
        'GlobalEventProvider: Extracted chatSessionId: $messageChatSessionId');
    debugPrint(
        'GlobalEventProvider: Current active session: $_currentActiveSessionId');

    final isFromActiveSession = messageChatSessionId != null &&
        messageChatSessionId == _currentActiveSessionId;

    debugPrint(
        'GlobalEventProvider: Message from session $messageChatSessionId, current active session: $_currentActiveSessionId');
    debugPrint(
        'GlobalEventProvider: Is from active session: $isFromActiveSession');

    // Only play sound if message is NOT from the currently active session
    if (!isFromActiveSession) {
      debugPrint(
          'GlobalEventProvider: Playing sound for message from inactive session');
      _soundService.playNewMessageSound();
    } else {
      debugPrint(
          'GlobalEventProvider: Skipping sound - message from active session');
    }

    // Always add to notifications
    _addNotification({
      'type': 'message',
      'title': 'New Message',
      'content': data['content'] ?? 'You have a new message',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Refresh session lists to update last message and unread counts
    _refreshSessionLists();

    notifyListeners();
  }

  // Refresh both chat and group session lists
  void _refreshSessionLists() {
    debugPrint('GlobalEventProvider: Refreshing session lists');

    // Use a small delay to allow UI to settle before triggering refresh
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_refreshChatSessionsCallback != null) {
        try {
          debugPrint(
              'GlobalEventProvider: Calling chat sessions refresh callback');
          _refreshChatSessionsCallback!();
          debugPrint(
              'GlobalEventProvider: Chat sessions refresh callback completed');
        } catch (e) {
          debugPrint(
              'GlobalEventProvider: Error calling chat sessions refresh callback: $e');
        }
      } else {
        debugPrint(
            'GlobalEventProvider: Chat sessions refresh callback is null');
      }

      if (_refreshGroupSessionsCallback != null) {
        try {
          debugPrint(
              'GlobalEventProvider: Calling group sessions refresh callback');
          _refreshGroupSessionsCallback!();
          debugPrint(
              'GlobalEventProvider: Group sessions refresh callback completed');
        } catch (e) {
          debugPrint(
              'GlobalEventProvider: Error calling group sessions refresh callback: $e');
        }
      } else {
        debugPrint(
            'GlobalEventProvider: Group sessions refresh callback is null');
      }
    });
  }

  // Handle new conversation
  void _handleNewConversation(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: New conversation created - $data');

    // Play notification sound
    _soundService.playNotificationSound();

    _addNotification({
      'type': 'conversation',
      'title': 'New Conversation',
      'content': 'A new conversation was created',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    notifyListeners();
  }

  // Handle new group
  void _handleNewGroup(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: New group created - $data');

    // Play notification sound
    _soundService.playNotificationSound();

    _addNotification({
      'type': 'group',
      'title': 'New Group',
      'content': 'You were added to a new group: ${data['title'] ?? 'Unknown'}',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    notifyListeners();
  }

  // Handle notification
  void _handleNotification(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: New notification - $data');

    // Play notification sound
    _soundService.playNotificationSound();

    _addNotification({
      'type': 'notification',
      'title': data['title'] ?? 'Notification',
      'content': data['content'] ?? 'You have a new notification',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    notifyListeners();
  }

  // Handle incoming call
  void _handleIncomingCall(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: Incoming call - $data');

    _incomingCall = data;

    // Play incoming call sound
    _soundService.playIncomingCallSound();

    _addNotification({
      'type': 'call',
      'title': 'Incoming Call',
      'content': 'Call from ${data['callerName'] ?? 'Unknown'}',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    notifyListeners();
  }

  // Handle user status change
  void _handleUserStatusChange(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: User status change - $data');

    final userId = data['userId'] as String?;
    final status = data['status'] as String?;

    if (userId != null && status != null) {
      _userStatusMap[userId] = status;
      notifyListeners();
    }
  }

  // Handle message read
  void _handleMessageRead(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: Message read - $data');

    if (_unreadMessageCount > 0) {
      _unreadMessageCount--;
      notifyListeners();
    }
  }

  // Handle contact update
  void _handleContactUpdate(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: Contact update - $data');

    _addNotification({
      'type': 'contact',
      'title': 'Contact Update',
      'content': data['message'] ?? 'Your contacts have been updated',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    notifyListeners();
  }

  // Handle group member update
  void _handleGroupMemberUpdate(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: Group member update - $data');

    _addNotification({
      'type': 'group_member',
      'title': 'Group Update',
      'content': data['message'] ?? 'Group membership has changed',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    notifyListeners();
  }

  // Handle profile update
  void _handleProfileUpdate(Map<String, dynamic> data) {
    debugPrint('GlobalEventProvider: Profile update - $data');

    // Profile updates might not need notifications, just notify listeners
    notifyListeners();
  }

  // Add notification
  void _addNotification(Map<String, dynamic> notification) {
    _notifications.insert(0, notification);
    _hasNewNotifications = true;

    // Keep only last 100 notifications
    if (_notifications.length > 100) {
      _notifications = _notifications.take(100).toList();
    }
  }

  // Mark notifications as read
  void markNotificationsAsRead() {
    _hasNewNotifications = false;
    notifyListeners();
  }

  // Clear all notifications
  void clearNotifications() {
    _notifications.clear();
    _hasNewNotifications = false;
    notifyListeners();
  }

  // Dismiss incoming call
  void dismissIncomingCall() {
    _incomingCall = null;
    notifyListeners();
  }

  // Reset unread message count
  void resetUnreadMessageCount() {
    _unreadMessageCount = 0;
    notifyListeners();
  }

  // Get user status
  String getUserStatus(String userId) {
    return _userStatusMap[userId] ?? 'offline';
  }

  // Send global events
  void updateUserStatus(String status) {
    _globalSocketService.updateUserStatus(status);
  }

  void markMessageAsRead(String messageId, String chatSessionId) {
    _globalSocketService.markMessageAsRead(messageId, chatSessionId);
  }

  void sendGlobalTyping(String chatSessionId, bool isTyping) {
    _globalSocketService.sendGlobalTyping(chatSessionId, isTyping);
  }

  // Disconnect global events
  Future<void> disconnectGlobalEvents() async {
    debugPrint('GlobalEventProvider: Disconnecting global events');

    // Stop connection health check
    _stopConnectionHealthCheck();

    await _globalSocketService.disconnectGlobalSocket();

    // Dispose sound service
    await _soundService.dispose();

    // Clear all data and reset state
    _notifications.clear();
    _latestMessage = null;
    _incomingCall = null;
    _hasNewNotifications = false;
    _unreadMessageCount = 0;
    _userStatusMap.clear();
    _isGlobalConnected = false;
    _isInitialized = false; // Reset initialization state
    _currentUserId = null; // Reset current user ID
    _currentActiveSessionId = null; // Clear active session
    _refreshChatSessionsCallback = null; // Clear callbacks
    _refreshGroupSessionsCallback = null;

    notifyListeners();
  }

  // Get connection info
  Map<String, dynamic> getConnectionInfo() {
    final socketInfo = _globalSocketService.getConnectionInfo();
    return {
      'provider_initialized': _isInitialized,
      'provider_connected': _isGlobalConnected,
      'current_user_id': _currentUserId,
      'socket_info': socketInfo,
    };
  }

  // Debug method to log current status
  void logCurrentStatus() {
    final info = getConnectionInfo();
    debugPrint('GlobalEventProvider Status: $info');
  }

  // Start periodic connection health check
  void _startConnectionHealthCheck() {
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer =
        Timer.periodic(const Duration(minutes: 2), (timer) {
      _checkConnectionHealth();
    });
    debugPrint('GlobalEventProvider: Started connection health check');
  }

  // Check connection health and reconnect if needed
  Future<void> _checkConnectionHealth() async {
    if (_currentUserId == null || !_isInitialized) {
      debugPrint(
          'GlobalEventProvider: Skipping health check - not initialized or no user');
      return;
    }

    debugPrint('GlobalEventProvider: Checking connection health');
    final socketInfo = _globalSocketService.getConnectionInfo();

    debugPrint('GlobalEventProvider: Socket info - ${socketInfo.toString()}');

    final isHealthy = socketInfo['isConnected'] == true &&
        socketInfo['socketConnected'] == true &&
        _isGlobalConnected;

    if (!isHealthy) {
      debugPrint(
          'GlobalEventProvider: Connection unhealthy, attempting reconnection');
      debugPrint('  - Socket connected: ${socketInfo['isConnected']}');
      debugPrint('  - Socket.io connected: ${socketInfo['socketConnected']}');
      debugPrint('  - Provider connected: $_isGlobalConnected');

      try {
        await _globalSocketService.initializeGlobalSocket(_currentUserId!);
        debugPrint('GlobalEventProvider: Health check reconnection successful');
      } catch (e) {
        debugPrint('GlobalEventProvider: Health check reconnection failed: $e');
      }
    } else {
      debugPrint('GlobalEventProvider: Connection health check passed');
    }
  }

  // Stop connection health check
  void _stopConnectionHealthCheck() {
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer = null;
    debugPrint('GlobalEventProvider: Stopped connection health check');
  }

  // Set callbacks for refreshing session lists
  void setRefreshSessionsCallbacks({
    Function()? refreshChatSessions,
    Function()? refreshGroupSessions,
  }) {
    _refreshChatSessionsCallback = refreshChatSessions;
    _refreshGroupSessionsCallback = refreshGroupSessions;
    debugPrint('GlobalEventProvider: Session refresh callbacks set');
  }

  // Set current active session (call when entering a chat screen)
  void setCurrentActiveSession(String sessionId) {
    _currentActiveSessionId = sessionId;
    debugPrint('GlobalEventProvider: Set current active session to $sessionId');
  }

  // Clear current active session (call when leaving a chat screen)
  void clearCurrentActiveSession() {
    debugPrint(
        'GlobalEventProvider: Clearing current active session (was: $_currentActiveSessionId)');
    _currentActiveSessionId = null;
  }

  // Manual test method for debugging (remove in production)
  void testSessionRefresh() {
    debugPrint('GlobalEventProvider: Manual test - triggering session refresh');
    _refreshSessionLists();
  }
}
