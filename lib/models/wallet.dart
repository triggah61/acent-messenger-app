class Wallet {
  final String id;
  final String address;
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
    required this.address,
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
      address: json['address'] ?? '',
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
      'address': address,
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
  slow,
  standard,
  fast,
}

class NetworkFee {
  final NetworkFeeType type;
  final double fee;
  final String description;
  final int estimatedTime; // in minutes

  NetworkFee({
    required this.type,
    required this.fee,
    required this.description,
    required this.estimatedTime,
  });

  factory NetworkFee.fromJson(Map<String, dynamic> json) {
    return NetworkFee(
      type: NetworkFeeType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => NetworkFeeType.standard,
      ),
      fee: (json['fee'] ?? 0.0).toDouble(),
      description: json['description'] ?? '',
      estimatedTime: json['estimatedTime'] ?? 30,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString().split('.').last,
      'fee': fee,
      'description': description,
      'estimatedTime': estimatedTime,
    };
  }
} 