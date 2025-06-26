import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/models/message.dart';
import 'package:acent_messenger/services/auth_service.dart';
import 'dart:async';

/// **DEPRECATED**: This class is deprecated and should not be used.
/// Use GlobalSocketService instead to avoid multiple socket connections.
///
/// This service was replaced by GlobalSocketService to consolidate all socket
/// communication into a single connection, preventing conflicts and improving
/// connection stability.
@Deprecated(
    'Use GlobalSocketService instead. This will be removed in a future version.')
class SocketService {
  static SocketService? _instance;
  IO.Socket? _socket;
  final AuthService _authService = AuthService();
  final Map<String, List<Function(dynamic)>> _listeners = {};

  // Connection state tracking
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;

  // Singleton pattern
  @Deprecated('Use GlobalSocketService.instance instead')
  static SocketService get instance {
    print(
        'WARNING: SocketService is deprecated. Use GlobalSocketService instead.');
    _instance ??= SocketService();
    return _instance!;
  }

  bool get isConnected => _isConnected && _socket?.connected == true;
  bool get isConnecting => _isConnecting;

  // Initialize socket connection
  Future<void> initializeSocket() async {
    if (_isConnecting) {
      print('SocketService: Already connecting, waiting...');
      return;
    }

    if (_socket != null && isConnected) {
      print('SocketService: Already connected');
      return;
    }

    await _connect();
  }

  Future<void> _connect() async {
    try {
      _isConnecting = true;

      // Clean up any existing socket first
      if (_socket != null) {
        print('SocketService: Cleaning up existing socket');
        await _cleanDisconnect();
      }

      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token available');

      print('SocketService: Creating new socket connection');

      _socket = IO.io(
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

      _socket!.connect();
      _setupSocketListeners();
    } catch (e) {
      print('SocketService: Failed to initialize - $e');
      _isConnecting = false;
      _scheduleReconnection();
      throw e;
    }
  }

  void _setupSocketListeners() {
    // Clear any existing listeners first
    _socket?.clearListeners();

    _socket?.onConnect((_) {
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _reconnectTimer?.cancel();
      print('SocketService: Socket connected');
    });

    _socket?.onDisconnect((reason) {
      _isConnected = false;
      print('SocketService: Socket disconnected - reason: $reason');

      // Only attempt reconnection for unexpected disconnections
      if (reason != 'client namespace disconnect' && reason != 'forced close') {
        _scheduleReconnection();
      }
    });

    _socket?.onError((error) {
      print('SocketService: Socket error: $error');
      _isConnected = false;

      // Don't reconnect on authentication errors
      if (!error.toString().contains('Authentication error')) {
        _scheduleReconnection();
      }
    });

    _socket?.onConnectError((error) {
      print('SocketService: Connection error: $error');
      _isConnecting = false;
      _scheduleReconnection();
    });
  }

  // Schedule reconnection with exponential backoff
  void _scheduleReconnection() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('SocketService: Max reconnection attempts reached');
      return;
    }

    _reconnectAttempts++;
    final delay = Duration(seconds: 2 * _reconnectAttempts);

    print(
        'SocketService: Scheduling reconnection attempt $_reconnectAttempts in ${delay.inSeconds} seconds');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        await _connect();
      } catch (e) {
        print(
            'SocketService: Reconnection attempt $_reconnectAttempts failed: $e');
      }
    });
  }

  // Helper method to add a listener for an event
  Function(dynamic) _addListener(String event, Function(dynamic) callback) {
    if (!_listeners.containsKey(event)) {
      _listeners[event] = [];

      // Set up the socket listener for this event type (only once per event type)
      _socket?.on(event, (data) {
        // Call all registered callbacks for this event
        final listeners = List<Function(dynamic)>.from(_listeners[event] ?? []);
        for (var listener in listeners) {
          try {
            listener(data);
          } catch (e) {
            print('Error in socket listener for event $event: $e');
          }
        }
      });
    }

    _listeners[event]!.add(callback);
    return callback; // Return the callback so it can be used for removal
  }

  // Helper method to remove a specific listener
  void _removeListener(String event, Function(dynamic) callback) {
    if (_listeners.containsKey(event)) {
      _listeners[event]!.remove(callback);

      // If no more listeners for this event, remove the socket listener
      if (_listeners[event]!.isEmpty) {
        _socket?.off(event);
        _listeners.remove(event);
      }
    }
  }

  // Join a chat session
  void joinChatSession(String chatSessionId) {
    if (isConnected) {
      _socket?.emit('join_chat', chatSessionId);
      print('SocketService: Joined chat session: $chatSessionId');
    } else {
      print('SocketService: Cannot join chat session - not connected');
    }
  }

  // Leave a chat session
  void leaveChatSession(String chatSessionId) {
    if (isConnected) {
      _socket?.emit('leave_chat', chatSessionId);
      print('SocketService: Left chat session: $chatSessionId');
    } else {
      print('SocketService: Cannot leave chat session - not connected');
    }
  }

  // Listen for new messages - now returns the callback for removal
  Function(dynamic) onNewMessage(Function(Message) callback) {
    final listener = (data) {
      print('new_message: $data');
      try {
        final message = Message.fromJson(data);
        callback(message);
      } catch (e) {
        print('Error parsing message in onNewMessage: $e');
      }
    };

    return _addListener('new_message', listener);
  }

  // Listen for new sessions - now returns the callback for removal
  Function(dynamic) onNewSession(Function(List<dynamic>) callback) {
    final listener = (data) {
      try {
        callback(data);
      } catch (e) {
        print('Error in onNewSession callback: $e');
      }
    };

    return _addListener('new_chat_session', listener);
  }

  // Remove a specific new message listener
  void removeNewMessageListener(Function(dynamic)? callback) {
    if (callback != null) {
      _removeListener('new_message', callback);
    }
  }

  // Remove a specific new session listener
  void removeNewSessionListener(Function(dynamic)? callback) {
    if (callback != null) {
      _removeListener('new_chat_session', callback);
    }
  }

  // Listen for typing events - now returns the callback for removal
  Function(dynamic) onTyping(Function(String userId, bool isTyping) callback) {
    final listener = (data) {
      try {
        callback(data['userId'], data['isTyping']);
      } catch (e) {
        print('Error in onTyping callback: $e');
      }
    };

    return _addListener('typing', listener);
  }

  // Remove a specific typing listener
  void removeTypingListener(Function(dynamic)? callback) {
    if (callback != null) {
      _removeListener('typing', callback);
    }
  }

  // Listen for reaction updates - now returns the callback for removal
  Function(dynamic) onMessageReactionsUpdated(
      Function(Map<String, dynamic>) callback) {
    final listener = (data) {
      try {
        callback(data);
      } catch (e) {
        print('Error in onMessageReactionsUpdated callback: $e');
      }
    };

    return _addListener('message_reactions_updated', listener);
  }

  // Remove a specific reaction updates listener
  void removeReactionUpdatesListener(Function(dynamic)? callback) {
    if (callback != null) {
      _removeListener('message_reactions_updated', callback);
    }
  }

  // Emit typing event
  void emitTyping(String chatSessionId, bool isTyping) {
    if (isConnected) {
      _socket?.emit('typing', {
        'chatSessionId': chatSessionId,
        'isTyping': isTyping,
      });
    } else {
      print('SocketService: Cannot emit typing - not connected');
    }
  }

  // Clean disconnect helper
  Future<void> _cleanDisconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;

    if (_socket != null) {
      try {
        _socket?.disconnect();
        _socket?.dispose();
      } catch (e) {
        print('SocketService: Error during clean disconnect: $e');
      }
      _socket = null;
    }

    _isConnected = false;
    _isConnecting = false;
  }

  // Disconnect socket
  Future<void> disconnect() async {
    print('SocketService: Disconnecting socket');

    // Remove all listeners
    _listeners.forEach((event, listeners) {
      _socket?.off(event);
    });
    _listeners.clear();

    await _cleanDisconnect();

    print('SocketService: Socket disconnected');
  }

  // Get connection info for debugging
  Map<String, dynamic> getConnectionInfo() {
    return {
      'isConnected': isConnected,
      'isConnecting': _isConnecting,
      'hasSocket': _socket != null,
      'reconnectAttempts': _reconnectAttempts,
      'listenerCount': _listeners.length,
      'socketConnected': _socket?.connected,
    };
  }
}
