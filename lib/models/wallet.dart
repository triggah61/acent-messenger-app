class Wallet {
  final String id;
  final String btcAddress;
  final String ethAddress;
  final String bscAddress;
  final String label;
  final DateTime createdAt;
  final DateTime lastUsed;
  final String network;
  final int availableBalance; // in satoshis
  final double btcBalance;
  final double ethBalance;
  final double bscBalance;
  final double usdBalance;
  final double platformFeePercentage;
  final Map<String, Map<String, double>>? exchangeData;

  Wallet({
    required this.id,
    required this.btcAddress,
    required this.ethAddress,
    required this.bscAddress,
    required this.label,
    required this.createdAt,
    required this.lastUsed,
    required this.network,
    required this.availableBalance,
    required this.btcBalance,
    required this.ethBalance,
    required this.bscBalance,
    required this.usdBalance,
    required this.platformFeePercentage,
    this.exchangeData,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    // Parse exchange data if available
    Map<String, Map<String, double>>? exchangeData;
    if (json['exchangeData'] != null) {
      exchangeData = {};
      final data = json['exchangeData'] as Map<String, dynamic>;
      data.forEach((currency, rates) {
        exchangeData?[currency] = {};
        final ratesMap = rates as Map<String, dynamic>;
        ratesMap.forEach((toCurrency, rate) {
          exchangeData?[currency]?[toCurrency] = (rate as num).toDouble();
        });
      });
    }

    return Wallet(
      id: json['_id'],
      btcAddress: json['btcAddress'] ?? '',
      ethAddress: json['ethAddress'] ?? '',
      bscAddress: json['bscAddress'] ?? '',
      label: json['label'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
      lastUsed: DateTime.parse(json['lastUsed']),
      network: json['network'] ?? '',
      availableBalance: json['availableBtcBalance'] ?? 0,
      btcBalance: (json['btcBalance'] ?? 0.0).toDouble(),
      ethBalance: (json['ethBalance'] ?? 0.0).toDouble(),
      bscBalance: (json['bscBalance'] ?? 0.0).toDouble(),
      usdBalance: (json['usdBalance'] ?? 0.0).toDouble(),
      platformFeePercentage: (json['platformFeePercentage'] ?? 0.0).toDouble(),
      exchangeData: exchangeData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'btcAddress': btcAddress,
      'ethAddress': ethAddress,
      'bscAddress': bscAddress,
      'label': label,
      'createdAt': createdAt.toIso8601String(),
      'lastUsed': lastUsed.toIso8601String(),
      'network': network,
      'availableBalance': availableBalance,
      'btcBalance': btcBalance,
      'ethBalance': ethBalance,
      'bscBalance': bscBalance,
      'usdBalance': usdBalance,
      'platformFeePercentage': platformFeePercentage,
      'exchangeData': exchangeData,
    };
  }

  // Helper method to calculate platform fee for a given amount
  double calculatePlatformFee(double amount) {
    return amount * (platformFeePercentage / 100);
  }

  // Helper methods to get balance by currency
  double getBalanceForCurrency(String currency) {
    switch (currency.toUpperCase()) {
      case 'BTC':
        return btcBalance;
      case 'ETH':
        return ethBalance;
      case 'BNB':
        return bscBalance;
      default:
        return 0.0;
    }
  }

  // Helper methods to get address by currency
  String getAddressForCurrency(String currency) {
    switch (currency.toUpperCase()) {
      case 'BTC':
        return btcAddress;
      case 'ETH':
        return ethAddress;
      case 'BNB':
        // BNB on BSC uses the same address format as Ethereum
        return bscAddress.isNotEmpty ? bscAddress : ethAddress;
      default:
        return '';
    }
  }

  // Helper method to get USD equivalent for a currency
  double getUsdEquivalent(String currency) {
    final balance = getBalanceForCurrency(currency);
    if (balance == 0) return 0.0;
    
    final rate = getExchangeRate(currency, 'USD');
    return rate != null ? balance * rate : 0.0;
  }

  // Helper method to get exchange rate
  double? getExchangeRate(String fromCurrency, String toCurrency) {
    if (exchangeData == null) return null;
    return exchangeData?[fromCurrency.toUpperCase()]?[toCurrency.toUpperCase()];
  }
}

class Transaction {
  final String id;
  final String? txHash;
  final String type; // 'withdrawal', 'deposit'
  final String currency; // 'BTC', 'ETH', 'BNB'
  final double amount;
  final double fee;
  final double adminFee;
  final double netAmount;
  final String? fromAddress;
  final String? toAddress;
  final String status; // 'processing', 'confirmed', 'failed'
  final int confirmations;
  final String? description;
  final DateTime submittedAt;
  final DateTime? confirmedAt;
  final DateTime createdAt;

  Transaction({
    required this.id,
    this.txHash,
    required this.type,
    required this.currency,
    required this.amount,
    required this.fee,
    required this.adminFee,
    required this.netAmount,
    this.fromAddress,
    this.toAddress,
    required this.status,
    required this.confirmations,
    this.description,
    required this.submittedAt,
    this.confirmedAt,
    required this.createdAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['_id'] ?? json['id'],
      txHash: json['txHash'],
      type: json['type'],
      currency: json['currency'] ?? 'BTC',
      amount: (json['amount'] ?? 0.0).toDouble(),
      fee: (json['fee'] ?? 0.0).toDouble(),
      adminFee: (json['adminFee'] ?? 0.0).toDouble(),
      netAmount: (json['netAmount'] ?? 0.0).toDouble(),
      fromAddress: json['fromAddress'],
      toAddress: json['toAddress'],
      status: json['status'],
      confirmations: json['confirmations'] ?? 0,
      description: json['description'],
      submittedAt: DateTime.parse(json['submittedAt']),
      confirmedAt: json['confirmedAt'] != null ? DateTime.parse(json['confirmedAt']) : null,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'txHash': txHash,
      'type': type,
      'currency': currency,
      'amount': amount,
      'fee': fee,
      'adminFee': adminFee,
      'netAmount': netAmount,
      'fromAddress': fromAddress,
      'toAddress': toAddress,
      'status': status,
      'confirmations': confirmations,
      'description': description,
      'submittedAt': submittedAt.toIso8601String(),
      'confirmedAt': confirmedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Helper getter for backward compatibility
  double get btcAmount => amount.abs();
  
  // Helper getter to determine if it's a deposit or withdrawal
  bool get isDeposit => type.toLowerCase() == 'deposit';
  bool get isWithdrawal => type.toLowerCase() == 'withdrawal';
  
  // Helper getter to get direction for backward compatibility
  String get direction => isDeposit ? 'received' : 'sent';
}

class TransactionPagination {
  final int page;
  final int limit;
  final int totalPages;
  final int totalDocs;
  final bool hasNextPage;
  final bool hasPrevPage;

  TransactionPagination({
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.totalDocs,
    required this.hasNextPage,
    required this.hasPrevPage,
  });

  factory TransactionPagination.fromJson(Map<String, dynamic> json) {
    return TransactionPagination(
      page: json['currentPage'] ?? json['page'] ?? 1,
      limit: json['limit'] ?? 10,
      totalPages: json['totalPages'] ?? 1,
      totalDocs: json['totalTransactions'] ?? json['totalDocs'] ?? 0,
      hasNextPage: json['hasNext'] ?? json['hasNextPage'] ?? false,
      hasPrevPage: json['hasPrev'] ?? json['hasPrevPage'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'page': page,
      'limit': limit,
      'totalPages': totalPages,
      'totalDocs': totalDocs,
      'hasNextPage': hasNextPage,
      'hasPrevPage': hasPrevPage,
    };
  }
}

class TransactionHistoryResponse {
  final List<Transaction> transactions;
  final TransactionPagination pagination;

  TransactionHistoryResponse({
    required this.transactions,
    required this.pagination,
  });

  factory TransactionHistoryResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return TransactionHistoryResponse(
      transactions: (data['transactions'] as List)
          .map((tx) => Transaction.fromJson(tx))
          .toList(),
      pagination: TransactionPagination.fromJson(data['pagination']),
    );
  }
}

enum NetworkFeeType {
  low,
  medium,
  high,
}

class FeeAmount {
  final double amount;

  FeeAmount({
    required this.amount,
  });

  factory FeeAmount.fromJson(Map<String, dynamic> json) {
    return FeeAmount(
      amount: (json as double? ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
    };
  }

  // Backward compatibility getters
  double get btc => amount;
  int get satoshis => (amount * 100000000).round(); // Convert to satoshis for compatibility
}

class NetworkFee {
  final NetworkFeeType type;
  final FeeAmount networkFee;
  final FeeAmount platformFee;
  final String estimatedTime;

  NetworkFee({
    required this.type,
    required this.networkFee,
    required this.platformFee,
    required this.estimatedTime,
  });

  factory NetworkFee.fromJson(NetworkFeeType type, Map<String, dynamic> json, String estimatedTime) {
    return NetworkFee(
      type: type,
      networkFee: FeeAmount(amount: (json['network'] ?? 0.0).toDouble()),
      platformFee: FeeAmount(amount: (json['platform'] ?? 0.0).toDouble()),
      estimatedTime: estimatedTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString().split('.').last,
      'network': networkFee.toJson(),
      'platform': platformFee.toJson(),
      'estimatedTime': estimatedTime,
    };
  }

  // Helper getters
  double get totalBtcFee => networkFee.btc + platformFee.btc;
  
  // Legacy compatibility
  double get fee => totalBtcFee;
  String get description => _getDescription();
  int get estimatedTimeMinutes => _parseEstimatedTime();

  String _getDescription() {
    switch (type) {
      case NetworkFeeType.low:
        return 'Low priority - $estimatedTime';
      case NetworkFeeType.medium:
        return 'Standard priority - $estimatedTime';
      case NetworkFeeType.high:
        return 'High priority - $estimatedTime';
    }
  }

  int _parseEstimatedTime() {
    // Extract average time from string like "60-120 minutes"
    final parts = estimatedTime.split('-');
    if (parts.length >= 2) {
      final minTime = int.tryParse(parts[0]) ?? 30;
      final maxTime = int.tryParse(parts[1].split(' ')[0]) ?? 60;
      return ((minTime + maxTime) / 2).round();
    }
    return 30; // Default fallback
  }
}

class FeeEstimationResponse {
  final Map<NetworkFeeType, NetworkFee> fees;

  FeeEstimationResponse({required this.fees});

  factory FeeEstimationResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final feesData = data['fees'] as Map<String, dynamic>;
    final estimatedTimes = data['estimatedConfirmationTime'] as Map<String, dynamic>;

    final fees = <NetworkFeeType, NetworkFee>{};
    
    fees[NetworkFeeType.low] = NetworkFee.fromJson(
      NetworkFeeType.low,
      feesData['low'],
      estimatedTimes['low'] ?? '60-120 minutes',
    );
    
    fees[NetworkFeeType.medium] = NetworkFee.fromJson(
      NetworkFeeType.medium,
      feesData['medium'],
      estimatedTimes['medium'] ?? '10-30 minutes',
    );
    
    fees[NetworkFeeType.high] = NetworkFee.fromJson(
      NetworkFeeType.high,
      feesData['high'],
      estimatedTimes['high'] ?? '5-15 minutes',
    );

    return FeeEstimationResponse(fees: fees);
  }

  List<NetworkFee> get feeList => fees.values.toList();
  
  NetworkFee? getFee(NetworkFeeType type) => fees[type];
} 