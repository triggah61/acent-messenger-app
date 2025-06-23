import 'dart:convert';
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/services/socket_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:acent_messenger/services/auth_service.dart';
import 'package:acent_messenger/models/chat_session.dart';

class ChatProvider with ChangeNotifier {
  final AuthService _authService;
  final SocketService _socketService = SocketService.instance;
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
    _socketService.removeNewSessionListener(_newSessionListener);
    super.dispose();
  }

  Future<void> _initializeSocket() async {
    try {
      await _socketService.initializeSocket();
      _newSessionListener = _socketService.onNewSession((data) {
        print("ChatProvider - _initializeSocket: New session event received");
        print(data);
        fetchSessions(refresh: true);
      });
    } catch (e) {
      print('Failed to initialize socket: $e');
    }
  }

  Future<void> fetchSessions({bool refresh = false}) async {
    print("ChatProvider - fetchSessions: Starting fetch. Refresh: $refresh");
    if (_isLoading) {
      print("ChatProvider - fetchSessions: Already loading, returning");
      return;
    }
    if (refresh) {
      print("ChatProvider - fetchSessions: Refreshing, clearing existing sessions");
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

      final url = '${Config.baseApiUrl}/user/chat/sessionList?page=$_currentPage&limit=$_limit';
      print("ChatProvider - fetchSessions: Requesting URL: $url");

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print("ChatProvider - fetchSessions: Response status: ${response.statusCode}");
      print("ChatProvider - fetchSessions: Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final List<dynamic> docs = data['docs'];
        print("ChatProvider - fetchSessions: Found ${docs.length} sessions");
        
        final newSessions = docs.map((doc) => ChatSession.fromJson(doc)).toList();
        print("ChatProvider - fetchSessions: Parsed ${newSessions.length} sessions");
        
        _sessions.addAll(newSessions);
        print("ChatProvider - fetchSessions: Total sessions now: ${_sessions.length}");
        
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

  // Clear all chat data (for logout)
  void clearAllData() {
    _sessions.clear();
    _isLoading = false;
    _hasMore = true;
    _currentPage = 1;
    // Disconnect socket to prevent old data from coming through
    _socketService.disconnect();
    notifyListeners();
  }
} 