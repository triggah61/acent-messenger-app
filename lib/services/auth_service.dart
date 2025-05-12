import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  // For Android Emulator, use 10.0.2.2 instead of localhost
  // For iOS Simulator, use localhost
  // For physical devices, use your computer's IP address
  static const String baseUrl = 'http://192.168.0.102:8000/api';  // For Android Emulator
  // static const String baseUrl = 'http://localhost:8000/api';  // For iOS Simulator
  // static const String baseUrl = 'http://192.168.1.xxx:8000/api';  // For physical devices (replace xxx with your IP)
  
  final storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> login(String phoneNumber, String password) async {
    print("Printing full url: $baseUrl/auth/login");
    print(Uri.parse('$baseUrl/auth/login'));
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone_number': phoneNumber,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Store the token
        await storage.write(key: 'jwt_token', value: data['token']);
        // Store phone number for future use
        await storage.write(key: 'phone_number', value: phoneNumber);
        return data;
      } else {
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to the server: $e');
    }
  }

  Future<void> logout() async {
    await storage.delete(key: 'jwt_token');
    await storage.delete(key: 'phone_number');
  }

  Future<String?> getToken() async {
    return await storage.read(key: 'jwt_token');
  }

  Future<String?> getPhoneNumber() async {
    return await storage.read(key: 'phone_number');
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }
} 