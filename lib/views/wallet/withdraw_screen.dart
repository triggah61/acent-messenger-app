import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../models/wallet.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/qr_scanner_screen.dart';

class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({Key? key}) : super(key: key);

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  NetworkFeeType _selectedFeeType = NetworkFeeType.medium;
  bool _isLoading = false;
  final NumberFormat _btcFormat = NumberFormat('#,##0.00000000', 'en_US');
  
  // Debouncing for fee estimation
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().fetchNetworkFees();
    });
    
    // Listen to amount changes for fee estimation
    _amountController.addListener(_onAmountChanged);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121829),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Withdraw Bitcoin',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: Consumer<WalletProvider>(
                  builder: (context, walletProvider, child) {
                    final wallet = walletProvider.wallet;
                    if (wallet == null) {
                      return const Center(
                        child: Text(
                          'Wallet not available',
                          style: TextStyle(color: Colors.black87),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            _buildBalanceCard(wallet),
                            const SizedBox(height: 24),
                            _buildAmountSection(wallet),
                            const SizedBox(height: 24),
                            _buildNetworkFeeSection(walletProvider),
                            const SizedBox(height: 24),
                            _buildAddressSection(),
                            const SizedBox(height: 24),
                            _buildDescriptionSection(),
                            const SizedBox(height: 24),
                            _buildSummaryCard(wallet, walletProvider),
                            const SizedBox(height: 24),
                            _buildWithdrawButton(walletProvider),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(Wallet wallet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blueAccent, Colors.purpleAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Balance',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_btcFormat.format(wallet.btcBalance)} BTC',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountSection(Wallet wallet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Amount to Withdraw',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: '0.00000000',
              hintStyle: TextStyle(color: Colors.grey[400]),
              suffixText: 'BTC',
              suffixStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: Colors.white,
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
                borderSide: const BorderSide(color: Colors.blueAccent),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter an amount';
              }
              final amount = double.tryParse(value);
              if (amount == null || amount <= 0) {
                return 'Please enter a valid amount';
              }
              
              // Calculate total cost including both fees
              final selectedFee = context.read<WalletProvider>().getFeeByType(_selectedFeeType);
              final totalCost = amount + (selectedFee?.totalBtcFee ?? 0.0);
              
              if (totalCost > wallet.btcBalance) {
                return 'Insufficient balance (including fees)';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          // Row(
          //   children: [
          //     TextButton(
          //       onPressed: () => _setMaxAmount(wallet.btcBalance),
          //       child: const Text(
          //         'Max',
          //         style: TextStyle(color: Colors.blueAccent),
          //       ),
          //     ),
          //     const SizedBox(width: 16),
          //     TextButton(
          //       onPressed: () => _setPercentageAmount(wallet.btcBalance, 0.25),
          //       child: const Text(
          //         '25%',
          //         style: TextStyle(color: Colors.blueAccent),
          //       ),
          //     ),
          //     const SizedBox(width: 16),
          //     TextButton(
          //       onPressed: () => _setPercentageAmount(wallet.btcBalance, 0.5),
          //       child: const Text(
          //         '50%',
          //         style: TextStyle(color: Colors.blueAccent),
          //       ),
          //     ),
          //     const SizedBox(width: 16),
          //     TextButton(
          //       onPressed: () => _setPercentageAmount(wallet.btcBalance, 0.75),
          //       child: const Text(
          //         '75%',
          //         style: TextStyle(color: Colors.blueAccent),
          //       ),
          //     ),
          //   ],
          // ),
        ],
      ),
    );
  }

  Widget _buildNetworkFeeSection(WalletProvider walletProvider) {
    final fees = walletProvider.estimatedFees;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Network Fee',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (walletProvider.isLoadingFees) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  ),
                ),
              ],
            ],
          ),
          if (walletProvider.feeError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Error loading fees: ${walletProvider.feeError}',
              style: TextStyle(
                color: Colors.red[600],
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          ...fees.map((fee) => _buildFeeOption(fee)),
        ],
      ),
    );
  }

  Widget _buildFeeOption(NetworkFee fee) {
    final isSelected = _selectedFeeType == fee.type;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFeeType = fee.type;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.blueAccent : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blueAccent,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getFeeTypeTitle(fee.type),
                        style: TextStyle(
                          color: isSelected ? Colors.black87 : Colors.grey[700],
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${_btcFormat.format(fee.totalBtcFee)} BTC',
                            style: TextStyle(
                              color: isSelected ? Colors.black87 : Colors.grey[700],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Network: ${_btcFormat.format(fee.networkFee.btc)} BTC',
                            style: TextStyle(
                              color: isSelected ? Colors.grey[600] : Colors.grey[500],
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            'Platform: ${_btcFormat.format(fee.platformFee.btc)} BTC',
                            style: TextStyle(
                              color: isSelected ? Colors.grey[600] : Colors.grey[500],
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fee.description,
                    style: TextStyle(
                      color: isSelected ? Colors.grey[600] : Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Destination Address',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _addressController,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: 'Enter Bitcoin address (e.g., 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa)',
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.white,
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
                borderSide: const BorderSide(color: Colors.blueAccent),
              ),
              contentPadding: const EdgeInsets.all(16),
              suffixIcon: IconButton(
                icon: Icon(Icons.qr_code_scanner, color: Colors.grey[600]),
                onPressed: () {
                  _openQRScanner(context);
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a destination address';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Description (Optional)',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            style: const TextStyle(color: Colors.black87),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add a note for this transaction...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true,
              fillColor: Colors.white,
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
                borderSide: const BorderSide(color: Colors.blueAccent),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(Wallet wallet, WalletProvider walletProvider) {
    final amount = double.tryParse(_amountController.text) ?? 0.0;
    final selectedFee = walletProvider.getFeeByType(_selectedFeeType);
    
    if (selectedFee == null) {
      return const SizedBox.shrink();
    }
    
    final networkFee = selectedFee.networkFee.btc;
    final platformFee = selectedFee.platformFee.btc;
    final totalFees = selectedFee.totalBtcFee;
    final total = amount + totalFees;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transaction Summary',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _buildSummaryRow('Amount', '${_btcFormat.format(amount)} BTC'),
          _buildSummaryRow('Platform Fee', '${_btcFormat.format(platformFee)} BTC'),
          _buildSummaryRow('Network Fee', '${_btcFormat.format(networkFee)} BTC'),
          Divider(color: Colors.grey[300]),
          _buildSummaryRow('Total to Deduct', '${_btcFormat.format(total)} BTC', isTotal: true),
          const SizedBox(height: 8),
          Text(
            'Remaining Balance: ${_btcFormat.format(wallet.btcBalance - total)} BTC',
            style: TextStyle(
              color: total > wallet.btcBalance ? Colors.red : Colors.grey[600],
              fontSize: 12,
              fontWeight: total > wallet.btcBalance ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (total > wallet.btcBalance)
            const SizedBox(height: 4),
          if (total > wallet.btcBalance)
            const Text(
              'Insufficient balance',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isTotal ? Colors.black87 : Colors.grey[700],
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isTotal ? Colors.black87 : Colors.grey[700],
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWithdrawButton(WalletProvider walletProvider) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading || walletProvider.isLoading ? null : _handleWithdraw,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading || walletProvider.isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Confirm Withdrawal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  String _getFeeTypeTitle(NetworkFeeType type) {
    switch (type) {
      case NetworkFeeType.low:
        return 'Low';
      case NetworkFeeType.medium:
        return 'Standard';
      case NetworkFeeType.high:
        return 'Fast';
    }
  }

  Future<void> _handleWithdraw() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final amount = double.parse(_amountController.text);
      final address = _addressController.text.trim();
      final description = _descriptionController.text.trim();

      // Show confirmation dialog
      final confirmed = await _showConfirmationDialog(amount, address);
      
      if (confirmed == true) {
        final success = await context.read<WalletProvider>().createWithdrawal(
          amount: amount,
          toAddress: address,
          feeType: _selectedFeeType,
          description: description.isNotEmpty ? description : null,
        );

        if (success) {
          if (mounted) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Withdrawal Submitted!',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your Bitcoin withdrawal of ${_btcFormat.format(amount)} BTC has been submitted successfully.',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green[600],
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                duration: const Duration(seconds: 5),
                margin: const EdgeInsets.all(16),
                action: SnackBarAction(
                  label: 'View History',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ),
            );
            
            // Navigate back to wallet screen (which will auto-refresh)
            Navigator.pop(context);
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.read<WalletProvider>().error ?? 'Withdrawal failed',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        // Extract the actual error message from the exception
        String errorMessage = e.toString();
        if (errorMessage.startsWith('Exception: ')) {
          errorMessage = errorMessage.substring(11); // Remove 'Exception: ' prefix
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Withdrawal Failed',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        errorMessage,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 6),
            margin: const EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool?> _showConfirmationDialog(double amount, String address) {
    final selectedFee = context.read<WalletProvider>().getFeeByType(_selectedFeeType);
    
    if (selectedFee == null) {
      return Future.value(false);
    }
    
    final platformFee = selectedFee.platformFee.btc;
    final networkFee = selectedFee.networkFee.btc;
    final totalCost = amount + selectedFee.totalBtcFee;
    final description = _descriptionController.text.trim();

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 24),
            SizedBox(width: 8),
            Text(
              'Confirm Withdrawal',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConfirmationRow('Amount:', '${_btcFormat.format(amount)} BTC'),
                  const SizedBox(height: 8),
                  _buildConfirmationRow('Platform Fee:', '${_btcFormat.format(platformFee)} BTC'),
                  const SizedBox(height: 8),
                  _buildConfirmationRow('Network Fee:', '${_btcFormat.format(networkFee)} BTC'),
                  const SizedBox(height: 8),
                  _buildConfirmationRow('Priority:', _getFeeTypeTitle(_selectedFeeType)),
                  const Divider(),
                  _buildConfirmationRow(
                    'Total Cost:',
                    '${_btcFormat.format(totalCost)} BTC',
                    isTotal: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Destination:',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                address,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Description:',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This transaction cannot be reversed. Please verify the address carefully.',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
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
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Confirm Withdrawal',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isTotal ? Colors.black87 : Colors.grey[700],
            fontSize: isTotal ? 14 : 13,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: isTotal ? Colors.black87 : Colors.grey[700],
            fontSize: isTotal ? 14 : 13,
            fontWeight: isTotal ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _onAmountChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      final amount = double.tryParse(_amountController.text);
      if (amount != null && amount > 0) {
        context.read<WalletProvider>().estimateFeesForAmount(amount);
      } else {
        context.read<WalletProvider>().clearFeeEstimation();
      }
    });
  }

  void _openQRScanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QRScannerScreen(),
      ),
    ).then((result) {
      if (result != null && result is String) {
        _addressController.text = result;
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Bitcoin address scanned successfully!'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
} 