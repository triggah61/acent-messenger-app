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
    print('🔵 [BillingService] _onPurchaseUpdate called with ${purchaseDetailsList.length} purchase(s)');
    for (var purchaseDetails in purchaseDetailsList) {
      print('🔵 [BillingService] Processing purchase: ${purchaseDetails.productID}');
      print('   - Status: ${purchaseDetails.status}');
      print('   - Pending complete: ${purchaseDetails.pendingCompletePurchase}');
      
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchasePending = true;
        print('⏳ [BillingService] Purchase pending: ${purchaseDetails.productID}');
      } else {
        _purchasePending = false;
        
        if (purchaseDetails.status == PurchaseStatus.error) {
          print('❌ [BillingService] Purchase error detected:');
          print('   - Product ID: ${purchaseDetails.productID}');
          if (purchaseDetails.error != null) {
            print('   - Error code: ${purchaseDetails.error!.code}');
            print('   - Error message: ${purchaseDetails.error!.message}');
            print('   - Error details: ${purchaseDetails.error!.details}');
          }
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          print('✅ [BillingService] Purchase successful: ${purchaseDetails.productID}');
        } else {
          print('⚠️ [BillingService] Unknown purchase status: ${purchaseDetails.status}');
        }
      }

      // Complete the purchase
      if (purchaseDetails.pendingCompletePurchase) {
        print('🔵 [BillingService] Completing purchase: ${purchaseDetails.productID}');
        _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  /// Get product details for a list of product IDs
  Future<ProductDetailsResponse> getProductDetails(
    Set<String> productIds, {
    bool isSubscription = false,
  }) async {
    print('🔵 [BillingService] getProductDetails called');
    print('   - Product IDs: $productIds');
    print('   - Is subscription: $isSubscription');
    print('   - Billing available: $_isAvailable');
    
    if (!_isAvailable) {
      print('❌ [BillingService] Billing not available');
      throw Exception('In-app purchase not available');
    }

    try {
      print('🔵 [BillingService] Querying product details from Google Play...');
      final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(
        productIds,
      );

      print('✅ [BillingService] Product query completed');
      print('   - Products found: ${response.productDetails.length}');
      print('   - Not found IDs: ${response.notFoundIDs}');
      
      if (response.error != null) {
        print('❌ [BillingService] Product query error:');
        print('   - Code: ${response.error!.code}');
        print('   - Message: ${response.error!.message}');
        print('   - Details: ${response.error!.details}');
        throw Exception('Failed to query products: ${response.error!.message}');
      }

      if (response.productDetails.isNotEmpty) {
        for (var product in response.productDetails) {
          print('✅ [BillingService] Product found:');
          print('   - ID: ${product.id}');
          print('   - Price: ${product.price}');
          print('   - Title: ${product.title}');
        }
      } else {
        print('⚠️ [BillingService] No products found');
        if (response.notFoundIDs.isNotEmpty) {
          print('   - Not found IDs: ${response.notFoundIDs}');
        }
      }

      return response;
    } catch (e, stackTrace) {
      print('❌ [BillingService] Error querying products: $e');
      print('❌ [BillingService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Purchase a consumable product (one-time purchase like top-up)
  /// Uses buyConsumable for products that can be purchased multiple times
  Future<PurchaseDetails?> purchaseProduct(ProductDetails productDetails) async {
    print('🔵 [BillingService] purchaseProduct called');
    print('   - Product ID: ${productDetails.id}');
    print('   - Price: ${productDetails.price}');
    print('   - Billing available: $_isAvailable');
    print('   - Purchase pending: $_purchasePending');
    
    if (!_isAvailable) {
      print('❌ [BillingService] Billing not available');
      throw Exception('In-app purchase not available');
    }

    if (_purchasePending) {
      print('❌ [BillingService] Another purchase already in progress');
      throw Exception('Another purchase is already in progress');
    }

    try {
      print('🔵 [BillingService] Creating purchase param...');
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      print('🔵 [BillingService] Initiating CONSUMABLE purchase with Google Play...');
      print('   - Product type: Consumable (top-up)');
      print('   - Using buyConsumable method');
      
      // IMPORTANT: For consumable products (like top-ups), we MUST use buyConsumable
      // buyNonConsumable is only for products that can only be purchased once
      // buyConsumable allows the product to be purchased multiple times
      final bool success = await _inAppPurchase.buyConsumable(
        purchaseParam: purchaseParam,
        autoConsume: true, // Automatically consume after purchase
      );

      print('🔵 [BillingService] Purchase initiation result: $success');
      if (!success) {
        print('❌ [BillingService] Failed to initiate purchase');
        throw Exception('Failed to initiate purchase');
      }

      print('✅ [BillingService] Purchase initiated successfully, waiting for completion...');
      // Wait for purchase to complete (handled by stream)
      return null;
    } catch (e, stackTrace) {
      print('❌ [BillingService] Purchase error: $e');
      print('❌ [BillingService] Stack trace: $stackTrace');
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
    print('🔵 [BillingService] waitForPurchase called');
    print('   - Product ID: $productId');
    print('   - Timeout: ${timeout.inSeconds}s');
    
    final completer = Completer<PurchaseDetails?>();
    StreamSubscription<List<PurchaseDetails>>? tempSubscription;
    Timer? timeoutTimer;

    print('🔵 [BillingService] Setting up purchase stream listener...');
    tempSubscription = _inAppPurchase.purchaseStream.listen((purchases) {
      print('🔵 [BillingService] Purchase stream update received: ${purchases.length} purchase(s)');
      for (var purchase in purchases) {
        print('   - Product ID: ${purchase.productID}, Status: ${purchase.status}');
        print('   - Pending complete: ${purchase.pendingCompletePurchase}');
        
        // Check if this is the purchase we're waiting for
        if (purchase.productID == productId) {
          print('✅ [BillingService] Matching product found: $productId');
          
          if (purchase.status == PurchaseStatus.purchased || 
              purchase.status == PurchaseStatus.restored) {
            print('✅ [BillingService] Purchase successful!');
            timeoutTimer?.cancel();
            tempSubscription?.cancel();
            completer.complete(purchase);
            return;
          } else if (purchase.status == PurchaseStatus.error) {
            print('❌ [BillingService] Purchase error status received');
            if (purchase.error != null) {
              print('   - Error code: ${purchase.error!.code}');
              print('   - Error message: ${purchase.error!.message}');
              print('   - Error details: ${purchase.error!.details}');
            }
            timeoutTimer?.cancel();
            tempSubscription?.cancel();
            
            // Create a more detailed error message
            String errorMsg = 'Purchase failed';
            final purchaseError = purchase.error;
            if (purchaseError != null) {
              final errorMessage = purchaseError.message;
              final errorCode = purchaseError.code;
              print('   - Error code: $errorCode');
              print('   - Error message: $errorMessage');
              
              if (errorCode == 'item_unavailable') {
                errorMsg = 'The item you are trying to purchase is not available. Please check Google Play Console.';
              } else if (errorCode == 'developer_error') {
                errorMsg = 'Developer error: $errorMessage';
              } else if (errorCode == 'user_canceled') {
                errorMsg = 'Purchase was cancelled by user';
              } else {
                errorMsg = errorMessage.isNotEmpty ? errorMessage : 'Purchase failed with code: $errorCode';
              }
            }
            
            completer.completeError(Exception(errorMsg));
            return;
          } else if (purchase.status == PurchaseStatus.pending) {
            print('⏳ [BillingService] Purchase pending...');
          } else if (purchase.status == PurchaseStatus.canceled) {
            print('⚠️ [BillingService] Purchase cancelled by user');
            timeoutTimer?.cancel();
            tempSubscription?.cancel();
            completer.completeError(Exception('Purchase was cancelled'));
            return;
          } else {
            print('⚠️ [BillingService] Purchase status: ${purchase.status}');
          }
        } else {
          print('   - Skipping purchase (different product ID)');
        }
      }
    }, onError: (error) {
      print('❌ [BillingService] Purchase stream error: $error');
      print('❌ [BillingService] Error type: ${error.runtimeType}');
      timeoutTimer?.cancel();
      tempSubscription?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    timeoutTimer = Timer(timeout, () {
      print('⏰ [BillingService] Purchase timeout after ${timeout.inSeconds}s');
      tempSubscription?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(Exception('Purchase timeout after ${timeout.inSeconds} seconds'));
      }
    });

    print('⏳ [BillingService] Waiting for purchase completion...');
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

