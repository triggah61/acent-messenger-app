import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/models/message.dart';
import 'package:acent_messenger/services/auth_service.dart';

class SocketService {
  static SocketService? _instance;
  IO.Socket? _socket;
  final AuthService _authService = AuthService();
  final Map<String, List<Function(dynamic)>> _listeners = {};

  // Singleton pattern
  static SocketService get instance {
    _instance ??= SocketService();
    return _instance!;
  }

  // Initialize socket connection
  Future<void> initializeSocket() async {
    if (_socket != null) return;

    final token = await _authService.getToken();
    if (token == null) throw Exception('No authentication token available');

    _socket = IO.io(
      Config.baseApiUrl.replaceAll('/api', ''),
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setPath('/api/socket.io')
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );

    _socket!.connect();
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    _socket?.onConnect((_) {
      print('Socket connected');
    });

    _socket?.onDisconnect((_) {
      print('Socket disconnected');
    });

    _socket?.onError((error) {
      print('Socket error: $error');
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
    _socket?.emit('join_chat', chatSessionId);
  }

  // Leave a chat session
  void leaveChatSession(String chatSessionId) {
    _socket?.emit('leave_chat', chatSessionId);
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
  Function(dynamic) onMessageReactionsUpdated(Function(Map<String, dynamic>) callback) {
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
    _socket?.emit('typing', {
      'chatSessionId': chatSessionId,
      'isTyping': isTyping,
    });
  }

  // Disconnect socket
  void disconnect() {
    // Remove all listeners
    _listeners.forEach((event, listeners) {
      _socket?.off(event);
    });
    _listeners.clear();
    
    _socket?.disconnect();
    _socket = null;
  }
} 