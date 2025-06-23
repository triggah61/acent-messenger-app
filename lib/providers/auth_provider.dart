import 'dart:convert';

import 'package:acent_messenger/constants/config.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/global_socket_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final GlobalSocketService _globalSocketService = GlobalSocketService.instance;
  Profile? _profile;
  bool _isLoading = true; // Start with loading true
  bool _isInitialized = false;
  String? _token;
  String? _userId;
  
  // Callback to clear data from other providers
  Function()? _clearAllDataCallback;
  
  // Global events callback
  Function(String)? _initializeGlobalEventsCallback;

  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _profile != null && _token != null;
  bool get isInitialized => _isInitialized;
  String? get token => _token;
  String? get userId => _userId;
  
  // Set callback to clear data from other providers
  void setClearAllDataCallback(Function() callback) {
    _clearAllDataCallback = callback;
  }
  
  // Set callback to initialize global events
  void setInitializeGlobalEventsCallback(Function(String) callback) {
    _initializeGlobalEventsCallback = callback;
  }

  Future<String?> getUserId() async {
    if (_userId != null) return _userId;
    final storage = const FlutterSecureStorage();
    _userId = await storage.read(key: 'userId');
    return _userId;
  }

  // Call this after successful login to fetch profile
  Future<void> handleLoginSuccess(String token) async {
    _isLoading = true;
    notifyListeners();
    
    try {
      await _authService.storage.write(key: 'jwt_token', value: token);
      _token = token;
      await fetchProfile();
      
      // Initialize global events after successful login
      if (_profile?.id != null && _initializeGlobalEventsCallback != null) {
        debugPrint('AuthProvider: Initializing global events for user ${_profile!.id}');
        _initializeGlobalEventsCallback!(_profile!.id);
        
        // Update user status to online
        _globalSocketService.updateUserStatus('online');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Manual profile fetch
  Future<void> fetchProfile() async {

    print("AuthProvider - fetchProfile: isLoading: $_isLoading");
    
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
        
        if (response.statusCode == 200) {
          print("Profile: ${response.body}, ${response.statusCode}");
          final data = jsonDecode(response.body);
          print("Profile Data: ${data['data']['id']}");
          _profile = Profile.fromJson(data['data']);
          _isInitialized = true;
          print(" AuthMiddleware: Profile fetched: ${_profile?.toJson()}");
          
          // Ensure global events are initialized if callback is set and we have a profile
          if (_profile?.id != null && _initializeGlobalEventsCallback != null) {
            debugPrint('AuthProvider: Ensuring global events for user ${_profile!.id}');
            _initializeGlobalEventsCallback!(_profile!.id);
            
            // Update user status to online
            _globalSocketService.updateUserStatus('online');
          }
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
    // Update user status to offline before logout
    if (_profile?.id != null) {
      _globalSocketService.updateUserStatus('offline');
    }
    
    // Disconnect global socket
    await _globalSocketService.disconnectGlobalSocket();
    
    await _authService.logout();
    _profile = null;
    _isInitialized = false;
    _token = null;
    _userId = null;
    
    // Clear secure storage
    final storage = const FlutterSecureStorage();
    await storage.delete(key: 'token');
    await storage.delete(key: 'userId');
    await storage.delete(key: 'jwt_token');
    await storage.delete(key: 'phone_number');
    
    // Clear data from all other providers
    if (_clearAllDataCallback != null) {
      _clearAllDataCallback!();
    }
    
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
        _token = token; // Set the token
        await fetchProfile(); // This will set the profile if token is valid
      } else {
        _profile = null;
        _token = null;
      }
    } catch (e) {
      _profile = null;
      _token = null;
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
  
  // Update user status manually
  void updateUserStatus(String status) {
    if (_profile?.id != null) {
      _globalSocketService.updateUserStatus(status);
    }
  }
  
  // Get global socket connection info
  Map<String, dynamic> getGlobalSocketInfo() {
    return _globalSocketService.getConnectionInfo();
  }
}
