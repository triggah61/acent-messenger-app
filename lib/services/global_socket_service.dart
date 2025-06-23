import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/services/auth_service.dart';
import 'package:acent_messenger/services/sound_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

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

  // Singleton pattern
  static GlobalSocketService get instance {
    _instance ??= GlobalSocketService();
    return _instance!;
  }

  bool get isConnected => _isConnected;
  String? get currentUserId => _currentUserId;

  // Initialize global socket connection for a specific user
  Future<void> initializeGlobalSocket(String userId) async {
    debugPrint('GlobalSocket: Attempting to initialize for user $userId');
    debugPrint('GlobalSocket: Current state - isConnected: $_isConnected, currentUserId: $_currentUserId, hasSocket: ${_globalSocket != null}');
    
    // If we have the same user and are connected, check if socket is actually working
    if (_globalSocket != null && _currentUserId == userId && _isConnected) {
      debugPrint('GlobalSocket: Already connected for user $userId, checking socket health');
      // Test the connection by emitting a ping
      try {
        _globalSocket?.emit('ping', {'userId': userId});
        debugPrint('GlobalSocket: Socket appears healthy, skipping reconnection');
        return;
      } catch (e) {
        debugPrint('GlobalSocket: Socket health check failed, will reconnect - $e');
      }
    }

    // Always disconnect first to ensure clean state
    if (_globalSocket != null) {
      debugPrint('GlobalSocket: Disconnecting existing socket before reconnecting');
      await disconnectGlobalSocket();
      // Add a small delay to ensure cleanup is complete
      await Future.delayed(const Duration(milliseconds: 500));
    }

    try {
      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token available');

      debugPrint('GlobalSocket: Creating new socket connection for user $userId');

      _globalSocket = IO.io(
        Config.baseApiUrl.replaceAll('/api', ''),
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setPath('/api/socket.io')
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .build(),
      );

      _globalSocket!.connect();
      _setupGlobalSocketListeners();
      _currentUserId = userId;
      
      debugPrint('GlobalSocket: Connection initiated for user $userId');
    } catch (e) {
      debugPrint('GlobalSocket: Failed to initialize - $e');
      throw e;
    }
  }

  void _setupGlobalSocketListeners() {
    _globalSocket?.onConnect((_) {
      _isConnected = true;
      debugPrint('GlobalSocket: Connected successfully');
      debugPrint('Current User ID: $_currentUserId');
      
      // Join user's personal room for global events
      if (_currentUserId != null) {
        debugPrint('GlobalSocket: Emitting join_user_room for user $_currentUserId');
        _globalSocket?.emit('join_user_room', _currentUserId);
        debugPrint('GlobalSocket: Joined user room $_currentUserId');
      } else {
        debugPrint('GlobalSocket: WARNING - No current user ID to join room');
      }
      
      _notifyListeners('connection_status', {'connected': true});
    });

    _globalSocket?.onDisconnect((_) {
      _isConnected = false;
      debugPrint('GlobalSocket: Disconnected');
      _notifyListeners('connection_status', {'connected': false});
    });

    _globalSocket?.onError((error) {
      debugPrint('GlobalSocket: Error - $error');
      _notifyListeners('connection_error', {'error': error.toString()});
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
    if (_isConnected && _globalSocket != null) {
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

  // Disconnect global socket
  Future<void> disconnectGlobalSocket() async {
    debugPrint('GlobalSocket: Disconnecting global socket');
    
    if (_globalSocket != null) {
      // Leave user room before disconnecting
      if (_currentUserId != null) {
        _globalSocket?.emit('leave_user_room', _currentUserId);
      }
      
      // Clear all listeners
      _eventListeners.clear();
      
      // Disconnect socket
      _globalSocket?.disconnect();
      _globalSocket = null;
    }
    
    _isConnected = false;
    _currentUserId = null;
    
    // Stop any playing sounds
    _soundService.stopAllSounds();
    
    debugPrint('GlobalSocket: Disconnected successfully');
  }

  // Get connection info
  Map<String, dynamic> getConnectionInfo() {
    return {
      'isConnected': _isConnected,
      'currentUserId': _currentUserId,
      'hasSocket': _globalSocket != null,
      'listenerCount': _eventListeners.length,
    };
  }
} 