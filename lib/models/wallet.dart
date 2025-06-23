class Wallet {
  final String id;
  final String btcAddress;
  final String ethAddress;
  final String label;
  final DateTime createdAt;
  final DateTime lastUsed;
  final String network;
  final int availableBalance; // in satoshis
  final double btcBalance;
  final double usdBalance;
  final double platformFeePercentage;

  Wallet({
    required this.id,
    required this.btcAddress,
    required this.ethAddress,
    required this.label,
    required this.createdAt,
    required this.lastUsed,
    required this.network,
    required this.availableBalance,
    required this.btcBalance,
    required this.usdBalance,
    required this.platformFeePercentage,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['_id'],
      btcAddress: json['btcAddress'] ?? '',
      ethAddress: json['ethAddress'] ?? '',
      label: json['label'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
      lastUsed: DateTime.parse(json['lastUsed']),
      network: json['network'] ?? '',
      availableBalance: json['availableBalance'] ?? 0,
      btcBalance: (json['btcBalance'] ?? 0.0).toDouble(),
      usdBalance: (json['usdBalance'] ?? 0.0).toDouble(),
      platformFeePercentage: (json['platformFeePercentage'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'btcAddress': btcAddress,
      'ethAddress': ethAddress,
      'label': label,
      'createdAt': createdAt.toIso8601String(),
      'lastUsed': lastUsed.toIso8601String(),
      'network': network,
      'availableBalance': availableBalance,
      'btcBalance': btcBalance,
      'usdBalance': usdBalance,
      'platformFeePercentage': platformFeePercentage,
    };
  }

  // Helper method to calculate platform fee for a given amount
  double calculatePlatformFee(double amount) {
    return amount * (platformFeePercentage / 100);
  }
}

class Transaction {
  final String id;
  final String? txHash;
  final String type; // 'withdrawal', 'deposit'
  final String direction; // 'sent', 'received'
  final TransactionAmount amount;
  final TransactionAmount fee;
  final TransactionAmount adminFee;
  final TransactionAmount netAmount;
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
    required this.direction,
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
      id: json['id'],
      txHash: json['txHash'],
      type: json['type'],
      direction: json['direction'],
      amount: TransactionAmount.fromJson(json['amount']),
      fee: TransactionAmount.fromJson(json['fee']),
      adminFee: TransactionAmount.fromJson(json['adminFee']),
      netAmount: TransactionAmount.fromJson(json['netAmount']),
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
      'direction': direction,
      'amount': amount.toJson(),
      'fee': fee.toJson(),
      'adminFee': adminFee.toJson(),
      'netAmount': netAmount.toJson(),
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
  double get btcAmount => amount.btc.abs();
  
  // Helper getter to determine if it's a deposit or withdrawal
  bool get isDeposit => direction == 'received';
  bool get isWithdrawal => direction == 'sent';
}

class TransactionAmount {
  final int satoshis;
  final double btc;

  TransactionAmount({
    required this.satoshis,
    required this.btc,
  });

  factory TransactionAmount.fromJson(Map<String, dynamic> json) {
    return TransactionAmount(
      satoshis: json['satoshis'] ?? 0,
      btc: (json['btc'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'satoshis': satoshis,
      'btc': btc,
    };
  }
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
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 10,
      totalPages: json['totalPages'] ?? 1,
      totalDocs: json['totalDocs'] ?? 0,
      hasNextPage: json['hasNextPage'] ?? false,
      hasPrevPage: json['hasPrevPage'] ?? false,
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
  final int satoshis;
  final double btc;

  FeeAmount({
    required this.satoshis,
    required this.btc,
  });

  factory FeeAmount.fromJson(Map<String, dynamic> json) {
    return FeeAmount(
      satoshis: json['satoshis'] ?? 0,
      btc: (json['btc'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'satoshis': satoshis,
      'btc': btc,
    };
  }
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
      networkFee: FeeAmount.fromJson(json['network']),
      platformFee: FeeAmount.fromJson(json['platform']),
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
  int get totalSatoshis => networkFee.satoshis + platformFee.satoshis;
  
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