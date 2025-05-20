import 'dart:convert';

import 'package:chattingapp/constants/config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/profile.dart';
import '../services/auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  Profile? _profile;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _token;
  String? _userId;

  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _profile != null;
  bool get isInitialized => _isInitialized;
  String? get token => _token;
  String? get userId => _userId;
  

  Future<String?> getUserId() async {
    if (_userId != null) return _userId;
    final storage = const FlutterSecureStorage();
    _userId = await storage.read(key: 'userId');
    return _userId;
  }

  // Call this after successful login to fetch profile
  Future<void> handleLoginSuccess(String token) async {
    await _authService.storage.write(key: 'jwt_token', value: token);
    await fetchProfile();
  }

  // Manual profile fetch
  Future<void> fetchProfile() async {
    if (_isLoading) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _authService.getToken();
      if (token != null) {
        final response = await http.get(
          Uri.parse('${Config.baseApiUrl}/user/profile/info'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token'
          },
        );

        // print("Response: ${response.body}, ${response.statusCode}");
        
        if (response.statusCode == 200) {
          print("Profile: ${response.body}, ${response.statusCode}");
          final data = jsonDecode(response.body);
          print("Profile Data: ${data['data']['id']}");
          _profile = Profile.fromJson(data['data']);
          _isInitialized = true;
          print(" AuthMiddleware: Profile fetched: ${_profile?.toJson()}");
        } else {
          _profile = null;
          await _authService.logout(); // Clear invalid token
        }
      } else {
        _profile = null;
      }
    } catch (e) {
      _profile = null;
      print("Error fetching profile: $e");
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _profile = null;
    _isInitialized = false;
    _token = null;
    _userId = null;
    final storage = const FlutterSecureStorage();
    await storage.delete(key: 'token');
    await storage.delete(key: 'userId');
    notifyListeners();
  }

  // Initial auth check - only called once when app starts
  Future<void> checkAuthStatus() async {
    if (_isInitialized) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _authService.getToken();
      if (token != null) {
        await fetchProfile();
      }
    } catch (e) {
      _profile = null;
      print("Error checking auth status: $e");
    } finally {
      _isLoading = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setToken(String token) async {
    _token = token;
    final storage = const FlutterSecureStorage();
    await storage.write(key: 'token', value: token);
    notifyListeners();
  }

  Future<void> setUserId(String userId) async {
    _userId = userId;
    final storage = const FlutterSecureStorage();
    await storage.write(key: 'userId', value: userId);
    notifyListeners();
  }
}
