import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../constants/config.dart';
import '../services/auth_service.dart';
import '../models/call.dart';

/**
 * Service for handling call-related API operations
 */
class CallService {
  final AuthService _authService;

  CallService(this._authService);

  /// Get the current platform name for metadata
  String _getPlatform() {
    if (Platform.isAndroid) {
      return 'android';
    } else if (Platform.isIOS) {
      return 'ios';
    } else {
      return 'web'; // Fallback for other platforms
    }
  }

  /// Initiate a new call
  Future<Map<String, dynamic>> initiateCall({
    required List<String> participantIds,
    required String type,
    String? chatSessionId,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/call/initiate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'participantIds': participantIds,
          'type': type,
          if (chatSessionId != null) 'chatSessionId': chatSessionId,
          'metadata': {
            'clientPlatform': _getPlatform(),
            'appVersion': '1.0.0', // You can make this dynamic
          },
        }),
      );

      print(
        'CallService: Initiate call response status: ${response.statusCode}',
      );
      print('CallService: Initiate call response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'call': Call.fromJson(data['data']),
          'channelName': data['channelName'],
          'message': data['message'],
        };
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to initiate call');
      }
    } catch (e) {
      print('CallService: Error initiating call: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Accept an incoming call
  Future<Map<String, dynamic>> acceptCall(String callId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/call/accept/$callId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('CallService: Accept call response status: ${response.statusCode}');
      print('CallService: Accept call response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'call': Call.fromJson(data['data']),
          'message': data['message'],
        };
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to accept call');
      }
    } catch (e) {
      print('CallService: Error accepting call: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Decline an incoming call
  Future<Map<String, dynamic>> declineCall(String callId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/call/decline/$callId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print(
        'CallService: Decline call response status: ${response.statusCode}',
      );
      print('CallService: Decline call response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'call': Call.fromJson(data['data']),
          'message': data['message'],
        };
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to decline call');
      }
    } catch (e) {
      print('CallService: Error declining call: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// End an active call
  Future<Map<String, dynamic>> endCall(
    String callId, {
    String reason = 'normal',
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/call/end/$callId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'reason': reason}),
      );

      print('CallService: End call response status: ${response.statusCode}');
      print('CallService: End call response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'call': Call.fromJson(data['data']),
          'message': data['message'],
        };
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to end call');
      }
    } catch (e) {
      print('CallService: Error ending call: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get Agora token for a call
  Future<AgoraToken?> getCallToken(String callId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/call/token/$callId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      print('CallService: Get token response status: ${response.statusCode}');
      print('CallService: Get token response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AgoraToken.fromJson(data['data']);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to get call token');
      }
    } catch (e) {
      print('CallService: Error getting call token: $e');
      return null;
    }
  }

  /// Get call history
  Future<Map<String, dynamic>> getCallHistory({
    int page = 1,
    int limit = 20,
    String? type,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      // Build query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (type != null) queryParams['type'] = type;
      if (status != null) queryParams['status'] = status;
      if (startDate != null)
        queryParams['startDate'] = startDate.toIso8601String();
      if (endDate != null) queryParams['endDate'] = endDate.toIso8601String();

      final uri = Uri.parse(
        '${Config.baseApiUrl}/user/call/history',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );

      print(
        'CallService: Get call history response status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final callHistory =
            (data['data']['docs'] as List)
                .map((callJson) => Call.fromJson(callJson))
                .toList();

        return {
          'success': true,
          'calls': callHistory,
          'pagination': {
            'currentPage': data['data']['page'],
            'totalPages': data['data']['totalPages'],
            'totalCalls': data['data']['totalDocs'],
            'hasNextPage': data['data']['hasNextPage'],
            'hasPrevPage': data['data']['hasPrevPage'],
          },
        };
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to get call history');
      }
    } catch (e) {
      print('CallService: Error getting call history: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get a specific call by ID (for incoming call notifications)
  Future<Call?> getCallById(String callId) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/call/$callId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      print('CallService: Get call response status: ${response.statusCode}');
      print('CallService: Get call response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return Call.fromJson(data['data']);
      } else if (response.statusCode == 404) {
        print('CallService: Call not found: $callId');
        return null;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to get call');
      }
    } catch (e) {
      print('CallService: Error getting call: $e');
      return null;
    }
  }

  /// Get active calls for user
  Future<List<Call>> getActiveCalls() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/call/active'),
        headers: {'Authorization': 'Bearer $token'},
      );

      print(
        'CallService: Get active calls response status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['data'] as List)
            .map((callJson) => Call.fromJson(callJson))
            .toList();
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to get active calls');
      }
    } catch (e) {
      print('CallService: Error getting active calls: $e');
      return [];
    }
  }

  /// Update call quality rating
  Future<bool> updateCallQuality({
    required String callId,
    required double rating,
    String? networkQuality,
    List<String> issues = const [],
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/call/quality/$callId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'rating': rating,
          if (networkQuality != null) 'networkQuality': networkQuality,
          'issues': issues,
        }),
      );

      print(
        'CallService: Update call quality response status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        final error = jsonDecode(response.body);
        print('CallService: Error updating call quality: ${error['message']}');
        return false;
      }
    } catch (e) {
      print('CallService: Error updating call quality: $e');
      return false;
    }
  }
}
