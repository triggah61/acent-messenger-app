import 'dart:convert';
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/services/pusher_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:acent_messenger/services/auth_service.dart';
import 'package:acent_messenger/models/chat_session.dart';

class GroupProvider with ChangeNotifier {
  final AuthService _authService;
  final PusherService _pusherService = PusherService.instance;
  List<ChatSession> _sessions = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _limit = 10;

  // Store listener reference for proper cleanup
  Function(dynamic)? _newSessionListener;

  GroupProvider(this._authService) {
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
        print("GroupProvider - _initializeSocket: New session event received");
        print(data);
        // Use smart update instead of full refresh
        addNewSession(data);
      };

      _pusherService.addChatEventListener(
          'new_chat_session', _newSessionListener!);

      print('GroupProvider: Socket listener initialized');
    } catch (e) {
      print('GroupProvider: Failed to initialize socket listener: $e');
    }
  }

  Future<void> fetchSessions({bool refresh = false}) async {
    print("GroupProvider - fetchSessions: Starting fetch. Refresh: $refresh");
    if (_isLoading) {
      print("GroupProvider - fetchSessions: Already loading, returning");
      return;
    }
    if (refresh) {
      print(
          "GroupProvider - fetchSessions: Refreshing, clearing existing sessions");
      _sessions = [];
      _currentPage = 1;
      _hasMore = true;
    }
    if (!_hasMore) {
      print("GroupProvider - fetchSessions: No more sessions to load");
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final token = await _authService.getToken();
      if (token == null) {
        print("GroupProvider - fetchSessions: No token found");
        throw Exception('No token found');
      }
      print("GroupProvider - fetchSessions: Token found, making API request");

      final url =
          '${Config.baseApiUrl}/user/chat/sessionList?page=$_currentPage&limit=$_limit&type=group';
      print("GroupProvider - fetchSessions: Requesting URL: $url");

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print(
          "GroupProvider - fetchSessions: Response status: ${response.statusCode}");
      print("GroupProvider - fetchSessions: Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final List<dynamic> docs = data['docs'];
        print("GroupProvider - fetchSessions: Found ${docs.length} sessions");

        final newSessions =
            docs.map((doc) => ChatSession.fromJson(doc)).toList();
        print(
            "GroupProvider - fetchSessions: Parsed ${newSessions.length} sessions");

        _sessions.addAll(newSessions);
        print(
            "GroupProvider - fetchSessions: Total sessions now: ${_sessions.length}");

        _hasMore = data['hasNextPage'] ?? false;
        print("GroupProvider - fetchSessions: Has more pages: $_hasMore");

        _currentPage++;
        print(
            "GroupProvider - fetchSessions: Next page will be: $_currentPage");
      } else {
        print(
            "GroupProvider - fetchSessions: Error response: ${response.body}");
        throw Exception('Failed to fetch group sessions: ${response.body}');
      }
    } catch (e) {
      print('GroupProvider - fetchSessions Error: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
      print("GroupProvider - fetchSessions: Completed fetch");
    }
  }

  Future<void> refreshSessions() async {
    print("GroupProvider - refreshSessions: Starting refresh");
    try {
      await fetchSessions(refresh: true);
      print("GroupProvider - refreshSessions: Refresh completed successfully");
    } catch (e) {
      print("GroupProvider - refreshSessions: Error during refresh - $e");
      rethrow;
    }
  }

  // Smart update: Update existing session with new message or add new session
  void updateSessionWithNewMessage(Map<String, dynamic> messageData) {
    try {
      print(
          "GroupProvider - updateSessionWithNewMessage: Processing message data");

      final chatSessionId = messageData['chatSession'] as String?;
      if (chatSessionId == null) {
        print(
            "GroupProvider - updateSessionWithNewMessage: No chatSessionId found");
        return;
      }

      // Find existing session
      final existingIndex =
          _sessions.indexWhere((session) => session.id == chatSessionId);

      if (existingIndex != -1) {
        // Update existing session
        print(
            "GroupProvider - updateSessionWithNewMessage: Updating existing session $chatSessionId");
        _updateExistingSession(existingIndex, messageData);
      } else {
        // This might be a new session, let's fetch it specifically
        print(
            "GroupProvider - updateSessionWithNewMessage: Session not found, might be new session");
        _handlePotentialNewSession(chatSessionId);
      }

      notifyListeners();
    } catch (e) {
      print("GroupProvider - updateSessionWithNewMessage: Error - $e");
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
        "GroupProvider - _updateExistingSession: Updated session ${session.id} and moved to top");
  }

  Future<void> _handlePotentialNewSession(String chatSessionId) async {
    try {
      print(
          "GroupProvider - _handlePotentialNewSession: Fetching session $chatSessionId");

      final token = await _authService.getToken();
      if (token == null) return;

      // Try to fetch the specific session (this would need a new API endpoint)
      // For now, we'll do a limited refresh to get the latest session
      _sessions.clear();
      _currentPage = 1;
      _hasMore = true;
      await fetchSessions();
    } catch (e) {
      print("GroupProvider - _handlePotentialNewSession: Error - $e");
    }
  }

  // Add new session to the top of the list
  void addNewSession(Map<String, dynamic> sessionData) {
    try {
      print("GroupProvider - addNewSession: Adding new session");

      final newSession = ChatSession.fromJson(sessionData);

      // Check if session already exists
      final existingIndex =
          _sessions.indexWhere((session) => session.id == newSession.id);

      if (existingIndex == -1) {
        // Add to top of list
        _sessions.insert(0, newSession);
        print(
            "GroupProvider - addNewSession: Added new session ${newSession.id}");
      } else {
        // Move existing session to top
        final existingSession = _sessions.removeAt(existingIndex);
        _sessions.insert(0, existingSession);
        print(
            "GroupProvider - addNewSession: Moved existing session ${newSession.id} to top");
      }

      notifyListeners();
    } catch (e) {
      print("GroupProvider - addNewSession: Error - $e");
      // Fallback to refresh if smart add fails
      fetchSessions(refresh: true);
    }
  }

  // Clear all group data (for logout)
  void clearAllData() {
    _sessions.clear();
    _isLoading = false;
    _hasMore = true;
    _currentPage = 1;
    // Note: Global socket should remain connected and be managed by GlobalEventProvider
    notifyListeners();
  }
}
