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

  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _profile != null;
  

  Future<void> fetchProfile() async {
    final token = await _authService.getToken();
    if (token != null) {
      final response = await http.post(
        Uri.parse('${ApiRequest.baseApiUrl}/profile/info'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _profile = Profile.fromJson(data);
      } else {
        _profile = null;
        print("No token found");
      }
    } else {
      _profile = null;
      print("No token found");
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _profile = null;
    notifyListeners();
  }

  Future<void> checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _authService.getToken();
      if (token != null) {
        // Fetch profile data using the token
        await fetchProfile();
      }
    } catch (e) {
      _profile = null;
      print(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
