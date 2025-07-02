import 'dart:convert';
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/services/pusher_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:acent_messenger/services/auth_service.dart';
import 'package:acent_messenger/models/chat_session.dart';

class ChatProvider with ChangeNotifier {
  final AuthService _authService;
  final PusherService _pusherService = PusherService.instance;
  List<ChatSession> _sessions = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _limit = 10;

  // Store listener reference for proper cleanup
  Function(dynamic)? _newSessionListener;

  ChatProvider(this._authService) {
    _initializeSocket();
  }

  List<ChatSession> get sessions => _sessions;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  @override
  void dispose() {
    if (_newSessionListener != null) {
      _pusherService.removeChatEventListener(
          'new_chat_session', _newSessionListener!);
    }
    super.dispose();
  }

  Future<void> _initializeSocket() async {
    try {
      // The global socket should already be initialized by GlobalEventProvider
      // We just need to listen for new session events

      _newSessionListener = (data) {
        print("ChatProvider - _initializeSocket: New session event received");
        print(data);
        // Use smart update instead of full refresh
        addNewSession(data);
      };

      _pusherService.addChatEventListener(
          'new_chat_session', _newSessionListener!);

      print('ChatProvider: Socket listener initialized');
    } catch (e) {
      print('ChatProvider: Failed to initialize socket listener: $e');
    }
  }

  Future<void> fetchSessions({bool refresh = false}) async {
    print("ChatProvider - fetchSessions: Starting fetch. Refresh: $refresh");
    if (_isLoading) {
      print("ChatProvider - fetchSessions: Already loading, returning");
      return;
    }
    if (refresh) {
      print(
          "ChatProvider - fetchSessions: Refreshing, clearing existing sessions");
      _sessions = [];
      _currentPage = 1;
      _hasMore = true;
    }
    if (!_hasMore) {
      print("ChatProvider - fetchSessions: No more sessions to load");
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final token = await _authService.getToken();
      if (token == null) {
        print("ChatProvider - fetchSessions: No token found");
        throw Exception('No token found');
      }
      print("ChatProvider - fetchSessions: Token found, making API request");

      final url =
          '${Config.baseApiUrl}/user/chat/sessionList?page=$_currentPage&limit=$_limit';
      print("ChatProvider - fetchSessions: Requesting URL: $url");

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print(
          "ChatProvider - fetchSessions: Response status: ${response.statusCode}");
      print("ChatProvider - fetchSessions: Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final List<dynamic> docs = data['docs'];
        print("ChatProvider - fetchSessions: Found ${docs.length} sessions");

        final newSessions =
            docs.map((doc) => ChatSession.fromJson(doc)).toList();
        print(
            "ChatProvider - fetchSessions: Parsed ${newSessions.length} sessions");

        _sessions.addAll(newSessions);
        print(
            "ChatProvider - fetchSessions: Total sessions now: ${_sessions.length}");

        _hasMore = data['hasNextPage'] ?? false;
        print("ChatProvider - fetchSessions: Has more pages: $_hasMore");

        _currentPage++;
        print("ChatProvider - fetchSessions: Next page will be: $_currentPage");
      } else {
        print("ChatProvider - fetchSessions: Error response: ${response.body}");
        throw Exception('Failed to fetch chat sessions: ${response.body}');
      }
    } catch (e) {
      print('ChatProvider - fetchSessions Error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
      print("ChatProvider - fetchSessions: Completed fetch");
    }
  }

  Future<void> refreshSessions() async {
    print("ChatProvider - refreshSessions: Starting refresh");
    try {
      await fetchSessions(refresh: true);
      print("ChatProvider - refreshSessions: Refresh completed successfully");
    } catch (e) {
      print("ChatProvider - refreshSessions: Error during refresh - $e");
      rethrow;
    }
  }

  // Smart update: Update existing session with new message or add new session
  void updateSessionWithNewMessage(Map<String, dynamic> messageData) {
    try {
      print(
          "ChatProvider - updateSessionWithNewMessage: Processing message data");

      final chatSessionId = messageData['chatSession'] as String?;
      if (chatSessionId == null) {
        print(
            "ChatProvider - updateSessionWithNewMessage: No chatSessionId found");
        return;
      }

      // Find existing session
      final existingIndex =
          _sessions.indexWhere((session) => session.id == chatSessionId);

      if (existingIndex != -1) {
        // Update existing session
        print(
            "ChatProvider - updateSessionWithNewMessage: Updating existing session $chatSessionId");
        _updateExistingSession(existingIndex, messageData);
      } else {
        // This might be a new session, let's fetch it specifically
        print(
            "ChatProvider - updateSessionWithNewMessage: Session not found, might be new session");
        _handlePotentialNewSession(chatSessionId);
      }

      notifyListeners();
    } catch (e) {
      print("ChatProvider - updateSessionWithNewMessage: Error - $e");
      // Fallback to refresh if smart update fails
      fetchSessions(refresh: true);
    }
  }

  void _updateExistingSession(
      int sessionIndex, Map<String, dynamic> messageData) {
    final session = _sessions[sessionIndex];

    // Create updated last message
    final updatedLastMessage = LastMessage(
      id: messageData['_id'] ?? '',
      sender: messageData['sender'] ?? '',
      content: messageData['content'] ?? '',
      attachments: messageData['attachments'] ?? [],
      status: messageData['status'] ?? 'sent',
      createdAt: messageData['createdAt'] != null
          ? DateTime.parse(messageData['createdAt'])
          : DateTime.now(),
    );

    // Create updated session
    final updatedSession = ChatSession(
      id: session.id,
      title: session.title,
      type: session.type,
      lastMessage: updatedLastMessage,
      createdBy: session.createdBy,
      otherUser: session.otherUser,
      status: session.status,
      recipients: session.recipients,
      photo: session.photo,
      createdAt: DateTime.now(), // Update to current time to move to top
    );

    // Remove from current position and add to top
    _sessions.removeAt(sessionIndex);
    _sessions.insert(0, updatedSession);

    print(
        "ChatProvider - _updateExistingSession: Updated session ${session.id} and moved to top");
  }

  Future<void> _handlePotentialNewSession(String chatSessionId) async {
    try {
      print(
          "ChatProvider - _handlePotentialNewSession: Fetching session $chatSessionId");

      final token = await _authService.getToken();
      if (token == null) return;

      // Try to fetch the specific session (this would need a new API endpoint)
      // For now, we'll do a limited refresh to get the latest session
      _sessions.clear();
      _currentPage = 1;
      _hasMore = true;
      await fetchSessions();
    } catch (e) {
      print("ChatProvider - _handlePotentialNewSession: Error - $e");
    }
  }

  // Add new session to the top of the list
  void addNewSession(Map<String, dynamic> sessionData) {
    try {
      print("ChatProvider - addNewSession: Adding new session");

      final newSession = ChatSession.fromJson(sessionData);

      // Check if session already exists
      final existingIndex =
          _sessions.indexWhere((session) => session.id == newSession.id);

      if (existingIndex == -1) {
        // Add to top of list
        _sessions.insert(0, newSession);
        print(
            "ChatProvider - addNewSession: Added new session ${newSession.id}");
      } else {
        // Move existing session to top
        final existingSession = _sessions.removeAt(existingIndex);
        _sessions.insert(0, existingSession);
        print(
            "ChatProvider - addNewSession: Moved existing session ${newSession.id} to top");
      }

      notifyListeners();
    } catch (e) {
      print("ChatProvider - addNewSession: Error - $e");
      // Fallback to refresh if smart add fails
      fetchSessions(refresh: true);
    }
  }

  // Clear all chat data (for logout)
  void clearAllData() {
    _sessions.clear();
    _isLoading = false;
    _hasMore = true;
    _currentPage = 1;
    // Note: Global socket should remain connected and be managed by GlobalEventProvider
    notifyListeners();
  }
}
