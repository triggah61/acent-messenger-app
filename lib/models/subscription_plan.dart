import 'package:flutter/material.dart';

/// Subscription Plan Model
/// Defines the structure for subscription plans (Free, Standard, Premium)
class SubscriptionPlan {
  final String id;
  final String name;
  final double monthlyPrice; // USD per month
  final double annualPrice; // USD per year (total)
  final int monthlyCredits; // Credits per month
  final int annualCredits; // Credits per year (total)
  final List<String> features; // List of features available in this plan (deprecated - use description HTML)
  final List<String> benefits; // List of benefits to display with checkmarks
  final String description; // HTML description from rich text editor
  final String? subtitle; // Subtitle to show under the plan name
  final Color color; // Color theme for the plan
  final bool isCustom; // Whether this is a custom plan
  final String? contactFormLink; // Contact form link for custom plans
  final String? actionButtonText; // Custom action button text
  // Google Play Billing product IDs (not exposed to client, used internally)
  final String? googlePlayMonthlySubscriptionId;
  final String? googlePlayAnnualSubscriptionId;
  final String? googlePlaySandboxMonthlySubscriptionId;
  final String? googlePlaySandboxAnnualSubscriptionId;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.monthlyPrice,
    required this.annualPrice,
    required this.monthlyCredits,
    required this.annualCredits,
    required this.features,
    required this.benefits,
    required this.description,
    required this.color,
    this.subtitle,
    this.isCustom = false,
    this.contactFormLink,
    this.actionButtonText,
    this.googlePlayMonthlySubscriptionId,
    this.googlePlayAnnualSubscriptionId,
    this.googlePlaySandboxMonthlySubscriptionId,
    this.googlePlaySandboxAnnualSubscriptionId,
  });

  /// Get monthly equivalent price for annual plan
  double get annualMonthlyPrice => annualPrice / 12;

  /// Calculate discount percentage when choosing annual over monthly
  double get discountPercentage {
    if (monthlyPrice == 0 || isCustom) return 0;
    final annualMonthly = annualMonthlyPrice;
    return ((monthlyPrice - annualMonthly) / monthlyPrice) * 100;
  }

  /// Create SubscriptionPlan from JSON (API response)
  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    print('SubscriptionPlan.fromJson: Parsing plan with keys: ${json.keys}');
    
    // Parse color from hex string
    Color parseColor(String? colorHex) {
      if (colorHex == null || colorHex.isEmpty) {
        return const Color(0xFF2196F3); // Default blue
      }
      try {
        // Remove # if present
        String hex = colorHex.replaceAll('#', '');
        // Handle 6-digit hex
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        }
        // Handle 8-digit hex (with alpha)
        if (hex.length == 8) {
          return Color(int.parse(hex, radix: 16));
        }
        return const Color(0xFF2196F3);
      } catch (e) {
        print('SubscriptionPlan.fromJson: Error parsing color $colorHex: $e');
        return const Color(0xFF2196F3);
      }
    }

    // Calculate annual price from annualMonthlyPrice
    final annualMonthlyPrice = (json['annualMonthlyPrice'] as num?)?.toDouble() ?? 0.0;
    final annualPrice = annualMonthlyPrice * 12;

    // Calculate annual credits from annualMonthlyCredit
    final annualMonthlyCredit = (json['annualMonthlyCredit'] as num?)?.toInt() ?? 0;
    final annualCredits = annualMonthlyCredit * 12;

    // Ensure id is never empty - handle MongoDB ObjectId conversion
    String? planId;
    final idValue = json['_id'];
    print('SubscriptionPlan.fromJson: _id value: $idValue (type: ${idValue.runtimeType})');
    
    if (idValue != null) {
      // Handle MongoDB ObjectId (can be Map with $oid or direct string)
      if (idValue is Map) {
        planId = idValue['\$oid']?.toString() ?? idValue['_id']?.toString();
        print('SubscriptionPlan.fromJson: Extracted ID from Map: $planId');
      } else {
        planId = idValue.toString();
        print('SubscriptionPlan.fromJson: Converted ID to string: $planId');
      }
    }
    planId ??= json['id']?.toString();
    
    if (planId == null || planId.isEmpty) {
      print('SubscriptionPlan.fromJson: ERROR - No valid ID found!');
      throw Exception('Subscription plan must have a valid _id or id field. Received: $idValue');
    }
    
    print('SubscriptionPlan.fromJson: Successfully parsed plan ID: $planId');

    // Parse benefits array
    List<String> parseBenefits(dynamic benefitsJson) {
      if (benefitsJson == null) return [];
      if (benefitsJson is List) {
        return benefitsJson.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    return SubscriptionPlan(
      id: planId,
      name: json['name']?.toString() ?? 'Unknown Plan',
      monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0.0,
      annualPrice: annualPrice,
      monthlyCredits: (json['monthlyCredit'] as num?)?.toInt() ?? 0,
      annualCredits: annualCredits,
      features: [], // Features are now in the HTML description
      benefits: parseBenefits(json['benefits']),
      description: json['description']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      color: parseColor(json['color']?.toString()),
      isCustom: json['isCustom'] == true || json['isCustom'] == 'true',
      contactFormLink: json['contactFormLink']?.toString(),
      actionButtonText: json['actionButtonText']?.toString(),
      googlePlayMonthlySubscriptionId: json['googlePlayMonthlySubscriptionId']?.toString(),
      googlePlayAnnualSubscriptionId: json['googlePlayAnnualSubscriptionId']?.toString(),
      googlePlaySandboxMonthlySubscriptionId: json['googlePlaySandboxMonthlySubscriptionId']?.toString(),
      googlePlaySandboxAnnualSubscriptionId: json['googlePlaySandboxAnnualSubscriptionId']?.toString(),
    );
  }

  /// Convert SubscriptionPlan to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'monthlyPrice': monthlyPrice,
      'annualPrice': annualPrice,
      'monthlyCredits': monthlyCredits,
      'annualCredits': annualCredits,
      'features': features,
      'description': description,
      'color': '#${color.value.toRadixString(16).substring(2)}',
      'isCustom': isCustom,
      'contactFormLink': contactFormLink,
      'actionButtonText': actionButtonText,
    };
  }
}

/// Predefined subscription plans
class SubscriptionPlans {
  static const free = SubscriptionPlan(
    id: 'free',
    name: 'Free',
    monthlyPrice: 0.0,
    annualPrice: 0.0,
    monthlyCredits: 100, // Example: 100 credits per month
    annualCredits: 1200, // Example: 1200 credits per year
    features: [
      'Basic translation features',
      'Limited translation minutes',
      'Standard support',
    ],
    benefits: [
      'Basic translation features',
      'Limited translation minutes',
      'Standard support',
    ],
    description: 'Perfect for occasional use',
    color: Color(0xFF9E9E9E), // Grey
    isCustom: false,
  );

  static const standard = SubscriptionPlan(
    id: 'standard',
    name: 'Standard',
    monthlyPrice: 15.0,
    annualPrice: 144.0, // $12/month * 12 = $144/year
    monthlyCredits: 1000, // Example: 1000 credits per month
    annualCredits: 12000, // Example: 12000 credits per year
    features: [
      'All basic features',
      'Extended translation minutes',
      'Priority support',
      'Advanced translation options',
    ],
    benefits: [
      'All basic features',
      'Extended translation minutes',
      'Priority support',
      'Advanced translation options',
    ],
    description: 'Best for regular users',
    color: Color(0xFF2196F3), // Blue
    isCustom: false,
  );

  static const premium = SubscriptionPlan(
    id: 'premium',
    name: 'Premium',
    monthlyPrice: 25.0,
    annualPrice: 240.0, // $20/month * 12 = $240/year
    monthlyCredits: 2500, // Example: 2500 credits per month
    annualCredits: 30000, // Example: 30000 credits per year
    features: [
      'All standard features',
      'Unlimited translation minutes',
      '24/7 priority support',
      'Advanced translation options',
      'Premium features access',
      'Early access to new features',
    ],
    benefits: [
      'All standard features',
      'Unlimited translation minutes',
      '24/7 priority support',
      'Advanced translation options',
      'Premium features access',
      'Early access to new features',
    ],
    description: 'For power users and professionals',
    color: Color(0xFFFF9800), // Orange
    isCustom: false,
  );

  static List<SubscriptionPlan> get all => [free, standard, premium];

  static SubscriptionPlan getById(String id) {
    return all.firstWhere(
      (plan) => plan.id == id,
      orElse: () => free,
    );
  }
}

/// User Subscription Model
/// Represents the current user's subscription status
class UserSubscription {
  final String planId;
  final double creditBalance;
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;
  final bool isActive;

  const UserSubscription({
    required this.planId,
    required this.creditBalance,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
    this.isActive = true,
  });

  SubscriptionPlan get plan => SubscriptionPlans.getById(planId);

  /// Get remaining days in current subscription period
  int? get remainingDays {
    if (subscriptionEndDate == null) return null;
    final now = DateTime.now();
    if (subscriptionEndDate!.isBefore(now)) return 0;
    return subscriptionEndDate!.difference(now).inDays;
  }
}

/// Credit conversion rate
/// 1 USD = X credits (configurable)
class CreditConverter {
  static const double creditsPerUsd = 100.0; // 1 USD = 100 credits

  static double usdToCredits(double usd) {
    return usd * creditsPerUsd;
  }

  static double creditsToUsd(double credits) {
    return credits / creditsPerUsd;
  }
}

