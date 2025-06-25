import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';

class WalletProvider with ChangeNotifier {
  final WalletService _walletService;
  
  Wallet? _wallet;
  List<Transaction> _transactions = [];
  List<NetworkFee> _networkFees = [];
  
  // Fee estimation state
  FeeEstimationResponse? _feeEstimation;
  bool _isLoadingFees = false;
  String? _feeError;
  double? _lastFeeAmount; // Track the last amount for which fees were estimated
  
  // Transaction pagination state
  TransactionPagination? _transactionPagination;
  bool _isLoadingTransactions = false;
  bool _isLoadingMoreTransactions = false;
  bool _hasTransactionError = false;
  String? _transactionError;

  bool _isLoading = false;
  String? _error;

  WalletProvider(this._walletService);

  // Getters
  Wallet? get wallet => _wallet;
  List<Transaction> get transactions => _transactions;
  List<NetworkFee> get networkFees => _networkFees;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  // Fee estimation getters
  FeeEstimationResponse? get feeEstimation => _feeEstimation;
  bool get isLoadingFees => _isLoadingFees;
  String? get feeError => _feeError;
  double? get lastFeeAmount => _lastFeeAmount;
  List<NetworkFee> get estimatedFees => _feeEstimation?.feeList ?? _networkFees;
  
  // Transaction pagination getters
  TransactionPagination? get transactionPagination => _transactionPagination;
  bool get isLoadingTransactions => _isLoadingTransactions;
  bool get isLoadingMoreTransactions => _isLoadingMoreTransactions;
  bool get hasTransactionError => _hasTransactionError;
  String? get transactionError => _transactionError;
  bool get canLoadMoreTransactions => 
      _transactionPagination?.hasNextPage ?? false;

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Fetch wallet data
  Future<void> fetchWalletData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _wallet = await _walletService.getWallet();
      _error = null;
    } catch (e) {
      _error = e.toString();
      print('Error fetching wallet: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch transactions with pagination
  Future<void> fetchTransactions({bool refresh = false, String? currency}) async {
    if (refresh) {
      _transactions.clear();
      _transactionPagination = null;
      _hasTransactionError = false;
      _transactionError = null;
    }

    _isLoadingTransactions = refresh;
    notifyListeners();

    try {
      final response = await _walletService.getTransactions(
        page: 1,
        limit: 10,
        currency: currency,
      );

      _transactions = response.transactions;
      _transactionPagination = response.pagination;
      _hasTransactionError = false;
      _transactionError = null;
    } catch (e) {
      _hasTransactionError = true;
      _transactionError = e.toString();
      print('Error fetching transactions: $e');
    } finally {
      _isLoadingTransactions = false;
      notifyListeners();
    }
  }

  // Load more transactions (for pagination)
  Future<void> loadMoreTransactions({String? currency}) async {
    if (_isLoadingMoreTransactions || !canLoadMoreTransactions) return;

    _isLoadingMoreTransactions = true;
    notifyListeners();

    try {
      final nextPage = (_transactionPagination?.page ?? 0) + 1;
      final response = await _walletService.getTransactions(
        page: nextPage,
        limit: 10,
        currency: currency,
      );

      _transactions.addAll(response.transactions);
      _transactionPagination = response.pagination;
      _hasTransactionError = false;
      _transactionError = null;
    } catch (e) {
      _hasTransactionError = true;
      _transactionError = e.toString();
      print('Error loading more transactions: $e');
    } finally {
      _isLoadingMoreTransactions = false;
      notifyListeners();
    }
  }

  // Fetch network fees (fallback)
  Future<void> fetchNetworkFees() async {
    try {
      _networkFees = await _walletService.getNetworkFees();
    } catch (e) {
      print('Error fetching network fees: $e');
    }
  }

  // Estimate fees for a specific amount
  Future<void> estimateFeesForAmount(double amount, {String? currency}) async {
    // Don't fetch if amount is 0 or same as last request
    if (amount <= 0 || amount == _lastFeeAmount) return;

    _isLoadingFees = true;
    _feeError = null;
    _lastFeeAmount = amount;
    notifyListeners();

    try {
      _feeEstimation = await _walletService.estimateTransactionFee(
        amount, 
        currency: currency ?? 'BTC',
      );
      _feeError = null;
    } catch (e) {
      _feeError = e.toString();
      _feeEstimation = null;
      print('Error estimating fees: $e');
    } finally {
      _isLoadingFees = false;
      notifyListeners();
    }
  }

  // Clear fee estimation (when amount is cleared)
  void clearFeeEstimation() {
    _feeEstimation = null;
    _feeError = null;
    _lastFeeAmount = null;
    _isLoadingFees = false;
    notifyListeners();
  }

  // Get specific fee by type from current estimation
  NetworkFee? getFeeByType(NetworkFeeType type) {
    if (_feeEstimation != null) {
      return _feeEstimation!.getFee(type);
    }
    
    // Fallback to default fees
    try {
      return _networkFees.firstWhere((fee) => fee.type == type);
    } catch (e) {
      return null;
    }
  }

  // Refresh all wallet data
  Future<void> refreshWalletData() async {
    await Future.wait([
      fetchWalletData(),
      fetchTransactions(refresh: true),
      fetchNetworkFees(),
    ]);
  }

  // Clear all wallet data (for logout)
  void clearAllData() {
    _wallet = null;
    _transactions.clear();
    _networkFees.clear();
    _feeEstimation = null;
    _transactionPagination = null;
    _isLoading = false;
    _isLoadingFees = false;
    _isLoadingTransactions = false;
    _isLoadingMoreTransactions = false;
    _hasTransactionError = false;
    _error = null;
    _feeError = null;
    _transactionError = null;
    _lastFeeAmount = null;
    notifyListeners();
  }

  // Create withdrawal
  Future<bool> createWithdrawal({
    required double amount,
    required String toAddress,
    required NetworkFeeType feeType,
    String? description,
  }) async {
    _error = null; // Clear previous errors
    notifyListeners();
    
    try {
      final success = await _walletService.createWithdrawal(
        amount: amount,
        toAddress: toAddress,
        feeType: feeType,
        description: description,
      );

      if (success) {
        // Clear any previous errors on success
        _error = null;
        // Refresh wallet data after successful withdrawal
        await refreshWalletData();
        return true;
      } else {
        _error = 'Transaction failed. Please try again.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      // Extract clean error message
      String errorMessage = e.toString();
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11); // Remove 'Exception: ' prefix
      }
      
      _error = errorMessage;
      notifyListeners();
      return false;
    }
  }
} 