import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/subscription_plan.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
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
  final TextEditingController _topUpAmountController = TextEditingController();
  double _topUpAmount = 0.0;

  // API-related state
  List<SubscriptionPlan> _plans = [];
  bool _isLoadingPlans = true;
  String? _errorMessage;
  bool _isSubscribing = false;
  late SubscriptionService _subscriptionService;
  
  // Profile and balance state
  double _totalBalance = 0.0;
  double _topUpBalance = 0.0;
  double _subscriptionBalance = 0.0;
  String? _currentPlanId;
  bool _isLoadingBalance = true;

  @override
  void initState() {
    super.initState();
    _topUpAmountController.addListener(_onTopUpAmountChanged);
    
    // Initialize subscription service
    final authService = Provider.of<AuthService>(context, listen: false);
    _subscriptionService = SubscriptionService(authService);
    
    // Fetch plans and balance from API
    _fetchPlans();
    _fetchBalance();
  }

  @override
  void dispose() {
    _topUpAmountController.removeListener(_onTopUpAmountChanged);
    _topUpAmountController.dispose();
    super.dispose();
  }

  void _onTopUpAmountChanged() {
    final value = double.tryParse(_topUpAmountController.text) ?? 0.0;
    setState(() {
      _topUpAmount = value;
    });
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
            _totalBalance = (profileData['balance']?['totalBalance'] as num?)?.toDouble() ?? 0.0;
            _topUpBalance = (profileData['balance']?['topUpBalance'] as num?)?.toDouble() ?? 0.0;
            _subscriptionBalance = (profileData['balance']?['subscriptionBalance'] as num?)?.toDouble() ?? 0.0;
            _currentPlanId = profileData['subscription']?['currentPlan']?['_id']?.toString();
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

  /// Subscribe to a plan
  Future<void> _subscribeToPlan(SubscriptionPlan plan) async {
    // Handle custom plans
    if (plan.isCustom) {
      if (plan.contactFormLink != null && plan.contactFormLink!.isNotEmpty) {
        final uri = Uri.parse(plan.contactFormLink!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not open contact form link'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
      return;
    }

    setState(() {
      _isSubscribing = true;
    });

    try {
      final intervalType = _isAnnual ? 'year' : 'month';
      final result = await _subscriptionService.subscribeToPlan(
        planId: plan.id,
        intervalType: intervalType,
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Successfully subscribed!'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Refresh plans and balance
          await _fetchPlans();
          await _fetchBalance();
          await Future.delayed(const Duration(seconds: 1));
          
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubscribing = false;
        });
      }
    }
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
            child: _selectedTabIndex == 0
                ? _buildPlansTab()
                : _buildTopUpTab(),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
      print('SubscriptionModal: Building card for plan: ${plan.name} (${plan.id})');
      try {
        final card = _buildPlanCard(plan);
        children.add(card);
        print('SubscriptionModal: Successfully added card for ${plan.name}');
      } catch (e, stackTrace) {
        print('SubscriptionModal: Error building plan card for plan ${plan.id}: $e');
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

    print('SubscriptionModal: Returning ListView with ${children.length} children');
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
                      fontWeight: !_isAnnual ? FontWeight.w600 : FontWeight.w500,
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
    
    final isCurrentPlan = plan.id == _currentPlanId || plan.id == widget.currentSubscription.planId;
    final isFree = plan.monthlyPrice == 0 && !plan.isCustom;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentPlan
              ? plan.color
              : Colors.grey[300]!,
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
                      if (plan.subtitle != null && plan.subtitle!.isNotEmpty) ...[
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      backgroundColor: isCurrentPlan
                          ? Colors.grey[300]
                          : plan.color,
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
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            isCurrentPlan
                                ? 'Current Plan'
                                : plan.isCustom
                                    ? plan.actionButtonText ?? 'Contact Us'
                                    : isFree
                                        ? 'Downgrade to Free'
                                        : 'Subscribe to ${plan.name}',
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
    final credits = CreditConverter.usdToCredits(_topUpAmount);

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
            'Add credits to your account anytime',
            style: GoogleFonts.montserrat(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),

          // Current Balance
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.blue[200]!,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Balance',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLoadingBalance
                          ? 'Loading...'
                          : '${_totalBalance.toStringAsFixed(0)} Credits',
                      style: GoogleFonts.montserrat(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[900],
                      ),
                    ),
                  ],
                ),
                Icon(
                  Icons.account_balance_wallet,
                  size: 40,
                  color: Colors.blue[700],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // USD Input
          Text(
            'Amount (USD)',
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _topUpAmountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'Enter amount in USD',
              prefixIcon: const Icon(Icons.attach_money),
              prefixText: '\$ ',
              prefixStyle: GoogleFonts.montserrat(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
              ),
              filled: true,
              fillColor: Colors.grey[50],
            ),
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 24),

          // Quick Amount Buttons
          Text(
            'Quick Amount',
            style: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [10, 25, 50, 100].map((amount) {
              return GestureDetector(
                onTap: () {
                  _topUpAmountController.text = amount.toStringAsFixed(0);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey[300]!,
                    ),
                  ),
                  child: Text(
                    '\$$amount',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 32),

          // Credit Conversion Display
          if (_topUpAmount > 0) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green[50]!,
                    Colors.green[100]!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.green[300]!,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'You will receive:',
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      Text(
                        '${credits.toStringAsFixed(0)} Credits',
                        style: GoogleFonts.montserrat(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: Colors.green[300]),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.green[700],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '1 USD = ${CreditConverter.creditsPerUsd.toStringAsFixed(0)} Credits',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Top Up Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _topUpAmount > 0
                  ? () {
                      // TODO: Handle top-up
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Top up \$${_topUpAmount.toStringAsFixed(2)} for ${credits.toStringAsFixed(0)} credits',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: Text(
                'Top Up Balance',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

