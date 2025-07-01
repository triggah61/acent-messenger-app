import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import '../services/auth_service.dart';
import '../services/sound_notification_service.dart';
import '../constants/config.dart';
import 'package:http/http.dart' as http;

/// Pusher Service - Replaces Socket.IO implementation
/// Handles realtime messaging via Pusher channels
class PusherService {
  static PusherService? _instance;
  PusherChannelsFlutter? _pusher;
  final AuthService _authService = AuthService();
  final SoundNotificationService _soundService = SoundNotificationService();

  // Event callbacks
  final Map<String, List<Function(dynamic)>> _eventListeners = {};
  final Map<String, List<Function(dynamic)>> _chatEventListeners = {};

  // Connection state
  bool _isConnected = false;
  String? _currentUserId;
  bool _isInitialized = false;

  // Subscribed channels
  final Map<String, PusherChannel> _subscribedChannels = {};
  final Set<String> _activeChatSessions = <String>{};

  // Connection health monitoring
  Timer? _connectionHealthTimer;
  static const Duration _healthCheckInterval = Duration(minutes: 1);

  // Singleton pattern
  static PusherService get instance {
    _instance ??= PusherService();
    return _instance!;
  }

  bool get isConnected => _isConnected;
  String? get currentUserId => _currentUserId;
  bool get isInitialized => _isInitialized;
  Set<String> get activeChatSessions => Set.from(_activeChatSessions);

  /// Initialize Pusher service
  Future<bool> initializeGlobalSocket(String userId) async {
    try {
      debugPrint('PusherService: Initializing for user $userId');

      if (_isInitialized && _currentUserId == userId && _isConnected) {
        debugPrint(
            'PusherService: Already initialized and connected for user $userId');
        await _ensureUserChannel();
        await _rejoinActiveChatSessions();
        return true;
      }

      // Clean up any existing connection
      if (_pusher != null) {
        await _cleanDisconnect();
      }

      await _connect(userId);
      return true;
    } catch (e) {
      debugPrint('PusherService: Failed to initialize - $e');
      return false;
    }
  }

  /// Internal connection method
  Future<void> _connect(String userId) async {
    try {
      debugPrint('PusherService: Creating Pusher instance');

      _pusher = PusherChannelsFlutter.getInstance();
      _currentUserId = userId;

      await _pusher!.init(
        apiKey: Config.pusherKey,
        cluster: Config.pusherCluster,
        useTLS: Config.pusherUseTLS,
        onConnectionStateChange: _onConnectionStateChange,
        onError: _onError,
        onSubscriptionSucceeded: _onSubscriptionSucceeded,
        onEvent: _onEvent,
        onSubscriptionError: _onSubscriptionError,
        onDecryptionFailure: _onDecryptionFailure,
        onMemberAdded: _onMemberAdded,
        onMemberRemoved: _onMemberRemoved,
        onAuthorizer: _onAuthorizer,
      );

      await _pusher!.connect();
      debugPrint('PusherService: Pusher connection initiated');
    } catch (e) {
      debugPrint('PusherService: Error connecting - $e');
      throw e;
    }
  }

  /// Custom authorizer for private channels
  Future<Map<String, String>?> _onAuthorizer(
      String channelName, String socketId, dynamic options) async {
    try {
      debugPrint('PusherService: Authorizing channel: $channelName');

      final token = await _authService.getToken();
      if (token == null) {
        debugPrint(
            'PusherService: No auth token available for channel $channelName');
        return null;
      }

      debugPrint(
          'PusherService: Sending auth request for channel $channelName with socket $socketId');

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/pusher/auth'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'socket_id': socketId,
          'channel_name': channelName,
        }),
      );

      debugPrint('PusherService: Auth response status: ${response.statusCode}');
      debugPrint('PusherService: Auth response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
            'PusherService: Successfully authenticated for channel $channelName');

        // Return auth data directly as received from backend
        final Map<String, String> authResult = {
          'auth': data['auth'],
        };

        // Add channel_data for presence channels only
        if (channelName.startsWith('presence-') &&
            data['channel_data'] != null) {
          authResult['channel_data'] = data['channel_data'];
          debugPrint(
              'PusherService: Presence auth - Auth: ${data['auth']}, Channel Data: ${data['channel_data']}');
        }

        return authResult;
      } else {
        debugPrint(
            'PusherService: Auth failed for channel $channelName: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('PusherService: Auth error for channel $channelName: $e');
      return null;
    }
  }

  /// Connection state change handler
  void _onConnectionStateChange(String currentState, String previousState) {
    debugPrint(
        'PusherService: Connection state changed from $previousState to $currentState');

    final wasConnected = _isConnected;
    // Handle both lowercase and uppercase states
    _isConnected = currentState.toLowerCase() == 'connected';

    if (_isConnected && !wasConnected) {
      debugPrint('PusherService: Connected successfully');
      _isInitialized = true;
      _setupUserChannel();
      _startConnectionHealthCheck();
      _notifyListeners('connection_status', {'connected': true});
    } else if (!_isConnected && wasConnected) {
      debugPrint('PusherService: Disconnected');
      _notifyListeners('connection_status', {'connected': false});
    }

    // Add detailed logging for debugging
    debugPrint(
        'PusherService: _isConnected = $_isConnected, _isInitialized = $_isInitialized');
  }

  /// Error handler
  void _onError(String message, int? code, dynamic e) {
    debugPrint('PusherService: Error - $message (code: $code)');
    // If it's an authentication error, the connection might drop
    if (message.toLowerCase().contains('auth')) {
      debugPrint(
          'PusherService: Authentication error detected, connection may be unstable');
    }
    _notifyListeners('connection_error', {'error': message, 'code': code});
  }

  /// Subscription succeeded handler
  void _onSubscriptionSucceeded(String channelName, dynamic data) {
    debugPrint('PusherService: Successfully subscribed to $channelName');

    // If this is the user's personal channel, trigger any pending setup
    if (channelName == 'private-user_$_currentUserId') {
      _rejoinActiveChatSessions();
    }
  }

  /// Subscription error handler
  void _onSubscriptionError(String message, dynamic e) {
    debugPrint('PusherService: Subscription error - $message');
  }

  /// Decryption failure handler
  void _onDecryptionFailure(String event, String reason) {
    debugPrint('PusherService: Decryption failure for event $event - $reason');
  }

  /// Member added handler
  void _onMemberAdded(String channelName, PusherMember member) {
    debugPrint(
        'PusherService: Member added to $channelName - ${member.userId}');
  }

  /// Member removed handler
  void _onMemberRemoved(String channelName, PusherMember member) {
    debugPrint(
        'PusherService: Member removed from $channelName - ${member.userId}');
  }

  /// Event handler - routes events to appropriate listeners
  void _onEvent(PusherEvent event) {
    debugPrint(
        'PusherService: Received event ${event.eventName} on channel ${event.channelName}');

    try {
      dynamic data;

      // Handle different types of event data
      if (event.data != null && event.data!.isNotEmpty) {
        try {
          data = jsonDecode(event.data!);
        } catch (e) {
          // If JSON decode fails, use the raw data
          debugPrint(
              'PusherService: Could not decode event data as JSON, using raw data: ${event.data}');
          data = event.data;
        }
      } else {
        data = {};
      }

      // Skip internal Pusher events (like pusher:subscription_succeeded)
      if (event.eventName.startsWith('pusher:')) {
        debugPrint(
            'PusherService: Skipping internal Pusher event: ${event.eventName}');
        return;
      }

      // Handle global events (from user channel)
      if (event.channelName == 'private-user_$_currentUserId') {
        _handleGlobalEvent(event.eventName, data);
      }
      // Handle chat-specific events
      else if (event.channelName.startsWith('private-chat_')) {
        _handleChatEvent(event.eventName, data);
      }
      // Handle presence events
      else if (event.channelName.startsWith('presence-')) {
        _handlePresenceEvent(event.eventName, data);
      }
      // Handle any other channel events
      else {
        _notifyListeners(event.eventName, data);
      }
    } catch (e) {
      debugPrint(
          'PusherService: Error processing event ${event.eventName} - $e');
    }
  }

  /// Handle global events from user channel
  void _handleGlobalEvent(String eventName, dynamic data) {
    debugPrint('PusherService: Handling global event $eventName');
    _notifyListeners(eventName, data);
  }

  /// Handle chat-specific events
  void _handleChatEvent(String eventName, dynamic data) {
    debugPrint('PusherService: Handling chat event $eventName');
    _notifyChatListeners(eventName, data);
  }

  /// Handle presence events
  void _handlePresenceEvent(String eventName, dynamic data) {
    debugPrint(
        'PusherService: Handling presence event $eventName with data: $data');

    // Log specific presence events for debugging
    switch (eventName) {
      case 'user_online':
        debugPrint('PusherService: User came online: ${data['userId']}');
        break;
      case 'user_offline':
        debugPrint('PusherService: User went offline: ${data['userId']}');
        break;
      case 'user_status_update':
        debugPrint(
            'PusherService: User status update: ${data['userId']} -> ${data['status']}');
        break;
      default:
        debugPrint('PusherService: Unknown presence event: $eventName');
    }

    _notifyListeners(eventName, data);
  }

  /// Setup user channel for global events
  Future<void> _setupUserChannel() async {
    if (_currentUserId == null) return;

    try {
      // Wait a moment to ensure connection is fully established
      await Future.delayed(const Duration(milliseconds: 100));

      final channelName = 'private-user_$_currentUserId';
      debugPrint('PusherService: Setting up user channel $channelName');

      try {
        final channel = await _pusher!.subscribe(channelName: channelName);
        _subscribedChannels[channelName] = channel;
        debugPrint(
            'PusherService: Successfully subscribed to user channel $channelName');
      } catch (e) {
        debugPrint(
            'PusherService: Failed to subscribe to private user channel: $e');
        // For now, continue without user channel rather than failing completely
      }

      // Also subscribe to presence channel for user status
      try {
        final presenceChannelName = 'presence-user-status';
        final presenceChannel =
            await _pusher!.subscribe(channelName: presenceChannelName);
        _subscribedChannels[presenceChannelName] = presenceChannel;
        debugPrint(
            'PusherService: Successfully subscribed to presence channel $presenceChannelName');
      } catch (e) {
        debugPrint(
            'PusherService: Failed to subscribe to presence channel: $e');
        // Continue without presence channel
      }

      debugPrint('PusherService: User channel setup completed');
    } catch (e) {
      debugPrint('PusherService: Error setting up user channel - $e');
    }
  }

  /// Ensure user channel is subscribed
  Future<void> _ensureUserChannel() async {
    if (_currentUserId == null) return;

    final channelName = 'private-user_$_currentUserId';
    if (!_subscribedChannels.containsKey(channelName)) {
      await _setupUserChannel();
    }
  }

  /// Rejoin active chat sessions after reconnection
  Future<void> _rejoinActiveChatSessions() async {
    if (_activeChatSessions.isNotEmpty && _isConnected) {
      debugPrint(
          'PusherService: Rejoining ${_activeChatSessions.length} active chat sessions');

      for (final sessionId in _activeChatSessions.toList()) {
        try {
          await _subscribeToChatChannel(sessionId);
        } catch (e) {
          debugPrint(
              'PusherService: Error rejoining chat session $sessionId - $e');
        }
      }
    }
  }

  /// Subscribe to a chat channel
  Future<void> _subscribeToChatChannel(String chatSessionId) async {
    debugPrint('PusherService: Subscribing to chat channel $chatSessionId');
    debugPrint(
        'PusherService: Connection status - _isConnected: $_isConnected, _pusher: ${_pusher != null}');

    // Wait a bit for connection to stabilize if needed
    if (_pusher != null && !_isConnected) {
      debugPrint(
          'PusherService: Pusher exists but not connected, waiting for connection...');
      int retries = 0;
      while (!_isConnected && retries < 10) {
        await Future.delayed(const Duration(milliseconds: 200));
        retries++;
        debugPrint(
            'PusherService: Waiting for connection... attempt $retries, connected: $_isConnected');
      }
    }

    if (!_isConnected || _pusher == null) {
      debugPrint(
          'PusherService: Cannot subscribe to chat - not connected (isConnected: $_isConnected, pusher: ${_pusher != null})');
      return;
    }

    try {
      final channelName = 'private-chat_$chatSessionId';

      if (_subscribedChannels.containsKey(channelName)) {
        debugPrint('PusherService: Already subscribed to $channelName');
        return;
      }

      debugPrint('PusherService: Subscribing to chat channel $channelName');

      try {
        final channel = await _pusher!.subscribe(channelName: channelName);
        _subscribedChannels[channelName] = channel;
        debugPrint(
            'PusherService: Successfully subscribed to chat channel $channelName');
      } catch (e) {
        debugPrint(
            'PusherService: Failed to subscribe to private chat channel: $e');
        // Could add fallback to public channel here if needed for testing
      }
    } catch (e) {
      debugPrint('PusherService: Error subscribing to chat channel - $e');
    }
  }

  /// Unsubscribe from a chat channel
  Future<void> _unsubscribeFromChatChannel(String chatSessionId) async {
    try {
      final channelName = 'private-chat_$chatSessionId';

      if (_subscribedChannels.containsKey(channelName)) {
        await _pusher!.unsubscribe(channelName: channelName);
        _subscribedChannels.remove(channelName);
        debugPrint('PusherService: Unsubscribed from $channelName');
      }
    } catch (e) {
      debugPrint('PusherService: Error unsubscribing from chat channel - $e');
    }
  }

  // === CHAT-SPECIFIC METHODS (API compatibility with GlobalSocketService) ===

  /// Join a chat session
  void joinChatSession(String chatSessionId) {
    print('Chat: Joining chat session: $chatSessionId');
    if (chatSessionId.isEmpty) {
      debugPrint('PusherService: Cannot join chat - invalid session ID');
      return;
    }

    debugPrint('PusherService: Joining chat session: $chatSessionId');
    debugPrint(
        'PusherService: Current connection state - _isConnected: $_isConnected');
    _activeChatSessions.add(chatSessionId);

    // Always attempt to subscribe, let _subscribeToChatChannel handle connection waiting
    _subscribeToChatChannel(chatSessionId);
  }

  /// Leave a chat session
  void leaveChatSession(String chatSessionId) {
    if (chatSessionId.isEmpty) {
      debugPrint('PusherService: Cannot leave chat - invalid session ID');
      return;
    }

    debugPrint('PusherService: Leaving chat session: $chatSessionId');
    _activeChatSessions.remove(chatSessionId);
    _unsubscribeFromChatChannel(chatSessionId);
  }

  /// Emit typing event for chat (Send via HTTP endpoint)
  Future<void> emitChatTyping(String chatSessionId, bool isTyping) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('PusherService: No auth token for typing event');
        return;
      }

      final eventName = isTyping ? 'typing' : 'stop_typing';

      await http.post(
        Uri.parse('${Config.baseApiUrl}/pusher/events'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event': eventName,
          'data': {'chatSessionId': chatSessionId},
        }),
      );

      debugPrint(
          'PusherService: Sent $eventName event for chat $chatSessionId');
    } catch (e) {
      debugPrint('PusherService: Error sending typing event - $e');
    }
  }

  /// Mark message as read
  Future<void> markMessageAsRead(String messageId, String chatSessionId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('PusherService: No auth token for mark read event');
        return;
      }

      await http.post(
        Uri.parse('${Config.baseApiUrl}/pusher/events'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event': 'mark_message_read',
          'data': {
            'messageId': messageId,
            'chatSessionId': chatSessionId,
          },
        }),
      );

      debugPrint('PusherService: Marked message $messageId as read');
    } catch (e) {
      debugPrint('PusherService: Error marking message as read - $e');
    }
  }

  /// Send message reaction
  Future<void> sendMessageReaction(String messageId, String chatSessionId,
      String reaction, String action) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('PusherService: No auth token for reaction event');
        return;
      }

      await http.post(
        Uri.parse('${Config.baseApiUrl}/pusher/events'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event': 'message_reaction',
          'data': {
            'messageId': messageId,
            'chatSessionId': chatSessionId,
            'reaction': reaction,
            'action': action,
          },
        }),
      );

      debugPrint(
          'PusherService: Sent reaction $reaction for message $messageId');
    } catch (e) {
      debugPrint('PusherService: Error sending reaction - $e');
    }
  }

  /// Add chat event listener
  void addChatEventListener(String event, Function(dynamic) callback) {
    if (!_chatEventListeners.containsKey(event)) {
      _chatEventListeners[event] = [];
    }
    _chatEventListeners[event]!.add(callback);
    debugPrint('PusherService: Added chat listener for event $event');
  }

  /// Remove chat event listener
  void removeChatEventListener(String event, Function(dynamic) callback) {
    if (_chatEventListeners.containsKey(event)) {
      _chatEventListeners[event]!.remove(callback);
      if (_chatEventListeners[event]!.isEmpty) {
        _chatEventListeners.remove(event);
      }
      debugPrint('PusherService: Removed chat listener for event $event');
    }
  }

  /// Notify chat listeners
  void _notifyChatListeners(String event, dynamic data) {
    if (_chatEventListeners.containsKey(event)) {
      for (var listener in _chatEventListeners[event]!) {
        try {
          listener(data);
        } catch (e) {
          debugPrint(
              'PusherService: Error in chat listener for event $event - $e');
        }
      }
    }
  }

  // === GLOBAL EVENT METHODS ===

  /// Add event listener
  void addEventListener(String event, Function(dynamic) callback) {
    if (!_eventListeners.containsKey(event)) {
      _eventListeners[event] = [];
    }
    _eventListeners[event]!.add(callback);
    debugPrint('PusherService: Added listener for event $event');
  }

  /// Remove event listener
  void removeEventListener(String event, Function(dynamic) callback) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.remove(callback);
      if (_eventListeners[event]!.isEmpty) {
        _eventListeners.remove(event);
      }
      debugPrint('PusherService: Removed listener for event $event');
    }
  }

  /// Remove all listeners for an event
  void removeAllEventListeners(String event) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners.remove(event);
      debugPrint('PusherService: Removed all listeners for event $event');
    }
  }

  /// Notify all listeners for an event
  void _notifyListeners(String event, dynamic data) {
    if (_eventListeners.containsKey(event)) {
      for (var listener in _eventListeners[event]!) {
        try {
          listener(data);
        } catch (e) {
          debugPrint('PusherService: Error in listener for event $event - $e');
        }
      }
    }
  }

  // === COMPATIBILITY METHODS (for API compatibility with GlobalSocketService) ===

  /// Update user online status (Send via HTTP endpoint)
  Future<void> updateUserStatus(String status) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        debugPrint('PusherService: No auth token for status update');
        return;
      }

      await http.post(
        Uri.parse('${Config.baseApiUrl}/pusher/events'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event': 'update_user_status',
          'data': {'status': status},
        }),
      );

      debugPrint('PusherService: Updated user status to $status');
    } catch (e) {
      debugPrint('PusherService: Error updating user status - $e');
    }
  }

  /// Send global typing indicator
  Future<void> sendGlobalTyping(String chatSessionId, bool isTyping) async {
    // Use the same method as emitChatTyping
    await emitChatTyping(chatSessionId, isTyping);
  }

  /// Get connection info
  Map<String, dynamic> getConnectionInfo() {
    return {
      'isConnected': _isConnected,
      'currentUserId': _currentUserId,
      'isInitialized': _isInitialized,
      'subscribedChannels': _subscribedChannels.keys.toList(),
      'activeChatSessions': _activeChatSessions.toList(),
    };
  }

  /// Debug connection status - helpful for troubleshooting
  void debugConnectionStatus() {
    debugPrint('=== PusherService Debug Info ===');
    debugPrint('isConnected: $_isConnected');
    debugPrint('isInitialized: $_isInitialized');
    debugPrint('currentUserId: $_currentUserId');
    debugPrint('pusher instance: ${_pusher != null ? "exists" : "null"}');
    debugPrint('subscribedChannels: ${_subscribedChannels.keys.toList()}');
    debugPrint('activeChatSessions: $_activeChatSessions');
    debugPrint('eventListeners: ${_eventListeners.keys.toList()}');
    debugPrint('chatEventListeners: ${_chatEventListeners.keys.toList()}');
    debugPrint('===============================');
  }

  /// Start connection health monitoring
  void _startConnectionHealthCheck() {
    _connectionHealthTimer?.cancel();
    _connectionHealthTimer = Timer.periodic(_healthCheckInterval, (timer) {
      _performHealthCheck();
    });
  }

  /// Perform connection health check
  void _performHealthCheck() async {
    if (!_isConnected || _currentUserId == null) {
      return;
    }

    try {
      final token = await _authService.getToken();
      if (token == null) return;

      await http.post(
        Uri.parse('${Config.baseApiUrl}/pusher/ping'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      debugPrint('PusherService: Health check failed - $e');
    }
  }

  /// Clean disconnect
  Future<void> _cleanDisconnect() async {
    try {
      _connectionHealthTimer?.cancel();

      // Unsubscribe from all channels
      for (final channelName in _subscribedChannels.keys.toList()) {
        try {
          await _pusher!.unsubscribe(channelName: channelName);
        } catch (e) {
          debugPrint(
              'PusherService: Error unsubscribing from $channelName: $e');
        }
      }
      _subscribedChannels.clear();

      if (_pusher != null) {
        await _pusher!.disconnect();
        _pusher = null;
      }

      _isConnected = false;
      _isInitialized = false;
      _currentUserId = null;
      _activeChatSessions.clear();

      debugPrint('PusherService: Clean disconnect completed');
    } catch (e) {
      debugPrint('PusherService: Error during clean disconnect - $e');
    }
  }

  /// Disconnect global socket
  Future<void> disconnectGlobalSocket() async {
    debugPrint('PusherService: Disconnecting global socket');
    await _cleanDisconnect();
  }

  // === DEPRECATED SOCKET SERVICE COMPATIBILITY ===

  /// For backward compatibility with old SocketService interface

  /// Initialize socket (alias for initializeGlobalSocket)
  Future<void> initializeSocket() async {
    if (_currentUserId != null) {
      await initializeGlobalSocket(_currentUserId!);
    }
  }

  /// Disconnect (alias for disconnectGlobalSocket)
  Future<void> disconnect() async {
    await disconnectGlobalSocket();
  }
}
