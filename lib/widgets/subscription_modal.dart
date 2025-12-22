import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../models/subscription_plan.dart';
import '../models/credit_package.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../services/topup_service.dart';
import '../services/google_play_billing_service.dart';
import '../providers/auth_provider.dart';
import '../constants/config.dart';

/// Subscription Modal Widget
/// Displays subscription plans and top-up balance functionality
class SubscriptionModal extends StatefulWidget {
  final UserSubscription currentSubscription;
  final ScrollController? scrollController;

  const SubscriptionModal({
    super.key,
    required this.currentSubscription,
    this.scrollController,
  });

  static void show(BuildContext context, UserSubscription subscription) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => SubscriptionModal(
          currentSubscription: subscription,
          scrollController: scrollController,
        ),
      ),
    );
  }

  @override
  State<SubscriptionModal> createState() => _SubscriptionModalState();
}

class _SubscriptionModalState extends State<SubscriptionModal> {
  int _selectedTabIndex = 0; // 0 = Plans, 1 = Top Up
  bool _isAnnual = false; // false = Monthly, true = Annual

  // API-related state
  List<SubscriptionPlan> _plans = [];
  bool _isLoadingPlans = true;
  String? _errorMessage;
  bool _isSubscribing = false;
  late SubscriptionService _subscriptionService;
  late TopUpService _topUpService;
  late GooglePlayBillingService _billingService;

  // Profile and balance state
  double _totalBalance = 0.0;
  double _topUpBalance = 0.0;
  double _subscriptionBalance = 0.0;
  String? _currentPlanId;
  bool _isLoadingBalance = true;

  // Top-up state
  List<CreditPackage> _packages = [];
  bool _isLoadingPackages = true;
  bool _isToppingUp = false;
  String? _toppingUpPackageId;

  // Billing service state
  bool _isBillingAvailable = false;

  @override
  void initState() {
    super.initState();

    // Initialize services
    final authService = Provider.of<AuthService>(context, listen: false);
    _subscriptionService = SubscriptionService(authService);
    _topUpService = TopUpService(authService);
    _billingService = GooglePlayBillingService();

    // Fetch plans, packages, and balance from API
    _fetchPlans();
    _fetchPackages(); // Fetch initially without local pricing
    _fetchBalance();

    // Initialize billing service and then re-fetch packages with local pricing
    _initializeBilling().then((_) {
      // Re-fetch packages after billing is initialized to enrich with local pricing
      if (_isBillingAvailable) {
        print('🔄 [Billing] Re-fetching packages with local pricing...');
        _fetchPackages();
      }
    });
  }

  @override
  void dispose() {
    _billingService.dispose();
    super.dispose();
  }

  /// Initialize Google Play Billing service
  Future<void> _initializeBilling() async {
    print('🔵 [Billing] Initializing Google Play Billing service...');
    try {
      final isAvailable = await _billingService.initialize();
      print('🔵 [Billing] Initialization result: $isAvailable');
      if (mounted) {
        setState(() {
          _isBillingAvailable = isAvailable;
        });
        print('✅ [Billing] Billing availability set to: $_isBillingAvailable');
      }
    } catch (e, stackTrace) {
      print('❌ [Billing] Failed to initialize billing: $e');
      print('❌ [Billing] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isBillingAvailable = false;
        });
        print('⚠️ [Billing] Billing availability set to: false');
      }
    }
  }

  /// Fetch subscription plans from API
  Future<void> _fetchPlans() async {
    setState(() {
      _isLoadingPlans = true;
      _errorMessage = null;
    });

    try {
      print('SubscriptionModal: Fetching plans...');
      final plans = await _subscriptionService.getSubscriptionPlans();
      print('SubscriptionModal: Received ${plans.length} plans');
      for (var plan in plans) {
        print('SubscriptionModal: Plan - ${plan.name} (${plan.id})');
      }
      setState(() {
        _plans = plans;
        _isLoadingPlans = false;
      });
      print('SubscriptionModal: State updated. Plans count: ${_plans.length}');
    } catch (e, stackTrace) {
      print('SubscriptionModal: Error fetching plans: $e');
      print('SubscriptionModal: Stack trace: $stackTrace');
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoadingPlans = false;
      });
    }
  }

  /// Fetch credit packages from API and enrich with local pricing
  Future<void> _fetchPackages() async {
    setState(() {
      _isLoadingPackages = true;
    });

    try {
      print('SubscriptionModal: Fetching credit packages...');
      final packagesData = await _topUpService.getTopUpPackages();
      List<CreditPackage> packages =
          packagesData.map((pkg) => CreditPackage.fromJson(pkg)).toList();
      print('SubscriptionModal: Received ${packages.length} packages');

      // Enrich packages with local pricing from Google Play if billing is available
      if (_isBillingAvailable && packages.isNotEmpty) {
        try {
          final productIds = packages
              .where((pkg) => pkg.productId.isNotEmpty)
              .map((pkg) => pkg.productId)
              .toSet();

          if (productIds.isNotEmpty) {
            print(
                'SubscriptionModal: Fetching local pricing for ${productIds.length} products...');
            final productDetailsResponse =
                await _billingService.getProductDetails(
              productIds,
              isSubscription: false,
            );

            // Create a map of productId -> ProductDetails for quick lookup
            final productDetailsMap = {
              for (var product in productDetailsResponse.productDetails)
                product.id: product
            };

            // Update packages with local pricing
            packages = packages.map((pkg) {
              final productDetails = productDetailsMap[pkg.productId];
              if (productDetails != null) {
                // Extract currency code from price string (e.g., "£7.99" -> "GBP", "$4.99" -> "USD")
                String? currencyCode;
                String localPrice = productDetails.price;

                print('🔵 [FetchPackages] Processing package: ${pkg.name}');
                print('   - Product ID: ${pkg.productId}');
                print('   - Google Play Price: $localPrice');

                // Try to extract currency code from price string
                if (localPrice.isNotEmpty) {
                  // Google Play price format usually includes currency symbol
                  // We can try to detect from the symbol
                  if (localPrice.startsWith('£')) {
                    currencyCode = 'GBP';
                  } else if (localPrice.startsWith('€')) {
                    currencyCode = 'EUR';
                  } else if (localPrice.startsWith('¥')) {
                    currencyCode = 'JPY';
                  } else if (localPrice.startsWith('₹')) {
                    currencyCode = 'INR';
                  } else if (localPrice.startsWith('\$')) {
                    // Could be USD, CAD, AUD, etc. - default to USD
                    currencyCode = 'USD';
                  }

                  print('   - Detected Currency: $currencyCode');
                  print('   - Local Price: $localPrice');
                }

                final enrichedPackage = CreditPackage(
                  id: pkg.id,
                  name: pkg.name,
                  description: pkg.description,
                  usdPrice: pkg.usdPrice,
                  credits: pkg.credits,
                  productId: pkg.productId,
                  isPopular: pkg.isPopular,
                  sortOrder: pkg.sortOrder,
                  localPrice: localPrice.isNotEmpty ? localPrice : null,
                  currencyCode: currencyCode,
                );

                print(
                    '   - Enriched Package Display Price: ${enrichedPackage.getDisplayPrice()}');
                print(
                    '   - Final localPrice value: ${enrichedPackage.localPrice}');
                print(
                    '   - Final currencyCode value: ${enrichedPackage.currencyCode}');

                return enrichedPackage;
              }
              print(
                  '⚠️ [FetchPackages] No product details found for: ${pkg.productId}');
              return pkg;
            }).toList();

            print(
                'SubscriptionModal: Enriched ${packages.length} packages with local pricing');
          }
        } catch (e) {
          print(
              'SubscriptionModal: Error fetching local pricing (using USD fallback): $e');
          // Continue with USD pricing if local pricing fails
        }
      }

      setState(() {
        _packages = packages;
        _isLoadingPackages = false;
      });
    } catch (e, stackTrace) {
      print('SubscriptionModal: Error fetching packages: $e');
      print('SubscriptionModal: Stack trace: $stackTrace');
      setState(() {
        _isLoadingPackages = false;
      });
    }
  }

  /// Fetch user balance from profile API
  Future<void> _fetchBalance() async {
    setState(() {
      _isLoadingBalance = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = await authService.getToken();
      if (token == null) {
        setState(() {
          _isLoadingBalance = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/profile/info'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          final profileData = data['data'];
          setState(() {
            _totalBalance =
                (profileData['balance']?['totalBalance'] as num?)?.toDouble() ??
                    0.0;
            _topUpBalance =
                (profileData['balance']?['topUpBalance'] as num?)?.toDouble() ??
                    0.0;
            _subscriptionBalance =
                (profileData['balance']?['subscriptionBalance'] as num?)
                        ?.toDouble() ??
                    0.0;
            _currentPlanId =
                profileData['subscription']?['currentPlan']?['_id']?.toString();
            _isLoadingBalance = false;
          });
        }
      } else {
        setState(() {
          _isLoadingBalance = false;
        });
      }
    } catch (e) {
      print('Error fetching balance: $e');
      setState(() {
        _isLoadingBalance = false;
      });
    }
  }

  /// Subscribe to a plan using Google Play Billing
  Future<void> _subscribeToPlan(SubscriptionPlan plan) async {
    print(
        '🔵 [Subscription] _subscribeToPlan called for plan: ${plan.name} (${plan.id})');

    // Handle custom plans
    if (plan.isCustom) {
      print('🔵 [Subscription] Custom plan detected, opening contact form...');
      if (plan.contactFormLink != null && plan.contactFormLink!.isNotEmpty) {
        final uri = Uri.parse(plan.contactFormLink!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          print('✅ [Subscription] Contact form opened successfully');
        } else {
          print('❌ [Subscription] Failed to open contact form link');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not open contact form link'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
      return;
    }

    // Check if billing is available
    if (!_isBillingAvailable) {
      print('❌ [Subscription] Billing not available');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '🚫 In-app purchases are not available. Please install the app from Play Store.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    setState(() {
      _isSubscribing = true;
    });
    print('✅ [Subscription] Starting subscription process...');

    try {
      final intervalType = _isAnnual ? 'year' : 'month';
      print('🔵 [Subscription] Interval type: $intervalType');

      // Get product ID based on environment and interval
      final bool useSandbox = Config.useGooglePlaySandbox;
      String? productId;

      // Try to get the appropriate product ID
      if (useSandbox) {
        productId = _isAnnual
            ? plan.googlePlaySandboxAnnualSubscriptionId
            : plan.googlePlaySandboxMonthlySubscriptionId;
        print('🔵 [Subscription] Using SANDBOX product ID: $productId');

        // Fallback to production ID if sandbox is not available
        if (productId == null || productId.isEmpty) {
          print(
              '⚠️ [Subscription] Sandbox product ID not found, trying production...');
          productId = _isAnnual
              ? plan.googlePlayAnnualSubscriptionId
              : plan.googlePlayMonthlySubscriptionId;
          print(
              '🔵 [Subscription] Fallback to PRODUCTION product ID: $productId');
        }
      } else {
        productId = _isAnnual
            ? plan.googlePlayAnnualSubscriptionId
            : plan.googlePlayMonthlySubscriptionId;
        print('🔵 [Subscription] Using PRODUCTION product ID: $productId');

        // Fallback to sandbox ID if production is not available (for testing)
        if (productId == null || productId.isEmpty) {
          print(
              '⚠️ [Subscription] Production product ID not found, trying sandbox...');
          productId = _isAnnual
              ? plan.googlePlaySandboxAnnualSubscriptionId
              : plan.googlePlaySandboxMonthlySubscriptionId;
          print('🔵 [Subscription] Fallback to SANDBOX product ID: $productId');
        }
      }

      // Log all available product IDs for debugging
      print('🔵 [Subscription] Available product IDs:');
      print(
          '   - Monthly Production: ${plan.googlePlayMonthlySubscriptionId ?? "null"}');
      print(
          '   - Monthly Sandbox: ${plan.googlePlaySandboxMonthlySubscriptionId ?? "null"}');
      print(
          '   - Annual Production: ${plan.googlePlayAnnualSubscriptionId ?? "null"}');
      print(
          '   - Annual Sandbox: ${plan.googlePlaySandboxAnnualSubscriptionId ?? "null"}');

      if (productId == null || productId.isEmpty) {
        print('❌ [Subscription] Product ID not configured for this plan');
        print('❌ [Subscription] Plan details:');
        print('   - Name: ${plan.name}');
        print('   - ID: ${plan.id}');
        print('   - Is Custom: ${plan.isCustom}');
        throw Exception(
            'This subscription plan is not yet available for purchase.\n\n'
            'The plan needs to be synced with Google Play Console first.\n\n'
            'Please ask an administrator to:\n'
            '1. Go to Admin Panel > Subscription Plans\n'
            '2. Find this plan and click "Sync with Google Play"\n'
            '3. Wait for sync to complete\n\n'
            'Then try again.');
      }

      print('🔵 [Subscription] Querying product details from Google Play...');
      // Query product details
      final productDetailsResponse = await _billingService.getProductDetails(
        {productId},
        isSubscription: true,
      );

      if (productDetailsResponse.productDetails.isEmpty) {
        print('❌ [Subscription] Product not found in Google Play Store');
        print('❌ [Subscription] Product ID queried: $productId');
        print(
            '❌ [Subscription] Not found IDs: ${productDetailsResponse.notFoundIDs}');

        // Run diagnostics to help identify the issue
        print('🔍 [Subscription] Running diagnostics...');
        await _billingService.runDiagnostics({productId});

        throw Exception(
            'Subscription "$productId" not found in Google Play Store.\n\n'
            'This usually happens when:\n'
            '• App is not installed from Play Store\n'
            '• Subscription is not yet active\n'
            '• Changes are still propagating (wait 15-60 mins)\n\n'
            'Please ensure you:\n'
            '1. Install app from Internal Testing link\n'
            '2. Use a license tester account\n'
            '3. Wait for subscription to activate');
      }

      final productDetails = productDetailsResponse.productDetails.first;
      print('✅ [Subscription] Product details retrieved:');
      print('   - ID: ${productDetails.id}');
      print('   - Title: ${productDetails.title}');
      print('   - Price: ${productDetails.price}');

      // Show purchase confirmation dialog
      print('🔵 [Subscription] Showing confirmation dialog...');
      final confirmPurchase = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            '🎉 Subscribe to ${plan.name}',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildConfirmationRow(Icons.card_membership, 'Plan', plan.name),
              _buildConfirmationRow(
                  Icons.schedule, 'Billing', _isAnnual ? 'Annual' : 'Monthly'),
              _buildConfirmationRow(
                  Icons.attach_money, 'Price', productDetails.price),
              _buildConfirmationRow(Icons.stars, 'Credits',
                  '${_isAnnual ? plan.annualCredits : plan.monthlyCredits}'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your subscription will auto-renew unless cancelled',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: plan.color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Continue to Payment'),
            ),
          ],
        ),
      );

      if (confirmPurchase != true) {
        print('ℹ️ [Subscription] User cancelled confirmation dialog');
        setState(() {
          _isSubscribing = false;
        });
        return;
      }

      print('🔵 [Subscription] Initiating purchase with Google Play...');
      print('   - Test mode: ${_billingService.isTestMode}');

      // Handle TEST MODE differently
      if (_billingService.isTestMode) {
        print('🧪 [Subscription] TEST MODE - Simulating purchase...');

        // Simulate the purchase
        await _billingService.purchaseSubscription(productDetails);
        final mockToken = await _billingService.simulateTestPurchase(productId);

        print('🧪 [Subscription] TEST MODE - Purchase simulated successfully');
        print('   - Mock token: $mockToken');
        print('   ⚠️ NOTE: This is a TEST purchase - no real charge was made');
        print('   ⚠️ NOTE: Skipping backend verification in test mode');

        // In test mode, show success without backend verification
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.science, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🧪 TEST MODE: Subscription simulated for ${plan.name}!\n'
                      'No real charge was made.',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
          Navigator.of(context).pop();
        }

        if (mounted) {
          setState(() {
            _isSubscribing = false;
          });
        }
        return;
      }

      // PRODUCTION MODE - Real purchase flow
      // Initiate purchase
      await _billingService.purchaseSubscription(productDetails);

      print(
          '⏳ [Subscription] Waiting for purchase completion (120s timeout)...');

      // Wait for purchase completion with proper error handling
      PurchaseDetails? purchaseDetails;
      try {
        purchaseDetails = await _billingService.waitForPurchase(
          productId,
          timeout: const Duration(seconds: 120),
        );
      } catch (waitError) {
        // Handle cancellation or errors from waitForPurchase
        print('❌ [Subscription] Purchase wait error: $waitError');

        // Reset loading state immediately
        if (mounted) {
          setState(() {
            _isSubscribing = false;
          });
        }

        // Check if it's a cancellation
        final errorString = waitError.toString().toLowerCase();
        if (errorString.contains('cancelled') ||
            errorString.contains('canceled') ||
            errorString.contains('user_canceled')) {
          print('ℹ️ [Subscription] User cancelled the purchase');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Purchase was cancelled. No charges were made.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return; // Exit early, state already reset
        }

        // Re-throw other errors to be handled by outer catch block
        throw Exception(waitError.toString().replaceAll('Exception: ', ''));
      }

      // Check if purchase details is null (shouldn't happen after try-catch, but safety check)
      if (purchaseDetails == null) {
        print('❌ [Subscription] Purchase details is null');
        if (mounted) {
          setState(() {
            _isSubscribing = false;
          });
        }
        throw Exception(
            'Purchase was cancelled or timed out. No charges were made.');
      }

      // Check purchase status
      if (purchaseDetails.status != PurchaseStatus.purchased) {
        final errorMsg = purchaseDetails.error?.message ?? 'Unknown error';
        print('❌ [Subscription] Purchase failed: $errorMsg');
        print('❌ [Subscription] Purchase status: ${purchaseDetails.status}');

        // Reset loading state immediately
        if (mounted) {
          setState(() {
            _isSubscribing = false;
          });
        }

        // Handle cancellation status
        if (purchaseDetails.status == PurchaseStatus.canceled) {
          print('ℹ️ [Subscription] Purchase was cancelled');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Purchase was cancelled. No charges were made.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return; // Exit early, state already reset
        }

        throw Exception('Purchase failed: $errorMsg');
      }

      print('✅ [Subscription] Purchase completed successfully');

      // Get purchase token
      final purchaseToken = _billingService.getPurchaseToken(purchaseDetails);
      if (purchaseToken == null) {
        print('❌ [Subscription] Failed to get purchase token');
        throw Exception(
            'Failed to process purchase. Please contact support with your order ID.');
      }
      print('✅ [Subscription] Purchase token retrieved');

      print('🔵 [Subscription] Verifying purchase with backend...');
      // Verify purchase with backend
      final result = await _subscriptionService.verifyGooglePlaySubscription(
        purchaseToken: purchaseToken,
        subscriptionId: productId,
        planId: plan.id,
        intervalType: intervalType,
      );

      print('✅ [Subscription] Backend verification completed');

      if (mounted) {
        if (result['success'] == true) {
          print('🎉 [Subscription] Subscription activated successfully!');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result['message'] ??
                          '🎉 Successfully subscribed to ${plan.name}!',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );

          print('🔵 [Subscription] Refreshing plans and balance...');
          // Refresh plans and balance
          await _fetchPlans();
          await _fetchBalance();

          // Refresh AuthProvider profile to update bottom bar balance
          try {
            final authProvider =
                Provider.of<AuthProvider>(context, listen: false);
            await authProvider.fetchProfile();
            print('✅ [Subscription] AuthProvider profile refreshed');
          } catch (e) {
            print('⚠️ [Subscription] Failed to refresh AuthProvider: $e');
          }

          await Future.delayed(const Duration(seconds: 1));

          if (mounted) {
            print('✅ [Subscription] Closing modal...');
            Navigator.of(context).pop();
          }
        } else {
          print('❌ [Subscription] Backend verification failed');
          throw Exception(result['message'] ??
              'Subscription verification failed. Please contact support.');
        }
      }
    } catch (e) {
      print('❌ [Subscription] Error: $e');

      // Ensure loading state is reset even if there was an error
      if (mounted) {
        setState(() {
          _isSubscribing = false;
        });

        // Only show error snackbar if it's not a cancellation (already handled)
        final errorString = e.toString().toLowerCase();
        if (!errorString.contains('cancelled') &&
            !errorString.contains('canceled')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(e.toString().replaceAll('Exception: ', '')),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () => _subscribeToPlan(plan),
              ),
            ),
          );
        }
      }
    } finally {
      // Final safety check - ensure state is always reset
      if (mounted && _isSubscribing) {
        print(
            '⚠️ [Subscription] Loading state still true in finally block, resetting...');
        setState(() {
          _isSubscribing = false;
        });
      }
      print('✅ [Subscription] Subscription process completed');
    }
  }

  Widget _buildConfirmationRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Subscription & Credits',
                  style: GoogleFonts.montserrat(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black87),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Current Plan & Balance Card
          _buildCurrentStatusCard(),

          // Tab Bar
          _buildTabBar(),

          // Content
          Expanded(
            child: _selectedTabIndex == 0 ? _buildPlansTab() : _buildTopUpTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStatusCard() {
    // Find current plan from fetched plans or use default
    SubscriptionPlan currentPlan;
    if (_currentPlanId != null) {
      try {
        currentPlan = _plans.firstWhere((p) => p.id == _currentPlanId);
      } catch (e) {
        currentPlan = widget.currentSubscription.plan;
      }
    } else {
      currentPlan = widget.currentSubscription.plan;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            currentPlan.color.withOpacity(0.8),
            currentPlan.color,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: currentPlan.color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getPlanIcon(currentPlan.id),
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Plan: ${currentPlan.name}',
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                if (_isLoadingBalance)
                  const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Text(
                    '${_totalBalance.toStringAsFixed(0)} Credits',
                    style: GoogleFonts.montserrat(
                      fontSize: 24,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              'Plans',
              0,
              Icons.workspace_premium,
            ),
          ),
          Expanded(
            child: _buildTabButton(
              'Top Up',
              1,
              Icons.account_balance_wallet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index, IconData icon) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.blueAccent : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.blueAccent : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlansTab() {
    print('SubscriptionModal: _buildPlansTab called');
    print('SubscriptionModal: _isLoadingPlans: $_isLoadingPlans');
    print('SubscriptionModal: _errorMessage: $_errorMessage');
    print('SubscriptionModal: _plans.length: ${_plans.length}');

    if (_isLoadingPlans) {
      print('SubscriptionModal: Showing loading indicator');
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      print('SubscriptionModal: Showing error: $_errorMessage');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red[300],
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load plans',
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchPlans,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_plans.isEmpty) {
      print('SubscriptionModal: Plans list is empty, showing empty state');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No plans available',
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please check back later',
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchPlans,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    print('SubscriptionModal: Building plans list with ${_plans.length} plans');

    // Build list of children widgets safely
    final List<Widget> children = [
      Text(
        'Choose Your Plan',
        style: GoogleFonts.montserrat(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Select a plan that fits your needs',
        style: GoogleFonts.montserrat(
          fontSize: 14,
          color: Colors.grey[600],
        ),
      ),
      const SizedBox(height: 24),
    ];

    // Monthly/Annual Toggle Switch (only show if there are non-custom plans)
    if (_plans.isNotEmpty && _plans.any((plan) => !plan.isCustom)) {
      children.add(_buildBillingToggle());
      children.add(const SizedBox(height: 24));
    }

    // Add plan cards - filter and map safely
    final validPlans = _plans.where((plan) => plan.id.isNotEmpty).toList();
    print('SubscriptionModal: Valid plans count: ${validPlans.length}');
    for (var plan in validPlans) {
      print(
          'SubscriptionModal: Building card for plan: ${plan.name} (${plan.id})');
      try {
        final card = _buildPlanCard(plan);
        children.add(card);
        print('SubscriptionModal: Successfully added card for ${plan.name}');
      } catch (e, stackTrace) {
        print(
            'SubscriptionModal: Error building plan card for plan ${plan.id}: $e');
        print('SubscriptionModal: Stack trace: $stackTrace');
        // Skip this plan if it fails to build
      }
    }

    print('SubscriptionModal: Total children widgets: ${children.length}');

    // Ensure we have at least some children
    if (children.isEmpty) {
      print('SubscriptionModal: Children list is empty!');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No plans to display'),
            const SizedBox(height: 16),
            Text('Plans count: ${_plans.length}'),
            Text('Valid plans: ${_plans.where((p) => p.id.isNotEmpty).length}'),
            ElevatedButton(
              onPressed: _fetchPlans,
              child: const Text('Retry Fetch'),
            ),
          ],
        ),
      );
    }

    print(
        'SubscriptionModal: Returning ListView with ${children.length} children');
    // Use ListView but ensure padding is properly set
    // The scrollController from DraggableScrollableSheet should work fine
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      children: children,
    );
  }

  Widget _buildBillingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isAnnual = false;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_isAnnual ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: !_isAnnual
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Monthly',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight:
                          !_isAnnual ? FontWeight.w600 : FontWeight.w500,
                      color: !_isAnnual ? Colors.blueAccent : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isAnnual = true;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isAnnual ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: _isAnnual
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Annual',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: _isAnnual ? FontWeight.w600 : FontWeight.w500,
                      color: _isAnnual ? Colors.blueAccent : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan) {
    // Add null safety checks
    if (plan.id.isEmpty) {
      return const SizedBox.shrink(); // Skip rendering if plan has no ID
    }

    // Ensure all required fields are valid
    if (plan.name.isEmpty) {
      print('Warning: Plan ${plan.id} has empty name, using default');
    }

    final isCurrentPlan = plan.id == _currentPlanId ||
        plan.id == widget.currentSubscription.planId;
    final isFree = plan.monthlyPrice == 0 && !plan.isCustom;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentPlan ? plan.color : Colors.grey[300]!,
          width: isCurrentPlan ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  plan.color.withOpacity(0.1),
                  plan.color.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              plan.name,
                              style: GoogleFonts.montserrat(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: plan.color,
                              ),
                            ),
                          ),
                          if (isCurrentPlan) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: plan.color,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Current',
                                style: GoogleFonts.montserrat(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (plan.subtitle != null &&
                          plan.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          plan.subtitle!,
                          style: GoogleFonts.montserrat(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  _getPlanIcon(plan.id),
                  size: 40,
                  color: plan.color,
                ),
              ],
            ),
          ),

          // Price & Credits (or Custom Plan Info)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (plan.isCustom) ...[
                  // Custom Plan UI
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: plan.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: plan.color.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.contact_support,
                          size: 48,
                          color: plan.color,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Custom Plan',
                          style: GoogleFonts.montserrat(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Contact us for a personalized plan tailored to your needs',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Regular Plan UI
                  // Discount Badge for Annual
                  if (!isFree && _isAnnual && plan.discountPercentage > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.green[300]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_offer,
                            size: 16,
                            color: Colors.green[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Save ${plan.discountPercentage.toStringAsFixed(0)}%',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isFree
                            ? 'Free'
                            : _isAnnual
                                ? '\$${plan.annualMonthlyPrice.toStringAsFixed(0)}'
                                : '\$${plan.monthlyPrice.toStringAsFixed(0)}',
                        style: GoogleFonts.montserrat(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (!isFree)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 6),
                          child: Text(
                            '/month',
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!isFree && _isAnnual) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Billed annually (\$${plan.annualPrice.toStringAsFixed(0)}/year)',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.stars,
                        size: 18,
                        color: plan.color,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isAnnual
                            ? '${plan.annualCredits} credits/year'
                            : '${plan.monthlyCredits} credits/month',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),
                // Benefits (with colored tick icons)
                if (plan.benefits.isNotEmpty) ...[
                  Text(
                    'What\'s Included:',
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...plan.benefits.map((benefit) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: plan.color.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check,
                                size: 16,
                                color: plan.color,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                benefit,
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  color: Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 8),
                ],
                // Features (HTML Description)
                if (plan.description.isNotEmpty) ...[
                  Text(
                    'Features:',
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Html(
                    data: plan.description,
                    style: {
                      "body": Style(
                        margin: Margins.zero,
                        padding: HtmlPaddings.zero,
                        fontSize: FontSize(14),
                        color: Colors.black87,
                      ),
                      "p": Style(
                        margin: Margins.only(bottom: 8),
                      ),
                      "ul": Style(
                        margin: Margins.only(left: 20, bottom: 8),
                      ),
                      "li": Style(
                        margin: Margins.only(bottom: 4),
                      ),
                      "h1": Style(
                        fontSize: FontSize(20),
                        fontWeight: FontWeight.bold,
                        margin: Margins.only(bottom: 12),
                      ),
                      "h2": Style(
                        fontSize: FontSize(18),
                        fontWeight: FontWeight.bold,
                        margin: Margins.only(bottom: 10),
                      ),
                      "h3": Style(
                        fontSize: FontSize(16),
                        fontWeight: FontWeight.bold,
                        margin: Margins.only(bottom: 8),
                      ),
                    },
                  ),
                ] else ...[
                  Text(
                    'Features:',
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No features listed',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (isCurrentPlan || _isSubscribing)
                        ? null
                        : () => _subscribeToPlan(plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isCurrentPlan ? Colors.grey[300] : plan.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: isCurrentPlan ? 0 : 4,
                    ),
                    child: _isSubscribing
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            isCurrentPlan
                                ? 'Current Plan'
                                : plan.isCustom
                                    ? (plan.actionButtonText ?? 'Contact Us')
                                    : isFree
                                        ? (plan.actionButtonText ??
                                            'Downgrade to Free')
                                        : (plan.actionButtonText ??
                                            'Subscribe to ${plan.name}'),
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopUpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top Up Balance',
            style: GoogleFonts.montserrat(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose a package to add credits to your account',
            style: GoogleFonts.montserrat(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),

          // Packages Grid
          if (_isLoadingPackages)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_packages.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No packages available',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please check back later or contact support',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.75, // Adjusted for better content fit
              ),
              itemCount: _packages.length,
              itemBuilder: (context, index) {
                final package = _packages[index];
                final isToppingUp =
                    _isToppingUp && _toppingUpPackageId == package.id;

                return _buildPackageCard(package, isToppingUp);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPackageCard(CreditPackage package, bool isToppingUp) {
    // Debug: Log package pricing info
    print('🔵 [PackageCard] Building card for: ${package.name}');
    print('   - Local Price: ${package.localPrice}');
    print('   - Currency Code: ${package.currencyCode}');
    print('   - USD Price: ${package.usdPrice}');
    print('   - Display Price: ${package.getDisplayPrice()}');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: package.isPopular
            ? LinearGradient(
                colors: [
                  Colors.orange[50]!,
                  Colors.orange[100]!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: package.isPopular ? null : Colors.white,
        boxShadow: [
          BoxShadow(
            color: package.isPopular
                ? Colors.orange.withOpacity(0.3)
                : Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
        border: Border.all(
          color: package.isPopular ? Colors.orange[300]! : Colors.grey[200]!,
          width: package.isPopular ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isToppingUp || !_isBillingAvailable
              ? null
              : () => _purchaseTopUp(package),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Package Name
                Flexible(
                  child: Text(
                    package.name,
                    style: GoogleFonts.montserrat(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Description
                if (package.description != null &&
                    package.description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Flexible(
                    child: Text(
                      package.description!,
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        color: Colors.grey[600],
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                const Spacer(),

                // Price and Credits Card - Separate Lines
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.green[50]!,
                        Colors.green[100]!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.green[200]!,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Price on separate line with full decimal display
                      Text(
                        package.getDisplayPrice(),
                        style: GoogleFonts.montserrat(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[900],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Credits on separate line
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green[700],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${package.credits}',
                              style: GoogleFonts.montserrat(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Credits',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                      // Show USD fallback if local currency is different
                      if (package.localPrice != null &&
                          package.currencyCode != null &&
                          package.currencyCode != 'USD') ...[
                        const SizedBox(height: 4),
                        Text(
                          '≈ \$${package.usdPrice.toStringAsFixed(2)} USD',
                          style: GoogleFonts.montserrat(
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Purchase Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isToppingUp || !_isBillingAvailable
                        ? null
                        : () => _purchaseTopUp(package),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: package.isPopular
                          ? Colors.orange[600]
                          : Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: package.isPopular ? 4 : 2,
                      shadowColor: package.isPopular
                          ? Colors.orange.withOpacity(0.4)
                          : Colors.green.withOpacity(0.3),
                    ),
                    child: isToppingUp
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shopping_cart_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Purchase',
                                style: GoogleFonts.montserrat(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Purchase top-up via Google Play with package
  Future<void> _purchaseTopUp(CreditPackage package) async {
    print('🔵 [TopUp] _purchaseTopUp called for package: ${package.name}');
    print('🔵 [TopUp] Package ID: ${package.id}');
    print('🔵 [TopUp] Product ID: ${package.productId}');
    print('🔵 [TopUp] Billing available: $_isBillingAvailable');

    // Check billing availability
    if (!_isBillingAvailable) {
      print('❌ [TopUp] Billing not available');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'In-app purchases are not available. Please check your device settings.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // Validate package
    if (package.productId.isEmpty) {
      print('❌ [TopUp] Package has no product ID');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This package is not configured for purchase'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    print('✅ [TopUp] Validation passed, setting loading state');
    setState(() {
      _isToppingUp = true;
      _toppingUpPackageId = package.id;
    });

    try {
      final productId = package.productId;

      print('🔵 [TopUp] Configuration:');
      print('   - Product ID: $productId');
      print('   - Package: ${package.name}');
      print('   - Price: \$${package.usdPrice}');
      print('   - Credits: ${package.credits}');

      // Query product details
      print('🔵 [TopUp] Querying product details for: $productId');
      ProductDetailsResponse productDetailsResponse;
      try {
        productDetailsResponse = await _billingService.getProductDetails(
          {productId},
          isSubscription: false,
        );
        print('✅ [TopUp] Product query successful');
        print(
            '   - Found ${productDetailsResponse.productDetails.length} product(s)');
        if (productDetailsResponse.error != null) {
          print(
              '⚠️ [TopUp] Product query error: ${productDetailsResponse.error}');
        }
      } catch (e, stackTrace) {
        print('❌ [TopUp] Error querying product: $e');
        print('❌ [TopUp] Stack trace: $stackTrace');
        if (mounted) {
          setState(() {
            _isToppingUp = false;
            _toppingUpPackageId = null;
          });
        }
        throw Exception(
            'Unable to connect to Google Play Store. Please check your internet connection and try again.');
      }

      if (productDetailsResponse.productDetails.isEmpty) {
        print('❌ [TopUp] No products found for ID: $productId');
        if (mounted) {
          setState(() {
            _isToppingUp = false;
            _toppingUpPackageId = null;
          });
        }

        final errorMsg = 'This package is not available for purchase.\n\n'
            'Product ID: $productId\n\n'
            'The package may not be synced with Google Play Console yet.\n\n'
            'Please contact support or try again later.';

        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Package Unavailable'),
              content: SingleChildScrollView(
                child: Text(errorMsg),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final productDetails = productDetailsResponse.productDetails.first;

      print('✅ [TopUp] Product details retrieved:');
      print('   - Product ID: ${productDetails.id}');
      print('   - Price: ${productDetails.price}');
      print('   - Title: ${productDetails.title}');

      // Get display price - prefer productDetails.price (local) over package price
      final displayPrice = productDetails.price.isNotEmpty
          ? productDetails.price
          : package.getDisplayPrice();

      print('🔵 [TopUp] Display price for confirmation: $displayPrice');

      // Show purchase confirmation
      print('🔵 [TopUp] Showing purchase confirmation dialog');
      final confirmPurchase = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Purchase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                package.name,
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (package.description != null &&
                  package.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(package.description!),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Price:'),
                  Text(
                    displayPrice,
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              // Show USD reference if local currency is different
              if (productDetails.price.isNotEmpty &&
                  !productDetails.price.startsWith('\$')) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox.shrink(),
                    Text(
                      '≈ \$${package.usdPrice.toStringAsFixed(2)} USD',
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Credits:'),
                  Text(
                    '${package.credits}',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Purchase'),
            ),
          ],
        ),
      );

      if (confirmPurchase != true) {
        print('⚠️ [TopUp] Purchase cancelled by user');
        setState(() {
          _isToppingUp = false;
          _toppingUpPackageId = null;
        });
        return;
      }

      // Initiate purchase
      print('🔵 [TopUp] Initiating purchase...');
      try {
        await _billingService.purchaseProduct(productDetails);
        print('✅ [TopUp] Purchase initiated successfully');
      } catch (e, stackTrace) {
        print('❌ [TopUp] Failed to initiate purchase: $e');
        print('❌ [TopUp] Stack trace: $stackTrace');
        throw Exception('Failed to start purchase: ${e.toString()}');
      }

      // Wait for purchase completion
      print('🔵 [TopUp] Waiting for purchase completion (timeout: 120s)...');
      PurchaseDetails? purchaseDetails;
      try {
        purchaseDetails = await _billingService.waitForPurchase(
          productId,
          timeout: const Duration(seconds: 120),
        );
        print('✅ [TopUp] Purchase details received');
      } catch (e, stackTrace) {
        print('❌ [TopUp] Error waiting for purchase: $e');
        print('❌ [TopUp] Stack trace: $stackTrace');

        // Reset loading state immediately
        if (mounted) {
          setState(() {
            _isToppingUp = false;
            _toppingUpPackageId = null;
          });
        }

        // Check if it's a cancellation
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('cancelled') ||
            errorString.contains('canceled') ||
            errorString.contains('user_canceled')) {
          print('ℹ️ [TopUp] User cancelled the purchase');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Purchase was cancelled. No charges were made.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return; // Exit early, state already reset
        }

        String errorMessage = e.toString();
        if (errorMessage.contains('item_unavailable') ||
            errorMessage.contains('not available') ||
            errorMessage.contains('could not be found')) {
          errorMessage = 'The product is not available for purchase.\n\n'
              'Common causes:\n'
              '• App not installed from Google Play test track\n'
              '• Product not active in Google Play Console\n'
              '• Test account not properly set up\n'
              '• Wait 1-2 hours after product creation\n\n'
              'Product ID: $productId';
        }

        throw Exception(errorMessage);
      }

      // Check if purchase details is null (shouldn't happen after try-catch, but safety check)
      if (purchaseDetails == null) {
        print('❌ [TopUp] Purchase details is null - cancelled or timed out');
        if (mounted) {
          setState(() {
            _isToppingUp = false;
            _toppingUpPackageId = null;
          });
        }
        throw Exception('Purchase was cancelled or timed out');
      }

      print('🔵 [TopUp] Purchase status: ${purchaseDetails.status}');
      if (purchaseDetails.status != PurchaseStatus.purchased) {
        print(
            '❌ [TopUp] Purchase not successful. Status: ${purchaseDetails.status}');
        if (purchaseDetails.error != null) {
          print('❌ [TopUp] Error details: ${purchaseDetails.error}');
        }

        // Reset loading state immediately
        if (mounted) {
          setState(() {
            _isToppingUp = false;
            _toppingUpPackageId = null;
          });
        }

        // Handle cancellation status
        if (purchaseDetails.status == PurchaseStatus.canceled) {
          print('ℹ️ [TopUp] Purchase was cancelled');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Purchase was cancelled. No charges were made.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return; // Exit early, state already reset
        }

        String errorMsg = purchaseDetails.error?.message ?? 'Unknown error';
        if (errorMsg.contains('item_unavailable') ||
            errorMsg.contains('not available') ||
            errorMsg.contains('could not be found')) {
          errorMsg =
              'The product is not available for purchase. Please ensure:\n'
              '1. App is installed from Google Play test track\n'
              '2. Product is active in Google Play Console\n'
              '3. Test account is properly configured\n'
              '4. Wait 1-2 hours after product creation';
        }

        throw Exception('Purchase failed: $errorMsg');
      }

      // Get purchase token
      final purchaseToken = _billingService.getPurchaseToken(purchaseDetails);
      if (purchaseToken == null) {
        throw Exception('Failed to get purchase token');
      }

      // Verify purchase with backend
      print('🔵 [TopUp] Verifying purchase with backend...');
      print('   - Purchase token: ${purchaseToken.substring(0, 20)}...');
      print('   - Product ID: $productId');
      print('   - Package ID: ${package.id}');

      Map<String, dynamic> result;
      try {
        result = await _topUpService.verifyGooglePlayTopUp(
          purchaseToken: purchaseToken,
          productId: productId,
          packageId: package.id,
        );
        print('✅ [TopUp] Backend verification response received');
        print('   - Success: ${result['success']}');
        print('   - Message: ${result['message']}');
      } catch (e, stackTrace) {
        print('❌ [TopUp] Backend verification error: $e');
        print('❌ [TopUp] Stack trace: $stackTrace');
        throw Exception('Backend verification failed: ${e.toString()}');
      }

      if (mounted) {
        if (result['success'] == true) {
          print('✅ [TopUp] Top-up successful!');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Top-up successful!'),
              backgroundColor: Colors.green,
            ),
          );

          // Refresh balance and packages
          await _fetchBalance();
          await _fetchPackages();

          // Refresh AuthProvider profile to update bottom bar balance
          try {
            final authProvider =
                Provider.of<AuthProvider>(context, listen: false);
            await authProvider.fetchProfile();
            print('✅ [TopUp] AuthProvider profile refreshed');
          } catch (e) {
            print('⚠️ [TopUp] Failed to refresh AuthProvider: $e');
          }

          await Future.delayed(const Duration(seconds: 1));

          if (mounted) {
            Navigator.of(context).pop();
          }
        } else {
          throw Exception(result['message'] ?? 'Top-up verification failed');
        }
      }
    } catch (e, stackTrace) {
      print('❌ [TopUp] Top-up error caught: $e');
      print('❌ [TopUp] Error type: ${e.runtimeType}');
      print('❌ [TopUp] Stack trace: $stackTrace');

      // Ensure loading state is reset even if there was an error
      if (mounted) {
        setState(() {
          _isToppingUp = false;
          _toppingUpPackageId = null;
        });

        // Only show error snackbar if it's not a cancellation (already handled)
        final errorString = e.toString().toLowerCase();
        if (!errorString.contains('cancelled') &&
            !errorString.contains('canceled')) {
          String errorMessage = e.toString().replaceAll('Exception: ', '');
          if (errorMessage.isEmpty) {
            errorMessage = 'An unexpected error occurred. Please try again.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } finally {
      // Final safety check - ensure state is always reset
      print('🔵 [TopUp] Cleaning up - resetting loading state');
      if (mounted) {
        if (_isToppingUp) {
          print(
              '⚠️ [TopUp] Loading state still true in finally block, resetting...');
        }
        setState(() {
          _isToppingUp = false;
          _toppingUpPackageId = null;
        });
      }
    }
  }

  IconData _getPlanIcon(String planId) {
    // Try to find the plan in the fetched plans
    try {
      final plan = _plans.firstWhere((p) => p.id == planId);
      final planName = plan.name.toLowerCase();

      if (planName.contains('free')) {
        return Icons.free_breakfast;
      } else if (planName.contains('standard') || planName.contains('basic')) {
        return Icons.star;
      } else if (planName.contains('premium') || planName.contains('pro')) {
        return Icons.diamond;
      } else if (planName.contains('custom')) {
        return Icons.contact_support;
      }
    } catch (e) {
      // Plan not found in fetched plans, use default logic
      if (planId == 'free') {
        return Icons.free_breakfast;
      } else if (planId == 'standard') {
        return Icons.star;
      } else if (planId == 'premium') {
        return Icons.diamond;
      }
    }

    return Icons.workspace_premium;
  }
}
