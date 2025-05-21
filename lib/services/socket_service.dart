import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/models/message.dart';
import 'package:acent_messenger/services/auth_service.dart';

class SocketService {
  static SocketService? _instance;
  IO.Socket? _socket;
  final AuthService _authService = AuthService();
  final Map<String, Function(dynamic)> _listeners = {};

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

  // Join a chat session
  void joinChatSession(String chatSessionId) {
    _socket?.emit('join_chat', chatSessionId);
  }

  // Leave a chat session
  void leaveChatSession(String chatSessionId) {
    _socket?.emit('leave_chat', chatSessionId);
  }

  // Listen for new messages
  void onNewMessage(Function(Message) callback) {
    final listener = (data) {
      print('new_message: $data');
      final message = Message.fromJson(data);
      callback(message);
    };
    _socket?.on('new_message', listener);
    _listeners['new_message'] = listener;
  }

  void onNewSession(Function(List<dynamic>) callback) {
    final listener = (data) {
      callback(data);
    };
    _socket?.on('new_chat_session', listener);
    _listeners['new_chat_session'] = listener;
  }

  void removeNewSessionListener() {
    if (_listeners.containsKey('new_chat_session')) {
      _socket?.off('new_chat_session', _listeners['new_chat_session']);
      _listeners.remove('new_chat_session');
    }
  }

  // Remove new message listener
  void removeNewMessageListener() {
    if (_listeners.containsKey('new_message')) {
      _socket?.off('new_message', _listeners['new_message']);
      _listeners.remove('new_message');
    }
  }

  // Listen for typing events
  void onTyping(Function(String userId, bool isTyping) callback) {
    final listener = (data) {
      callback(data['userId'], data['isTyping']);
    };
    _socket?.on('typing', listener);
    _listeners['typing'] = listener;
  }

  // Remove typing listener
  void removeTypingListener() {
    if (_listeners.containsKey('typing')) {
      _socket?.off('typing', _listeners['typing']);
      _listeners.remove('typing');
    }
  }

  // Listen for reaction updates
  void onMessageReactionsUpdated(Function(Map<String, dynamic>) callback) {
    final listener = (data) {
      callback(data);
    };
    _socket?.on('message_reactions_updated', listener);
    _listeners['message_reactions_updated'] = listener;
  }

  // Remove reaction updates listener
  void removeReactionUpdatesListener() {
    if (_listeners.containsKey('message_reactions_updated')) {
      _socket?.off('message_reactions_updated', _listeners['message_reactions_updated']);
      _listeners.remove('message_reactions_updated');
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
    _listeners.forEach((event, listener) {
      _socket?.off(event, listener);
    });
    _listeners.clear();
    
    _socket?.disconnect();
    _socket = null;
  }
} 