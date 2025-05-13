import 'dart:convert';

import 'package:chattingapp/services/api_request.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/profile.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  Profile? _profile;
  bool _isLoading = false;
  bool _isInitialized = false;

  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _profile != null;
  bool get isInitialized => _isInitialized;
  
  // Get token for API requests
  Future<String?> getToken() async {
    return await _authService.getToken();
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
          Uri.parse('${ApiRequest.baseApiUrl}/user/profile/info'),
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
}
