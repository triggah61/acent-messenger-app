import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/config.dart';
import '../services/auth_service.dart';

class ContactService {
  final AuthService _authService;

  ContactService(this._authService);

  Future<void> sendInvitation(String dialCode, String phone) async {
    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/contact/invite'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'dialCode': dialCode,
          'phone': phone,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to send invitation');
      }
    } catch (e) {
      print('Error in sendInvitation: $e');
      rethrow;
    }
  }
} 