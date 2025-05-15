import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:chattingapp/constants/config.dart';
import 'package:chattingapp/models/message.dart';
import 'package:chattingapp/services/auth_service.dart';

class SocketService {
  static SocketService? _instance;
  IO.Socket? _socket;
  final AuthService _authService = AuthService();

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
    _socket?.on('new_message', (data) {
      print('new_message');
      final message = Message.fromJson(data);
      callback(message);
    });
  }

  // Listen for typing events
  void onTyping(Function(String userId, bool isTyping) callback) {
    _socket?.on('typing', (data) {
      callback(data['userId'], data['isTyping']);
    });
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
    _socket?.disconnect();
    _socket = null;
  }
} 