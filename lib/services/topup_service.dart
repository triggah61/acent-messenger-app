import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/config.dart';
import '../services/auth_service.dart';

/// Service for handling top-up related API operations
class TopUpService {
  final AuthService _authService;

  TopUpService(this._authService);


  /// Get all available credit packages
  Future<List<Map<String, dynamic>>> getTopUpPackages() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/topup/packages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch packages');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch packages');
      }
    } catch (e) {
      print('TopUpService: Error fetching packages: $e');
      rethrow;
    }
  }

  /// Verify Google Play top-up purchase
  Future<Map<String, dynamic>> verifyGooglePlayTopUp({
    required String purchaseToken,
    required String productId,
    required String packageId,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/topup/verify-google-play'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'purchaseToken': purchaseToken,
          'productId': productId,
          'packageId': packageId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return {
            'success': true,
            'data': data['data'],
            'message': data['message'] ?? 'Top-up successful',
          };
        } else {
          throw Exception(data['message'] ?? 'Failed to verify top-up');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to verify top-up purchase');
      }
    } catch (e) {
      print('TopUpService: Error verifying top-up: $e');
      rethrow;
    }
  }

  /// Get user's top-up history
  Future<Map<String, dynamic>> getTopUpHistory({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/topup/history?page=$page&limit=$limit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          return data['data'];
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch top-up history');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch top-up history');
      }
    } catch (e) {
      print('TopUpService: Error fetching history: $e');
      rethrow;
    }
  }
}

