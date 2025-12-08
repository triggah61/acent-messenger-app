import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

/// Google Play Billing Service
/// Handles in-app purchases and subscriptions via Google Play Billing
class GooglePlayBillingService {
  static final GooglePlayBillingService _instance = GooglePlayBillingService._internal();
  factory GooglePlayBillingService() => _instance;
  GooglePlayBillingService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isAvailable = false;
  bool _purchasePending = false;

  /// Initialize the billing service
  Future<bool> initialize() async {
    try {
      _isAvailable = await _inAppPurchase.isAvailable();
      
      if (!_isAvailable) {
        print('GooglePlayBillingService: In-app purchase not available');
        return false;
      }

      // Listen to purchase updates
      _subscription = _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () {
          _subscription?.cancel();
        },
        onError: (error) {
          print('GooglePlayBillingService: Purchase stream error: $error');
        },
      );

      print('GooglePlayBillingService: ✅ Initialized successfully');
      return true;
    } catch (e) {
      print('GooglePlayBillingService: ❌ Initialization failed: $e');
      return false;
    }
  }

  /// Handle purchase updates
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (var purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchasePending = true;
        print('GooglePlayBillingService: Purchase pending: ${purchaseDetails.productID}');
      } else {
        _purchasePending = false;
        
        if (purchaseDetails.status == PurchaseStatus.error) {
          print('GooglePlayBillingService: Purchase error: ${purchaseDetails.error}');
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          print('GooglePlayBillingService: Purchase successful: ${purchaseDetails.productID}');
        }
      }

      // Complete the purchase
      if (purchaseDetails.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  /// Get product details for a list of product IDs
  Future<ProductDetailsResponse> getProductDetails(
    Set<String> productIds, {
    bool isSubscription = false,
  }) async {
    if (!_isAvailable) {
      throw Exception('In-app purchase not available');
    }

    try {
      final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(
        productIds,
      );

      if (response.error != null) {
        throw Exception('Failed to query products: ${response.error!.message}');
      }

      return response;
    } catch (e) {
      print('GooglePlayBillingService: Error querying products: $e');
      rethrow;
    }
  }

  /// Purchase a product (one-time purchase)
  Future<PurchaseDetails?> purchaseProduct(ProductDetails productDetails) async {
    if (!_isAvailable) {
      throw Exception('In-app purchase not available');
    }

    if (_purchasePending) {
      throw Exception('Another purchase is already in progress');
    }

    try {
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        throw Exception('Failed to initiate purchase');
      }

      // Wait for purchase to complete (handled by stream)
      return null;
    } catch (e) {
      print('GooglePlayBillingService: Purchase error: $e');
      rethrow;
    }
  }

  /// Purchase a subscription
  Future<PurchaseDetails?> purchaseSubscription(ProductDetails productDetails) async {
    if (!_isAvailable) {
      throw Exception('In-app purchase not available');
    }

    if (_purchasePending) {
      throw Exception('Another purchase is already in progress');
    }

    try {
      // For subscriptions, we need to check the product type
      // The in_app_purchase package handles subscriptions differently
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      // Use buyNonConsumable for subscriptions (Google Play handles subscriptions automatically)
      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        throw Exception('Failed to initiate subscription purchase');
      }

      // Wait for purchase to complete (handled by stream)
      return null;
    } catch (e) {
      print('GooglePlayBillingService: Subscription purchase error: $e');
      rethrow;
    }
  }

  /// Wait for purchase completion
  Future<PurchaseDetails?> waitForPurchase(String productId, {Duration timeout = const Duration(seconds: 60)}) async {
    final completer = Completer<PurchaseDetails?>();
    StreamSubscription<List<PurchaseDetails>>? tempSubscription;
    Timer? timeoutTimer;

    tempSubscription = _inAppPurchase.purchaseStream.listen((purchases) {
      for (var purchase in purchases) {
        if (purchase.productID == productId) {
          if (purchase.status == PurchaseStatus.purchased || 
              purchase.status == PurchaseStatus.restored) {
            timeoutTimer?.cancel();
            tempSubscription?.cancel();
            completer.complete(purchase);
            return;
          } else if (purchase.status == PurchaseStatus.error) {
            timeoutTimer?.cancel();
            tempSubscription?.cancel();
            completer.completeError(purchase.error ?? Exception('Purchase failed'));
            return;
          }
        }
      }
    });

    timeoutTimer = Timer(timeout, () {
      tempSubscription?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(Exception('Purchase timeout'));
      }
    });

    return completer.future;
  }

  /// Restore purchases
  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      throw Exception('In-app purchase not available');
    }

    try {
      await _inAppPurchase.restorePurchases();
    } catch (e) {
      print('GooglePlayBillingService: Restore purchases error: $e');
      rethrow;
    }
  }

  /// Get purchase details from purchase token
  String? getPurchaseToken(PurchaseDetails purchaseDetails) {
    if (purchaseDetails is GooglePlayPurchaseDetails) {
      return purchaseDetails.billingClientPurchase.purchaseToken;
    } else if (purchaseDetails is AppStorePurchaseDetails) {
      return purchaseDetails.skPaymentTransaction.transactionIdentifier;
    }
    return null;
  }

  /// Get order ID from purchase details
  String? getOrderId(PurchaseDetails purchaseDetails) {
    if (purchaseDetails is GooglePlayPurchaseDetails) {
      return purchaseDetails.billingClientPurchase.orderId;
    } else if (purchaseDetails is AppStorePurchaseDetails) {
      return purchaseDetails.skPaymentTransaction.transactionIdentifier;
    }
    return null;
  }

  /// Check if purchase is pending
  bool get isPurchasePending => _purchasePending;

  /// Check if billing is available
  bool get isAvailable => _isAvailable;

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

