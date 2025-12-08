import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/config.dart';
import '../services/auth_service.dart';
import '../models/subscription_plan.dart';

/// Service for handling subscription-related API operations
class SubscriptionService {
  final AuthService _authService;

  SubscriptionService(this._authService);

  /// Get all active subscription plans
  Future<List<SubscriptionPlan>> getSubscriptionPlans() async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/subscriptions/plans'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('SubscriptionService: Get plans response status: ${response.statusCode}');
      print('SubscriptionService: Get plans response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('SubscriptionService: Parsed response data type: ${data.runtimeType}');
        print('SubscriptionService: Data keys: ${data.keys}');
        
        if (data['status'] == 'success' && data['data'] != null) {
          final plansData = data['data'];
          print('SubscriptionService: Plans data type: ${plansData.runtimeType}');
          print('SubscriptionService: Plans count: ${plansData is List ? plansData.length : 'not a list'}');
          
          // Ensure plansData is a List
          if (plansData is! List) {
            print('SubscriptionService: Plans data is not a list: $plansData');
            return [];
          }
          
          final List<dynamic> plansJson = plansData;
          // Filter out any plans that fail to parse and log errors
          final List<SubscriptionPlan> plans = [];
          for (var i = 0; i < plansJson.length; i++) {
            try {
              final planJson = plansJson[i];
              print('SubscriptionService: Parsing plan $i: ${planJson['_id'] ?? planJson['id']}');
              final plan = SubscriptionPlan.fromJson(planJson);
              // Only add plans with valid IDs
              if (plan.id.isNotEmpty) {
                plans.add(plan);
                print('SubscriptionService: Successfully parsed plan: ${plan.name} (${plan.id})');
              } else {
                print('SubscriptionService: Skipping plan with empty ID: $planJson');
              }
            } catch (e, stackTrace) {
              print('SubscriptionService: Error parsing plan $i: $e');
              print('SubscriptionService: Stack trace: $stackTrace');
              print('SubscriptionService: Plan data: ${plansJson[i]}');
              // Continue with other plans instead of failing completely
            }
          }
          print('SubscriptionService: Successfully parsed ${plans.length} out of ${plansJson.length} plans');
          return plans;
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch subscription plans');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch subscription plans');
      }
    } catch (e) {
      print('SubscriptionService: Error fetching plans: $e');
      rethrow;
    }
  }

  /// Subscribe to a subscription plan
  Future<Map<String, dynamic>> subscribeToPlan({
    required String planId,
    required String intervalType, // 'month' or 'year'
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/subscriptions/subscribe'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'planId': planId,
          'intervalType': intervalType,
        }),
      );

      print('SubscriptionService: Subscribe response status: ${response.statusCode}');
      print('SubscriptionService: Subscribe response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return {
            'success': true,
            'data': data['data'],
            'message': data['message'] ?? 'Successfully subscribed',
          };
        } else {
          throw Exception(data['message'] ?? 'Failed to subscribe');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to subscribe to plan');
      }
    } catch (e) {
      print('SubscriptionService: Error subscribing to plan: $e');
      rethrow;
    }
  }

  /// Verify Google Play subscription purchase
  Future<Map<String, dynamic>> verifyGooglePlaySubscription({
    required String purchaseToken,
    required String subscriptionId,
    required String planId,
    required String intervalType, // 'month' or 'year'
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/subscriptions/verify-google-play'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'purchaseToken': purchaseToken,
          'subscriptionId': subscriptionId,
          'planId': planId,
          'intervalType': intervalType,
        }),
      );

      print('SubscriptionService: Verify Google Play response status: ${response.statusCode}');
      print('SubscriptionService: Verify Google Play response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return {
            'success': true,
            'data': data['data'],
            'message': data['message'] ?? 'Successfully subscribed',
          };
        } else {
          throw Exception(data['message'] ?? 'Failed to verify subscription');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to verify subscription purchase');
      }
    } catch (e) {
      print('SubscriptionService: Error verifying subscription: $e');
      rethrow;
    }
  }

  /// Get user's subscription history
  Future<List<Map<String, dynamic>>> getSubscriptionHistory({String? status}) async {
    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      String url = '${Config.baseApiUrl}/user/subscriptions/history';
      if (status != null) {
        url += '?status=$status';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('SubscriptionService: Get history response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        } else {
          throw Exception(data['message'] ?? 'Failed to fetch subscription history');
        }
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch subscription history');
      }
    } catch (e) {
      print('SubscriptionService: Error fetching history: $e');
      rethrow;
    }
  }
}

