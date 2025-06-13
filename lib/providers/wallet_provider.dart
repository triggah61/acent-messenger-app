import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';

class WalletProvider with ChangeNotifier {
  final WalletService _walletService;
  
  Wallet? _wallet;
  List<Transaction> _transactions = [];
  List<NetworkFee> _networkFees = [];
  bool _isLoading = false;
  String? _error;

  WalletProvider(this._walletService);

  // Getters
  Wallet? get wallet => _wallet;
  List<Transaction> get transactions => _transactions;
  List<NetworkFee> get networkFees => _networkFees;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Fetch wallet data
  Future<void> fetchWallet() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _wallet = await _walletService.getWallet();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch transactions
  Future<void> fetchTransactions() async {
    try {
      if (_wallet == null) return;
      
      _transactions = await _walletService.getTransactions(_wallet!.id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // Fetch network fees
  Future<void> fetchNetworkFees() async {
    try {
      _networkFees = await _walletService.getNetworkFees();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
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
      _isLoading = true;
      _error = null;
      notifyListeners();

      final success = await _walletService.createWithdrawal(
        amount: amount,
        toAddress: toAddress,
        feeType: feeType,
        description: description,
      );

      if (success) {
        // Refresh wallet and transactions
        await fetchWallet();
        await fetchTransactions();
      }

      return success;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Refresh all wallet data
  Future<void> refreshWalletData() async {
    await Future.wait([
      fetchWallet(),
      fetchTransactions(),
      fetchNetworkFees(),
    ]);
  }
} 