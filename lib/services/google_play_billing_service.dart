import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

/// Google Play Billing Service
/// Handles in-app purchases and subscriptions via Google Play Billing
/// 
/// TEST MODE:
/// Set [testMode] to true during development to simulate purchases
/// without connecting to Google Play. This is useful when:
/// - Running in debug mode
/// - Testing UI flows
/// - Developing new features
/// 
/// In production, set [testMode] to false.
class GooglePlayBillingService {
  static final GooglePlayBillingService _instance = GooglePlayBillingService._internal();
  factory GooglePlayBillingService() => _instance;
  GooglePlayBillingService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isAvailable = false;
  bool _purchasePending = false;
  
  /// Enable test mode to simulate purchases during development
  /// Set to false for production builds
  /// 
  /// When true:
  /// - Products are simulated (no Google Play connection needed)
  /// - Purchases always succeed
  /// - No real charges are made
  /// 
  /// Can be enabled via: GooglePlayBillingService().enableTestMode()
  bool _testMode = false;
  
  /// Test mode products for simulation
  final Map<String, Map<String, dynamic>> _testProducts = {};
  
  /// Enable test mode for development
  /// Call this in debug mode to simulate purchases
  void enableTestMode({Map<String, Map<String, dynamic>>? products}) {
    _testMode = true;
    _isAvailable = true;
    
    // Add provided products or use defaults
    if (products != null) {
      _testProducts.addAll(products);
    }
    
    print('🧪 [BillingService] TEST MODE ENABLED');
    print('   - All purchases will be simulated');
    print('   - No real charges will be made');
    print('   - Products will be mocked');
  }
  
  /// Disable test mode (for production)
  void disableTestMode() {
    _testMode = false;
    _testProducts.clear();
    print('🔒 [BillingService] Test mode disabled - using real Google Play');
  }
  
  /// Check if test mode is enabled
  bool get isTestMode => _testMode;
  
  /// Add a test product for simulation
  void addTestProduct(String productId, {
    String? title,
    String? description,
    String? price,
    double? priceValue,
  }) {
    _testProducts[productId] = {
      'id': productId,
      'title': title ?? 'Test Product: $productId',
      'description': description ?? 'Test subscription for development',
      'price': price ?? '\$9.99',
      'priceValue': priceValue ?? 9.99,
    };
    print('🧪 [BillingService] Added test product: $productId');
  }
  
  /// Create a simulated ProductDetailsResponse for test mode
  ProductDetailsResponse _createTestProductResponse(Set<String> productIds) {
    final List<ProductDetails> testProductDetails = [];
    final Set<String> notFound = {};
    
    for (final productId in productIds) {
      if (_testProducts.containsKey(productId)) {
        final testData = _testProducts[productId]!;
        testProductDetails.add(_TestProductDetails(
          id: productId,
          title: testData['title'] as String,
          description: testData['description'] as String,
          price: testData['price'] as String,
          rawPrice: testData['priceValue'] as double,
          currencyCode: 'USD',
          currencySymbol: '\$',
        ));
        print('🧪 [BillingService] Test product found: $productId');
      } else {
        notFound.add(productId);
        print('⚠️ [BillingService] Test product not found: $productId');
      }
    }
    
    print('🧪 [BillingService] Test query complete:');
    print('   - Products found: ${testProductDetails.length}');
    print('   - Not found: ${notFound.length}');
    
    return ProductDetailsResponse(
      productDetails: testProductDetails,
      notFoundIDs: notFound.toList(),
      error: null,
    );
  }
  
  /// Simulate a test purchase (for test mode)
  /// Returns a mock purchase token for verification
  Future<String> simulateTestPurchase(String productId) async {
    print('🧪 [BillingService] Simulating test purchase for: $productId');
    
    // Simulate a small delay like a real purchase
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Generate a mock purchase token
    final mockToken = 'TEST_PURCHASE_TOKEN_${productId}_${DateTime.now().millisecondsSinceEpoch}';
    
    print('🧪 [BillingService] Test purchase simulated successfully');
    print('   - Product ID: $productId');
    print('   - Mock Token: $mockToken');
    print('   ⚠️ NOTE: This is a TEST purchase - no real charge was made');
    
    return mockToken;
  }

  /// Initialize the billing service
  /// 
  /// Set [autoEnableTestModeInDebug] to true to automatically enable test mode
  /// when running in debug mode. This allows testing without Google Play.
  Future<bool> initialize({bool autoEnableTestModeInDebug = false}) async {
    try {
      // Auto-enable test mode in debug builds if requested
      if (autoEnableTestModeInDebug && kDebugMode) {
        print('🧪 [BillingService] Debug mode detected - enabling test mode');
        enableTestMode();
        return true;
      }
      
      _isAvailable = await _inAppPurchase.isAvailable();
      
      if (!_isAvailable) {
        print('GooglePlayBillingService: In-app purchase not available');
        
        // In debug mode, suggest enabling test mode
        if (kDebugMode) {
          print('💡 [BillingService] Tip: Enable test mode for development');
          print('   Call: GooglePlayBillingService().enableTestMode()');
          print('   Or: GooglePlayBillingService().initialize(autoEnableTestModeInDebug: true)');
        }
        
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
      print('   - Mode: ${_testMode ? "TEST" : "PRODUCTION"}');
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
  /// In test mode, returns simulated product details
  Future<ProductDetailsResponse> getProductDetails(
    Set<String> productIds, {
    bool isSubscription = false,
  }) async {
    print('🔵 [BillingService] getProductDetails called');
    print('   - Product IDs: $productIds');
    print('   - Is subscription: $isSubscription');
    print('   - Billing available: $_isAvailable');
    print('   - Test mode: $_testMode');
    
    // TEST MODE: Return simulated products
    if (_testMode) {
      print('🧪 [BillingService] TEST MODE - Simulating product query...');
      
      // Auto-add test products for any requested product IDs
      for (final productId in productIds) {
        if (!_testProducts.containsKey(productId)) {
          addTestProduct(
            productId,
            title: 'Test: $productId',
            description: 'Test subscription for development',
            price: isSubscription ? '\$9.99/month' : '\$9.99',
            priceValue: 9.99,
          );
        }
      }
      
      // Create mock response with test products
      return _createTestProductResponse(productIds);
    }
    
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
  /// 
  /// IMPORTANT: For Google Play subscriptions:
  /// - Use subscription product ID (e.g., 'test_monthly') - NOT base plan ID
  /// - Google Play automatically uses the base plan
  /// - Base plan ID is only needed if subscription has multiple base plans
  Future<PurchaseDetails?> purchaseSubscription(ProductDetails productDetails) async {
    print('🔵 [BillingService] purchaseSubscription called');
    print('   - Product ID: ${productDetails.id}');
    print('   - Price: ${productDetails.price}');
    print('   - Title: ${productDetails.title}');
    print('   - Description: ${productDetails.description}');
    print('   - Billing available: $_isAvailable');
    print('   - Purchase pending: $_purchasePending');
    print('   - Test mode: $_testMode');
    
    // TEST MODE: Simulate purchase
    if (_testMode) {
      print('🧪 [BillingService] TEST MODE - Simulating subscription purchase...');
      final mockToken = await simulateTestPurchase(productDetails.id);
      
      // Return a mock purchase details
      // The calling code should check for test mode and handle accordingly
      print('🧪 [BillingService] TEST MODE - Purchase simulation complete');
      print('   - Mock token: $mockToken');
      print('   ⚠️ NOTE: No real charge was made');
      
      // In test mode, we return null but the purchase is considered successful
      // The caller should check isTestMode and handle accordingly
      return null;
    }
    
    if (!_isAvailable) {
      print('❌ [BillingService] Billing not available');
      throw Exception('In-app purchase not available');
    }

    if (_purchasePending) {
      print('❌ [BillingService] Another purchase already in progress');
      throw Exception('Another purchase is already in progress');
    }

    try {
      // For subscriptions, the in_app_purchase package uses buyNonConsumable
      // Google Play automatically handles the subscription and base plan
      // We only need the subscription product ID (e.g., 'test_monthly')
      // Base plan ID (e.g., 'test-monthly-baseplan') is NOT needed
      
      print('🔵 [BillingService] Creating purchase param for subscription...');
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      print('🔵 [BillingService] Initiating subscription purchase with Google Play...');
      print('   - Using buyNonConsumable (correct for subscriptions)');
      print('   - Subscription Product ID: ${productDetails.id}');
      print('   - Note: Base plan ID is handled automatically by Google Play');
      
      // Use buyNonConsumable for subscriptions
      // This is the correct method for subscriptions in the in_app_purchase package
      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      print('🔵 [BillingService] Purchase initiation result: $success');

      if (!success) {
        print('❌ [BillingService] Failed to initiate subscription purchase');
        throw Exception('Failed to initiate subscription purchase');
      }

      print('✅ [BillingService] Subscription purchase initiated successfully');
      print('   - Waiting for Google Play to process...');
      print('   - Google Play will use the base plan automatically');

      // Wait for purchase to complete (handled by stream)
      return null;
    } catch (e, stackTrace) {
      print('❌ [BillingService] Subscription purchase error: $e');
      print('❌ [BillingService] Stack trace: $stackTrace');
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

  /// Run diagnostic check for billing setup
  /// Returns a map with diagnostic information
  Future<Map<String, dynamic>> runDiagnostics(Set<String> productIds) async {
    final diagnostics = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'billingAvailable': _isAvailable,
      'productIds': productIds.toList(),
      'issues': <String>[],
      'recommendations': <String>[],
    };

    print('🔍 [BillingService] Running diagnostics...');
    print('   - Testing product IDs: $productIds');

    // Check 1: Billing availability
    if (!_isAvailable) {
      diagnostics['issues'].add('Google Play Billing is not available');
      diagnostics['recommendations'].add(
        'Ensure Google Play Services is installed and updated'
      );
      return diagnostics;
    }

    // Check 2: Query products
    try {
      final response = await _inAppPurchase.queryProductDetails(productIds);
      
      diagnostics['productsFound'] = response.productDetails.length;
      diagnostics['notFoundIds'] = response.notFoundIDs.toList();
      diagnostics['hasError'] = response.error != null;
      
      if (response.error != null) {
        diagnostics['errorCode'] = response.error!.code;
        diagnostics['errorMessage'] = response.error!.message;
        diagnostics['issues'].add('Error querying products: ${response.error!.message}');
      }

      if (response.productDetails.isEmpty) {
        diagnostics['issues'].add('No products found in Google Play');
        diagnostics['recommendations'].addAll([
          '1. Ensure app is installed from Google Play Store (not adb or flutter run)',
          '2. Verify subscriptions are ACTIVE in Play Console (not Draft)',
          '3. Verify base plans are ACTIVE',
          '4. Ensure you are using a license tester account',
          '5. Upload a signed release to Internal Testing track',
          '6. Wait 15-60 minutes for changes to propagate',
        ]);
      } else {
        diagnostics['products'] = response.productDetails.map((p) => {
          'id': p.id,
          'title': p.title,
          'price': p.price,
          'description': p.description,
        }).toList();
      }

      if (response.notFoundIDs.isNotEmpty) {
        diagnostics['issues'].add(
          'Products not found: ${response.notFoundIDs.join(", ")}'
        );
      }
    } catch (e) {
      diagnostics['queryError'] = e.toString();
      diagnostics['issues'].add('Failed to query products: $e');
    }

    // Print diagnostic summary
    print('🔍 [BillingService] Diagnostic Results:');
    print('   - Billing available: ${diagnostics['billingAvailable']}');
    print('   - Products found: ${diagnostics['productsFound'] ?? 0}');
    print('   - Not found IDs: ${diagnostics['notFoundIds'] ?? []}');
    print('   - Issues: ${(diagnostics['issues'] as List).length}');
    
    if ((diagnostics['issues'] as List).isNotEmpty) {
      print('');
      print('⚠️ [BillingService] Issues Found:');
      for (final issue in diagnostics['issues']) {
        print('   - $issue');
      }
    }

    if ((diagnostics['recommendations'] as List).isNotEmpty) {
      print('');
      print('💡 [BillingService] Recommendations:');
      for (final rec in diagnostics['recommendations']) {
        print('   - $rec');
      }
    }

    return diagnostics;
  }

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// Test product details for simulating purchases in development
/// This class implements ProductDetails interface for test mode
class _TestProductDetails extends ProductDetails {
  _TestProductDetails({
    required String id,
    required String title,
    required String description,
    required String price,
    required double rawPrice,
    required String currencyCode,
    required String currencySymbol,
  }) : super(
    id: id,
    title: title,
    description: description,
    price: price,
    rawPrice: rawPrice,
    currencyCode: currencyCode,
    currencySymbol: currencySymbol,
  );
}

