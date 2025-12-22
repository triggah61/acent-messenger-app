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
  
  // Local pricing from Google Play (optional, falls back to USD)
  final String? localPrice; // Formatted price string (e.g., "£7.99", "€8.99")
  final String? currencyCode; // Currency code (e.g., "GBP", "EUR", "USD")

  CreditPackage({
    required this.id,
    required this.name,
    this.description,
    required this.usdPrice,
    required this.credits,
    required this.productId,
    this.isPopular = false,
    this.sortOrder = 0,
    this.localPrice,
    this.currencyCode,
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
      localPrice: json['localPrice'],
      currencyCode: json['currencyCode'],
    );
  }
  
  /// Get display price - prefers local price, falls back to USD
  String getDisplayPrice() {
    if (localPrice != null && localPrice!.isNotEmpty) {
      return localPrice!;
    }
    return '\$${usdPrice.toStringAsFixed(2)}';
  }
  
  /// Get currency code for display
  String getDisplayCurrencyCode() {
    return currencyCode ?? 'USD';
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

