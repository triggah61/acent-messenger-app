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
  final String walletId;
  final String type; // 'deposit' or 'withdraw'
  final double amount;
  final double fee;
  final String? toAddress;
  final String? fromAddress;
  final String? description;
  final String status; // 'pending', 'confirmed', 'failed'
  final String? txHash;
  final DateTime createdAt;
  final DateTime updatedAt;

  Transaction({
    required this.id,
    required this.walletId,
    required this.type,
    required this.amount,
    required this.fee,
    this.toAddress,
    this.fromAddress,
    this.description,
    required this.status,
    this.txHash,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['_id'],
      walletId: json['walletId'],
      type: json['type'],
      amount: (json['amount'] ?? 0.0).toDouble(),
      fee: (json['fee'] ?? 0.0).toDouble(),
      toAddress: json['toAddress'],
      fromAddress: json['fromAddress'],
      description: json['description'],
      status: json['status'],
      txHash: json['txHash'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'walletId': walletId,
      'type': type,
      'amount': amount,
      'fee': fee,
      'toAddress': toAddress,
      'fromAddress': fromAddress,
      'description': description,
      'status': status,
      'txHash': txHash,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
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