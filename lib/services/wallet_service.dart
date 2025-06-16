import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wallet.dart';
import '../constants/config.dart';
import 'auth_service.dart';

class WalletService {
  final AuthService _authService;

  WalletService(this._authService);

  // Sample network fees (fallback when API is unavailable)
  static final List<NetworkFee> _sampleNetworkFees = [
    NetworkFee(
      type: NetworkFeeType.low,
      networkFee: FeeAmount(satoshis: 1130, btc: 0.0000113),
      platformFee: FeeAmount(satoshis: 1000, btc: 0.00001),
      estimatedTime: '60-120 minutes',
    ),
    NetworkFee(
      type: NetworkFeeType.medium,
      networkFee: FeeAmount(satoshis: 3390, btc: 0.0000339),
      platformFee: FeeAmount(satoshis: 1000, btc: 0.00001),
      estimatedTime: '10-30 minutes',
    ),
    NetworkFee(
      type: NetworkFeeType.high,
      networkFee: FeeAmount(satoshis: 6780, btc: 0.0000678),
      platformFee: FeeAmount(satoshis: 1000, btc: 0.00001),
      estimatedTime: '5-15 minutes',
    ),
  ];

  // Get wallet information from API
  Future<Wallet> getWallet() async {
    try {
      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token');

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/wallet/walletInformation'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        if (responseData['success'] == true && responseData['data'] != null) {
          return Wallet.fromJson(responseData['data']);
        } else {
          throw Exception(responseData['message'] ?? 'Failed to fetch wallet');
        }
      } else {
        throw Exception('Failed to fetch wallet: ${response.body}');
      }
    } catch (e) {
      print('Error fetching wallet: $e');
      throw Exception('Failed to fetch wallet: $e');
    }
  }

  // Get transaction history with pagination
  Future<TransactionHistoryResponse> getTransactions({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token');

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/wallet/getTransactionHistory?limit=$limit&page=$page'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        if (responseData['success'] == true && responseData['data'] != null) {
          return TransactionHistoryResponse.fromJson(responseData);
        } else {
          throw Exception(responseData['message'] ?? 'Failed to fetch transactions');
        }
      } else {
        throw Exception('Failed to fetch transactions: ${response.body}');
      }
    } catch (e) {
      print('Error fetching transactions: $e');
      throw Exception('Failed to fetch transactions: $e');
    }
  }

  // Legacy method for backward compatibility - remove when all references are updated
  @deprecated
  Future<List<Transaction>> getTransactionsList(String walletId) async {
    final response = await getTransactions(page: 1, limit: 50);
    return response.transactions;
  }

  // Get network fees (using sample data until API is provided)
  Future<List<NetworkFee>> getNetworkFees() async {
    try {
      // TODO: Replace with real API call when network fees endpoint is provided
      /*
      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/wallet/network-fees'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['fees'] as List)
            .map((fee) => NetworkFee.fromJson(fee))
            .toList();
      } else {
        throw Exception('Failed to fetch network fees');
      }
      */
      
      await Future.delayed(const Duration(milliseconds: 200)); // Simulate API delay
      return _sampleNetworkFees;
    } catch (e) {
      throw Exception('Failed to fetch network fees: $e');
    }
  }

  // Create withdrawal transaction
  Future<bool> createWithdrawal({
    required double amount,
    required String toAddress,
    required NetworkFeeType feeType,
    String? description,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token');

      // Convert NetworkFeeType to API string
      String priority;
      switch (feeType) {
        case NetworkFeeType.low:
          priority = 'low';
          break;
        case NetworkFeeType.medium:
          priority = 'medium';
          break;
        case NetworkFeeType.high:
          priority = 'high';
          break;
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/wallet/sendTransaction'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'toAddress': toAddress,
          'amount': amount,
          'priority': priority,
          'descripton': description ?? '', // Note: API uses 'descripton' (typo in API)
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return responseData['success'] == true;
      } else {
        final errorData = json.decode(response.body);

        throw Exception(errorData['message'] ?? 'Failed to create withdrawals: ${response.body}');
      }
    } catch (e) {
      print('Error creating withdrawal: $e');
      throw Exception('Failed to create withdrawalh: $e');
    }
  }

  // Generate QR code data for deposit address
  String generateQRCodeData(String address, {double? amount}) {
    if (amount != null && amount > 0) {
      return 'bitcoin:$address?amount=$amount';
    }
    return 'bitcoin:$address';
  }

  // Calculate total withdrawal cost (amount + platform fee + network fee)
  Map<String, double> calculateWithdrawalCost({
    required double amount,
    required double platformFeePercentage,
    required double networkFee,
  }) {
    final platformFee = amount * (platformFeePercentage / 100);
    final totalFees = platformFee + networkFee;
    final totalCost = amount + totalFees;

    return {
      'amount': amount,
      'platformFee': platformFee,
      'networkFee': networkFee,
      'totalFees': totalFees,
      'totalCost': totalCost,
    };
  }

  // Estimate transaction fees based on amount
  Future<FeeEstimationResponse> estimateTransactionFee(double amount) async {
    try {
      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token');

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/wallet/estimateTransactionFee'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'amount': amount}),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        if (responseData['success'] == true && responseData['data'] != null) {
          return FeeEstimationResponse.fromJson(responseData);
        } else {
          throw Exception(responseData['message'] ?? 'Failed to estimate fees');
        }
      } else {
        throw Exception('Failed to estimate fees: ${response.body}');
      }
    } catch (e) {
      print('Error estimating fees: $e');
      throw Exception('Failed to estimate fees: $e');
    }
  }
} 