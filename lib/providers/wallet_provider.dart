import 'package:flutter/material.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';

class WalletProvider with ChangeNotifier {
  final WalletService _walletService;
  
  Wallet? _wallet;
  List<Transaction> _transactions = [];
  List<NetworkFee> _networkFees = [];
  
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
  Future<void> fetchTransactions({bool refresh = false}) async {
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
  Future<void> loadMoreTransactions() async {
    if (_isLoadingMoreTransactions || !canLoadMoreTransactions) return;

    _isLoadingMoreTransactions = true;
    notifyListeners();

    try {
      final nextPage = (_transactionPagination?.page ?? 0) + 1;
      final response = await _walletService.getTransactions(
        page: nextPage,
        limit: 10,
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

  // Fetch network fees
  Future<void> fetchNetworkFees() async {
    try {
      _networkFees = await _walletService.getNetworkFees();
    } catch (e) {
      print('Error fetching network fees: $e');
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

  // Create withdrawal
  Future<bool> createWithdrawal({
    required double amount,
    required String toAddress,
    required NetworkFeeType feeType,
    String? description,
  }) async {
    try {
      final success = await _walletService.createWithdrawal(
        amount: amount,
        toAddress: toAddress,
        feeType: feeType,
        description: description,
      );

      if (success) {
        // Refresh wallet data after successful withdrawal
        await refreshWalletData();
      }

      return success;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
} 