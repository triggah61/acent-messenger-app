import 'dart:convert';
import 'package:chattingapp/constants/config.dart';
import 'package:chattingapp/services/socket_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:chattingapp/services/auth_service.dart';
import 'package:chattingapp/models/chat_session.dart';

class GroupProvider with ChangeNotifier {
  final AuthService _authService;
  final SocketService _socketService = SocketService.instance;
  List<ChatSession> _sessions = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _limit = 10;

  GroupProvider(this._authService) {
    _initializeSocket();
  }

  List<ChatSession> get sessions => _sessions;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;


  @override
  void dispose() {
    _socketService.removeNewSessionListener();
    super.dispose();
  }

  Future<void> _initializeSocket() async {
    try {
      await _socketService.initializeSocket();
      _socketService.onNewSession((data) {
        print("ChatProvider - _initializeSocket: New session event received");
        print(data);
        fetchSessions(refresh: true);
      });
    } catch (e) {
      print('Failed to initialize socket: $e');
    }
  }

  Future<void> fetchSessions({bool refresh = false}) async {
    print("GroupProvider - fetchSessions: Starting fetch. Refresh: $refresh");
    if (_isLoading) {
      print("GroupProvider - fetchSessions: Already loading, returning");
      return;   
    }
    if (refresh) {
      print("GroupProvider - fetchSessions: Refreshing, clearing existing sessions");
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

      final url = '${Config.baseApiUrl}/user/chat/sessionList?page=$_currentPage&limit=$_limit&type=group';
      print("GroupProvider - fetchSessions: Requesting URL: $url");

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print("GroupProvider - fetchSessions: Response status: ${response.statusCode}");
      print("GroupProvider - fetchSessions: Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        final List<dynamic> docs = data['docs'];
        print("GroupProvider - fetchSessions: Found ${docs.length} sessions");
        
        final newSessions = docs.map((doc) => ChatSession.fromJson(doc)).toList();
        print("GroupProvider - fetchSessions: Parsed ${newSessions.length} sessions");
        
        _sessions.addAll(newSessions);
        print("GroupProvider - fetchSessions: Total sessions now: ${_sessions.length}");
        
        _hasMore = data['hasNextPage'] ?? false;
        print("GroupProvider - fetchSessions: Has more pages: $_hasMore");
        
        _currentPage++;
        print("GroupProvider - fetchSessions: Next page will be: $_currentPage");
      } else {
        print("GroupProvider - fetchSessions: Error response: ${response.body}");
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
    await fetchSessions(refresh: true);
  }
} 