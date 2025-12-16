/// Credit Package Model
/// Represents a top-up package available for purchase
class CreditPackage {
  final String id;
  final String name;
  final String? description;
  final double usdPrice;
  final int credits;
  final String productId; // Google Play product ID
  final bool isPopular;
  final int sortOrder;

  CreditPackage({
    required this.id,
    required this.name,
    this.description,
    required this.usdPrice,
    required this.credits,
    required this.productId,
    this.isPopular = false,
    this.sortOrder = 0,
  });

  factory CreditPackage.fromJson(Map<String, dynamic> json) {
    return CreditPackage(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      usdPrice: (json['usdPrice'] as num?)?.toDouble() ?? 0.0,
      credits: (json['credits'] as num?)?.toInt() ?? 0,
      productId: json['productId'] ?? '',
      isPopular: json['isPopular'] ?? false,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'usdPrice': usdPrice,
      'credits': credits,
      'productId': productId,
      'isPopular': isPopular,
      'sortOrder': sortOrder,
    };
  }
}

