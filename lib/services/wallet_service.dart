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
    String? currency,
  }) async {
    try {
      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token');

      String url = '${Config.baseApiUrl}/user/wallet/getTransactionHistory?limit=$limit&page=$page';
      if (currency != null && currency.isNotEmpty) {
        url += '&currency=${currency.toUpperCase()}';
      }

      final response = await http.get(
        Uri.parse(url),
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
      if (token == null) throw Exception('Authentication required. Please log in again.');

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
          'description': description ?? '',
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        if (responseData['success'] == true) {
          return true;
        } else {
          // API returned success: false
          String errorMessage = responseData['message'] ?? 'Transaction failed';
          throw Exception(_getCustomErrorMessage(errorMessage));
        }
      } else {
       final errorData = json.decode(response.body);
        print("errorData: $errorData");
        String errorMessage = errorData['message'] ?? 'Transaction failed';
        throw Exception(_getCustomErrorMessage(errorMessage));
      }
    } catch (e) {
      print('Error creating withdrawal: $e');
      
      // If it's already a formatted exception, re-throw it
      if (e.toString().startsWith('Exception: ')) {
        rethrow;
      }
      
      // Handle network/connection errors
      if (e.toString().contains('SocketException') || 
          e.toString().contains('TimeoutException') ||
          e.toString().contains('Connection')) {
        throw Exception('Network connection failed. Please check your internet connection.');
      }
      
      // Generic error fallback
      throw Exception('Transaction failed. Please try agains.');
    }
  }

  // Helper method to provide custom error messages
  String _getCustomErrorMessage(String apiMessage) {
    // Convert API error messages to user-friendly messages
    final lowerMessage = apiMessage.toLowerCase();
    
    if (lowerMessage.contains('insufficient') && lowerMessage.contains('balance')) {
      return 'Insufficient balance. Please check your available funds.';
    } else if (lowerMessage.contains('invalid') && lowerMessage.contains('address')) {
      return 'Invalid Bitcoin address. Please check the destination address.';
    } else if (lowerMessage.contains('minimum') && lowerMessage.contains('amount')) {
      return 'Amount is below minimum withdrawal limit.';
    } else if (lowerMessage.contains('maximum') && lowerMessage.contains('amount')) {
      return 'Amount exceeds maximum withdrawal limit.';
    } else if (lowerMessage.contains('fee') && lowerMessage.contains('high')) {
      return 'Network fees are currently high. Please try again later.';
    } else if (lowerMessage.contains('pending') || lowerMessage.contains('processing')) {
      return 'You have a pending transaction. Please wait for it to complete.';
    } else if (lowerMessage.contains('limit') && lowerMessage.contains('exceeded')) {
      return 'Daily withdrawal limit exceeded. Please try again tomorrow.';
    } else if (lowerMessage.contains('maintenance')) {
      return 'Wallet is under maintenance. Please try again later.';
    } else if (lowerMessage.contains('blocked') || lowerMessage.contains('suspended')) {
      return 'Your account has restrictions. Please contact support.';
    } else if (lowerMessage.contains('rate') && lowerMessage.contains('limit')) {
      return 'Too many transactions. Please wait a moment and try again.';
    } else {
      // Return the original message if no custom mapping found
      return apiMessage;
    }
  }

  // Generate QR code data for deposit address
  String generateQRCodeData(String address, {double? amount, String? currency}) {
    final currencyCode = currency?.toUpperCase() ?? 'BTC';
    
    switch (currencyCode) {
      case 'BTC':
        if (amount != null && amount > 0) {
          return 'bitcoin:$address?amount=$amount';
        }
        return 'bitcoin:$address';
      case 'ETH':
        if (amount != null && amount > 0) {
          return 'ethereum:$address?value=${(amount * 1e18).toInt()}'; // Convert to wei
        }
        return 'ethereum:$address';
      case 'BNB':
        // BNB on BSC uses Ethereum format
        if (amount != null && amount > 0) {
          return 'ethereum:$address?value=${(amount * 1e18).toInt()}'; // Convert to wei
        }
        return 'ethereum:$address';
      default:
        return address; // Fallback to just the address
    }
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