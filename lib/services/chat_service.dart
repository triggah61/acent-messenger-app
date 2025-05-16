import 'package:chattingapp/models/chat_session.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/config.dart';
import '../services/auth_service.dart';

class ChatService {
  final AuthService _authService;

  ChatService(this._authService);

  Future<ChatSession> findOrCreateSession(String recipientId) async {
    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/chat/findChatSessionByReceipient/$recipientId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ChatSession.fromJson(data['data']);
      } else {
        throw Exception('Failed to find or create chat session');
      }
    } catch (e) {
      print('Error in findOrCreateSession: $e');
      rethrow;
    }
  }

  Future<ChatSession> createGroup(String title, List<String> recipientIds) async {
    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/chat/createSession'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': title,
          'recepientIds': recipientIds,
          'type': 'group',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ChatSession.fromJson(data['data']);
      } else {
        throw Exception('Failed to create group');
      }
    } catch (e) {
      print('Error in createGroup: $e');
      rethrow;
    }
  }
} 