import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/services/auth_service.dart';
import 'package:acent_messenger/services/sound_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';

class GlobalSocketService {
  static GlobalSocketService? _instance;
  IO.Socket? _globalSocket;
  final AuthService _authService = AuthService();
  final SoundNotificationService _soundService = SoundNotificationService();

  // Event callbacks
  final Map<String, List<Function(dynamic)>> _eventListeners = {};

  // Connection state
  bool _isConnected = false;
  String? _currentUserId;
  String? _currentUserRoom;

  // Connection health monitoring
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _reconnectDelay = Duration(seconds: 3);

  // Track last connection timestamp to detect stale connections
  DateTime? _lastConnectionTime;
  DateTime? _lastPongTime;

  // Connection state flags
  bool _isReconnecting = false;
  bool _isDisconnecting = false;

  // === CHAT-SPECIFIC METHODS (consolidated from SocketService) ===

  // Join a chat session
  void joinChatSession(String chatSessionId) {
    if (isConnected) {
      _globalSocket?.emit('join_chat', chatSessionId);
      debugPrint('GlobalSocket: Joined chat session: $chatSessionId');
    } else {
      debugPrint('GlobalSocket: Cannot join chat session - not connected');
    }
  }

  // Leave a chat session
  void leaveChatSession(String chatSessionId) {
    if (isConnected) {
      _globalSocket?.emit('leave_chat', chatSessionId);
      debugPrint('GlobalSocket: Left chat session: $chatSessionId');
    } else {
      debugPrint('GlobalSocket: Cannot leave chat session - not connected');
    }
  }

  // Emit typing event for chat
  void emitChatTyping(String chatSessionId, bool isTyping) {
    if (isConnected) {
      _globalSocket?.emit('typing', {
        'chatSessionId': chatSessionId,
        'isTyping': isTyping,
      });
      debugPrint(
          'GlobalSocket: Emitted chat typing: $chatSessionId, isTyping: $isTyping');
    } else {
      debugPrint('GlobalSocket: Cannot emit chat typing - not connected');
    }
  }

  // === CHAT EVENT LISTENERS ===

  // Track chat-specific listeners separately
  final Map<String, List<Function(dynamic)>> _chatEventListeners = {};

  // Add chat event listener
  void addChatEventListener(String event, Function(dynamic) callback) {
    if (!_chatEventListeners.containsKey(event)) {
      _chatEventListeners[event] = [];
    }
    _chatEventListeners[event]!.add(callback);
    debugPrint('GlobalSocket: Added chat listener for event $event');
  }

  // Remove chat event listener
  void removeChatEventListener(String event, Function(dynamic) callback) {
    if (_chatEventListeners.containsKey(event)) {
      _chatEventListeners[event]!.remove(callback);
      if (_chatEventListeners[event]!.isEmpty) {
        _chatEventListeners.remove(event);
      }
      debugPrint('GlobalSocket: Removed chat listener for event $event');
    }
  }

  // Notify chat listeners
  void _notifyChatListeners(String event, dynamic data) {
    if (_chatEventListeners.containsKey(event)) {
      for (var listener in _chatEventListeners[event]!) {
        try {
          listener(data);
        } catch (e) {
          debugPrint(
              'GlobalSocket: Error in chat listener for event $event - $e');
        }
      }
    }
  }

  // Singleton pattern
  static GlobalSocketService get instance {
    _instance ??= GlobalSocketService();
    return _instance!;
  }

  bool get isConnected => _isConnected && _globalSocket?.connected == true;
  String? get currentUserId => _currentUserId;
  bool get isReconnecting => _isReconnecting;

  // Initialize global socket connection for a specific user
  Future<void> initializeGlobalSocket(String userId) async {
    if (_isDisconnecting) {
      debugPrint('GlobalSocket: Currently disconnecting, waiting...');
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    debugPrint('GlobalSocket: Attempting to initialize for user $userId');
    debugPrint(
        'GlobalSocket: Current state - isConnected: $isConnected, currentUserId: $_currentUserId, hasSocket: ${_globalSocket != null}');

    // If we have the same user and socket is actually connected, check health
    if (_globalSocket != null && _currentUserId == userId && isConnected) {
      debugPrint(
          'GlobalSocket: Already connected for user $userId, checking socket health');

      // Test the connection by emitting a ping
      try {
        await _performHealthCheck();
        debugPrint(
            'GlobalSocket: Health check passed, ensuring user room membership');
        _ensureUserRoomMembership();
        return;
      } catch (e) {
        debugPrint('GlobalSocket: Health check failed, will reconnect - $e');
      }
    }

    // Always clean disconnect first to ensure clean state
    if (_globalSocket != null) {
      debugPrint(
          'GlobalSocket: Cleaning up existing socket before reconnecting');
      await _cleanDisconnect();
    }

    await _connect(userId);
  }

  // Internal connection method
  Future<void> _connect(String userId) async {
    try {
      _isReconnecting = true;

      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token available');

      debugPrint(
          'GlobalSocket: Creating new socket connection for user $userId');

      _globalSocket = IO.io(
        Config.baseApiUrl.replaceAll('/api', ''),
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setPath('/api/socket.io')
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .enableReconnection()
            .setReconnectionAttempts(3)
            .setReconnectionDelay(2000)
            .setTimeout(20000)
            .build(),
      );

      _globalSocket!.connect();
      _setupGlobalSocketListeners();
      _currentUserId = userId;
      _lastConnectionTime = DateTime.now();

      debugPrint('GlobalSocket: Connection initiated for user $userId');
    } catch (e) {
      debugPrint('GlobalSocket: Failed to initialize - $e');
      _isReconnecting = false;
      _scheduleReconnection(userId);
      throw e;
    }
  }

  // Perform health check by pinging the server
  Future<void> _performHealthCheck() async {
    final completer = Completer<void>();
    bool responded = false;

    // Set up one-time pong listener
    final unsubscribe = () {
      _globalSocket?.off('pong');
    };

    _globalSocket?.on('pong', (data) {
      responded = true;
      unsubscribe();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    // Send ping
    _globalSocket?.emit('ping', {'userId': _currentUserId});

    // Wait for response with timeout
    Timer(const Duration(seconds: 5), () {
      unsubscribe();
      if (!responded && !completer.isCompleted) {
        completer.completeError('Health check timeout');
      }
    });

    return completer.future;
  }

  // Ensure user is in their room (handles reconnection scenarios)
  void _ensureUserRoomMembership() {
    if (_currentUserId != null && isConnected) {
      final roomName = 'user_$_currentUserId';
      if (_currentUserRoom != roomName) {
        debugPrint('GlobalSocket: Ensuring membership in user room $roomName');
        _globalSocket?.emit('join_user_room', _currentUserId);
        _currentUserRoom = roomName;
      }
    }
  }

  void _setupGlobalSocketListeners() {
    // Clear any existing listeners first
    _globalSocket?.clearListeners();

    _globalSocket?.onConnect((_) {
      _isConnected = true;
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _lastConnectionTime = DateTime.now();
      _lastPongTime = DateTime.now();

      debugPrint('GlobalSocket: Connected successfully');
      debugPrint('Current User ID: $_currentUserId');

      // Join user's personal room for global events
      if (_currentUserId != null) {
        debugPrint(
            'GlobalSocket: Emitting join_user_room for user $_currentUserId');
        _globalSocket?.emit('join_user_room', _currentUserId);
        _currentUserRoom = 'user_$_currentUserId';
        debugPrint('GlobalSocket: Joined user room $_currentUserRoom');
      } else {
        debugPrint('GlobalSocket: WARNING - No current user ID to join room');
      }

      // Start health monitoring
      _startPingTimer();

      _notifyListeners('connection_status', {'connected': true});
    });

    _globalSocket?.onDisconnect((reason) {
      _isConnected = false;
      _currentUserRoom = null;
      _stopPingTimer();

      debugPrint('GlobalSocket: Disconnected - reason: $reason');

      // Only attempt reconnection if not manually disconnecting
      if (!_isDisconnecting) {
        debugPrint(
            'GlobalSocket: Unexpected disconnection, will attempt reconnection');
        _scheduleReconnection(_currentUserId);
      }

      _notifyListeners('connection_status', {'connected': false});
    });

    _globalSocket?.onError((error) {
      debugPrint('GlobalSocket: Error - $error');
      _notifyListeners('connection_error', {'error': error.toString()});

      // Handle auth errors by not attempting reconnection
      if (error.toString().contains('Authentication error')) {
        debugPrint(
            'GlobalSocket: Authentication error, stopping reconnection attempts');
        return;
      }

      if (!_isDisconnecting && !_isReconnecting) {
        _scheduleReconnection(_currentUserId);
      }
    });

    // Handle server confirmations
    _globalSocket?.on('joined_user_room', (data) {
      debugPrint('GlobalSocket: Confirmed joined user room: $data');
      _currentUserRoom = data['roomName'];
    });

    _globalSocket?.on('left_user_room', (data) {
      debugPrint('GlobalSocket: Confirmed left user room: $data');
      if (_currentUserRoom == data['roomName']) {
        _currentUserRoom = null;
      }
    });

    // Handle pong responses
    _globalSocket?.on('pong', (data) {
      _lastPongTime = DateTime.now();
      debugPrint('GlobalSocket: Received pong from server');
    });

    // Handle user status events
    _globalSocket?.on('user_online', (data) {
      debugPrint('GlobalSocket: User came online: $data');
      _notifyListeners('global_user_status', {
        'userId': data['userId'],
        'status': 'online',
        'timestamp': data['timestamp']
      });
    });

    _globalSocket?.on('user_offline', (data) {
      debugPrint('GlobalSocket: User went offline: $data');
      _notifyListeners('global_user_status', {
        'userId': data['userId'],
        'status': 'offline',
        'timestamp': data['timestamp']
      });
    });

    // Listen for global events
    _setupGlobalEventListeners();
  }

  void _setupGlobalEventListeners() {
    // New message received (regardless of current chat session)
    _globalSocket?.on('global_new_message', (data) {
      debugPrint('GlobalSocket: New message received - $data');

      // Notify listeners (sound will be played by GlobalEventProvider)
      _notifyListeners('global_new_message', data);
    });

    // New conversation created
    _globalSocket?.on('global_new_conversation', (data) {
      debugPrint('GlobalSocket: New conversation created - $data');

      // Notify listeners (sound will be played by GlobalEventProvider)
      _notifyListeners('global_new_conversation', data);
    });

    // New group created
    _globalSocket?.on('global_new_group', (data) {
      debugPrint('GlobalSocket: New group created - $data');

      // Notify listeners (sound will be played by GlobalEventProvider)
      _notifyListeners('global_new_group', data);
    });

    // New notification
    _globalSocket?.on('global_notification', (data) {
      debugPrint('GlobalSocket: New notification - $data');

      // Notify listeners (sound will be played by GlobalEventProvider)
      _notifyListeners('global_notification', data);
    });

    // Incoming call
    _globalSocket?.on('global_incoming_call', (data) {
      debugPrint('GlobalSocket: Incoming call - $data');

      // Notify listeners (sound will be played by GlobalEventProvider)
      _notifyListeners('global_incoming_call', data);
    });

    // User online/offline status
    _globalSocket?.on('global_user_status', (data) {
      debugPrint('GlobalSocket: User status change - $data');

      // Notify listeners
      _notifyListeners('global_user_status', data);
    });

    // Message read status
    _globalSocket?.on('global_message_read', (data) {
      debugPrint('GlobalSocket: Message read status - $data');

      // Notify listeners
      _notifyListeners('global_message_read', data);
    });

    // Typing indicator (global)
    _globalSocket?.on('global_typing', (data) {
      debugPrint('GlobalSocket: Global typing indicator - $data');

      // Notify listeners
      _notifyListeners('global_typing', data);
    });

    // Contact added/removed
    _globalSocket?.on('global_contact_update', (data) {
      debugPrint('GlobalSocket: Contact update - $data');

      // Notify listeners (sound will be played by GlobalEventProvider)
      _notifyListeners('global_contact_update', data);
    });

    // Group member added/removed
    _globalSocket?.on('global_group_member_update', (data) {
      debugPrint('GlobalSocket: Group member update - $data');

      // Notify listeners (sound will be played by GlobalEventProvider)
      _notifyListeners('global_group_member_update', data);
    });

    // Profile update
    _globalSocket?.on('global_profile_update', (data) {
      debugPrint('GlobalSocket: Profile update - $data');

      // Notify listeners
      _notifyListeners('global_profile_update', data);
    });

    // === CHAT-SPECIFIC EVENTS ===

    // New message in current chat session
    _globalSocket?.on('new_message', (data) {
      debugPrint('GlobalSocket: Chat new message - $data');
      _notifyChatListeners('new_message', data);
    });

    // New chat session created
    _globalSocket?.on('new_chat_session', (data) {
      debugPrint('GlobalSocket: New chat session - $data');
      _notifyChatListeners('new_chat_session', data);
    });

    // Typing indicators in chat
    _globalSocket?.on('typing_start', (data) {
      debugPrint('GlobalSocket: Chat typing start - $data');
      _notifyChatListeners('typing_start', data);
    });

    _globalSocket?.on('stop_typing', (data) {
      debugPrint('GlobalSocket: Chat typing stop - $data');
      _notifyChatListeners('stop_typing', data);
    });

    // Message reactions updated
    _globalSocket?.on('message_reactions_updated', (data) {
      debugPrint('GlobalSocket: Message reactions updated - $data');
      _notifyChatListeners('message_reactions_updated', data);
    });

    // Chat-specific confirmations
    _globalSocket?.on('joined_chat', (data) {
      debugPrint('GlobalSocket: Confirmed joined chat: $data');
      _notifyChatListeners('joined_chat', data);
    });

    _globalSocket?.on('left_chat', (data) {
      debugPrint('GlobalSocket: Confirmed left chat: $data');
      _notifyChatListeners('left_chat', data);
    });
  }

  // Start periodic ping to maintain connection health
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(_pingInterval, (timer) {
      if (isConnected && _currentUserId != null) {
        _globalSocket?.emit('ping', {'userId': _currentUserId});

        // Check if we haven't received a pong in too long
        if (_lastPongTime != null) {
          final timeSinceLastPong = DateTime.now().difference(_lastPongTime!);
          if (timeSinceLastPong.inSeconds > 60) {
            debugPrint(
                'GlobalSocket: No pong received for ${timeSinceLastPong.inSeconds} seconds, connection may be stale');
            _scheduleReconnection(_currentUserId);
          }
        }
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // Schedule reconnection with exponential backoff
  void _scheduleReconnection(String? userId) {
    if (_isDisconnecting || userId == null || _isReconnecting) return;

    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      debugPrint('GlobalSocket: Max reconnection attempts reached, giving up');
      return;
    }

    final delay =
        Duration(seconds: _reconnectDelay.inSeconds * _reconnectAttempts);
    debugPrint(
        'GlobalSocket: Scheduling reconnection attempt $_reconnectAttempts in ${delay.inSeconds} seconds');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (!_isDisconnecting && userId == _currentUserId) {
        debugPrint(
            'GlobalSocket: Attempting reconnection $_reconnectAttempts/$_maxReconnectAttempts');
        try {
          await _connect(userId);
        } catch (e) {
          debugPrint(
              'GlobalSocket: Reconnection attempt $_reconnectAttempts failed: $e');
        }
      }
    });
  }

  // Add event listener
  void addEventListener(String event, Function(dynamic) callback) {
    if (!_eventListeners.containsKey(event)) {
      _eventListeners[event] = [];
    }
    _eventListeners[event]!.add(callback);
    debugPrint('GlobalSocket: Added listener for event $event');
  }

  // Remove event listener
  void removeEventListener(String event, Function(dynamic) callback) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.remove(callback);
      if (_eventListeners[event]!.isEmpty) {
        _eventListeners.remove(event);
      }
      debugPrint('GlobalSocket: Removed listener for event $event');
    }
  }

  // Remove all listeners for an event
  void removeAllEventListeners(String event) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners.remove(event);
      debugPrint('GlobalSocket: Removed all listeners for event $event');
    }
  }

  // Notify all listeners for an event
  void _notifyListeners(String event, dynamic data) {
    if (_eventListeners.containsKey(event)) {
      for (var listener in _eventListeners[event]!) {
        try {
          listener(data);
        } catch (e) {
          debugPrint('GlobalSocket: Error in listener for event $event - $e');
        }
      }
    }
  }

  // Emit events to server
  void emitGlobalEvent(String event, dynamic data) {
    if (isConnected && _globalSocket != null) {
      _globalSocket!.emit(event, data);
      debugPrint('GlobalSocket: Emitted event $event with data $data');
    } else {
      debugPrint('GlobalSocket: Cannot emit event $event - not connected');
    }
  }

  // Update user online status
  void updateUserStatus(String status) {
    emitGlobalEvent('update_user_status', {
      'userId': _currentUserId,
      'status': status, // 'online', 'offline', 'away'
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Mark message as read globally
  void markMessageAsRead(String messageId, String chatSessionId) {
    emitGlobalEvent('mark_message_read', {
      'messageId': messageId,
      'chatSessionId': chatSessionId,
      'userId': _currentUserId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Send typing indicator globally
  void sendGlobalTyping(String chatSessionId, bool isTyping) {
    emitGlobalEvent('global_typing_indicator', {
      'chatSessionId': chatSessionId,
      'userId': _currentUserId,
      'isTyping': isTyping,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Clean disconnect helper
  Future<void> _cleanDisconnect() async {
    _isDisconnecting = true;

    _stopPingTimer();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;

    if (_globalSocket != null) {
      // Leave user room before disconnecting
      if (_currentUserId != null && isConnected) {
        try {
          _globalSocket?.emit('leave_user_room', _currentUserId);
          // Give time for the leave event to be processed
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          debugPrint('GlobalSocket: Error leaving user room: $e');
        }
      }

      // Clear all listeners
      _eventListeners.clear();
      _chatEventListeners.clear(); // Clear chat listeners too

      // Disconnect socket
      try {
        _globalSocket?.disconnect();
        _globalSocket?.dispose();
      } catch (e) {
        debugPrint('GlobalSocket: Error during disconnect: $e');
      }

      _globalSocket = null;
    }

    _isConnected = false;
    _currentUserId = null;
    _currentUserRoom = null;
    _lastConnectionTime = null;
    _lastPongTime = null;

    _isDisconnecting = false;
  }

  // Disconnect global socket
  Future<void> disconnectGlobalSocket() async {
    debugPrint('GlobalSocket: Disconnecting global socket');

    await _cleanDisconnect();

    // Stop any playing sounds
    _soundService.stopAllSounds();

    debugPrint('GlobalSocket: Disconnected successfully');
  }

  // Get connection info
  Map<String, dynamic> getConnectionInfo() {
    return {
      'isConnected': isConnected,
      'currentUserId': _currentUserId,
      'currentUserRoom': _currentUserRoom,
      'hasSocket': _globalSocket != null,
      'listenerCount': _eventListeners.length,
      'reconnectAttempts': _reconnectAttempts,
      'isReconnecting': _isReconnecting,
      'lastConnectionTime': _lastConnectionTime?.toIso8601String(),
      'lastPongTime': _lastPongTime?.toIso8601String(),
      'socketConnected': _globalSocket?.connected,
    };
  }
}
