import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wallet.dart';
import '../constants/config.dart';
import 'auth_service.dart';

class WalletService {
  final AuthService _authService;

  WalletService(this._authService);

  // Sample transactions for demonstration (until transaction API is provided)
  static final List<Transaction> _sampleTransactions = [
    Transaction(
      id: 'tx_001',
      walletId: 'wallet_001',
      type: 'deposit',
      amount: 0.001,
      fee: 0.00001,
      fromAddress: '3FRN9PWK47bHK3fy43nGjzTjNMXzqTWWcH',
      description: 'Deposit from external wallet',
      status: 'confirmed',
      txHash: '3e4c5a2b8d7f1a9c6e8b2f4d1a7c9e5b3f8d2a6c4e1b7f9a5c3d8e2b4f6a1c9d',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    Transaction(
      id: 'tx_002',
      walletId: 'wallet_001',
      type: 'withdraw',
      amount: 0.0005,
      fee: 0.00002,
      toAddress: '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2',
      description: 'Payment to merchant',
      status: 'confirmed',
      txHash: '7a2c4e6b8f1d3a5c9e2b4f6d8a1c3e5b7f9d2a4c6e8b1f3d5a7c9e2b4f6d8a1c',
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      updatedAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
    Transaction(
      id: 'tx_003',
      walletId: 'wallet_001',
      type: 'deposit',
      amount: 0.00075,
      fee: 0.00001,
      fromAddress: '1QHsF1UE7Vxh6nAr3tWe2c4Bg7C1e2K2Jk',
      description: 'Deposit from friend',
      status: 'pending',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];

  // Sample network fees
  static final List<NetworkFee> _sampleNetworkFees = [
    NetworkFee(
      type: NetworkFeeType.slow,
      fee: 0.00001,
      description: 'Low priority - 60-120 minutes',
      estimatedTime: 90,
    ),
    NetworkFee(
      type: NetworkFeeType.standard,
      fee: 0.00003,
      description: 'Standard priority - 15-30 minutes',
      estimatedTime: 20,
    ),
    NetworkFee(
      type: NetworkFeeType.fast,
      fee: 0.00005,
      description: 'High priority - 5-15 minutes',
      estimatedTime: 10,
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

  // Get transaction history (using sample data until API is provided)
  Future<List<Transaction>> getTransactions(String walletId) async {
    try {
      // TODO: Replace with real API call when transaction endpoint is provided
      /*
      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token');

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/wallet/transactions'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['transactions'] as List)
            .map((tx) => Transaction.fromJson(tx))
            .toList();
      } else {
        throw Exception('Failed to fetch transactions');
      }
      */
      
      await Future.delayed(const Duration(milliseconds: 300)); // Simulate API delay
      return _sampleTransactions;
    } catch (e) {
      throw Exception('Failed to fetch transactions: $e');
    }
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
      // TODO: Replace with real API call when withdrawal endpoint is provided
      /*
      final token = await _authService.getToken();
      if (token == null) throw Exception('No authentication token');

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/wallet/withdraw'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'amount': amount,
          'toAddress': toAddress,
          'feeType': feeType.toString().split('.').last,
          'description': description,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Failed to create withdrawal');
      }
      */
      
      await Future.delayed(const Duration(seconds: 1)); // Simulate API delay
      
      // Validate inputs
      if (amount <= 0) throw Exception('Amount must be greater than 0');
      if (toAddress.isEmpty) throw Exception('Destination address is required');
      
      return true;
    } catch (e) {
      throw Exception('Failed to create withdrawal: $e');
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
} 