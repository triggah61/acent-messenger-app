import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/wallet.dart';
import '../../providers/wallet_provider.dart';

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
  
  NetworkFeeType _selectedFeeType = NetworkFeeType.standard;
  bool _isLoading = false;
  final NumberFormat _btcFormat = NumberFormat('#,##0.00000000', 'en_US');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().fetchNetworkFees();
    });
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
              final platformFee = wallet.calculatePlatformFee(amount);
              final networkFee = context.read<WalletProvider>().networkFees
                  .firstWhere((fee) => fee.type == _selectedFeeType, 
                      orElse: () => NetworkFee(
                        type: NetworkFeeType.standard,
                        fee: 0.00003,
                        description: 'Standard',
                        estimatedTime: 20,
                      )).fee;
              final totalCost = amount + platformFee + networkFee;
              
              if (totalCost > wallet.btcBalance) {
                return 'Insufficient balance (including fees)';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => _setMaxAmount(wallet.btcBalance),
                child: const Text(
                  'Max',
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => _setPercentageAmount(wallet.btcBalance, 0.25),
                child: const Text(
                  '25%',
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => _setPercentageAmount(wallet.btcBalance, 0.5),
                child: const Text(
                  '50%',
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => _setPercentageAmount(wallet.btcBalance, 0.75),
                child: const Text(
                  '75%',
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkFeeSection(WalletProvider walletProvider) {
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
            'Network Fee',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ...walletProvider.networkFees.map((fee) => _buildFeeOption(fee)),
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
                      Text(
                        '${_btcFormat.format(fee.fee)} BTC',
                        style: TextStyle(
                          color: isSelected ? Colors.black87 : Colors.grey[700],
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
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
                  // QR scanner functionality can be added here
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('QR Scanner not implemented'),
                    ),
                  );
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a destination address';
              }
              if (value.length < 26 || value.length > 35) {
                return 'Please enter a valid Bitcoin address';
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
    final selectedFee = walletProvider.networkFees
        .firstWhere((fee) => fee.type == _selectedFeeType, orElse: () => NetworkFee(
          type: NetworkFeeType.standard,
          fee: 0.00003,
          description: 'Standard',
          estimatedTime: 20,
        ));
    
    // Calculate platform fee based on wallet's platform fee percentage
    final platformFee = wallet.calculatePlatformFee(amount);
    final networkFee = selectedFee.fee;
    final totalFees = platformFee + networkFee;
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
          _buildSummaryRow('Platform Fee (${wallet.platformFeePercentage}%)', '${_btcFormat.format(platformFee)} BTC'),
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
      case NetworkFeeType.slow:
        return 'Slow';
      case NetworkFeeType.standard:
        return 'Standard';
      case NetworkFeeType.fast:
        return 'Fast';
    }
  }

  void _setMaxAmount(double maxAmount) {
    // Calculate the maximum withdrawable amount considering both fees
    final networkFee = context.read<WalletProvider>().networkFees
        .firstWhere((fee) => fee.type == _selectedFeeType, 
            orElse: () => NetworkFee(
              type: NetworkFeeType.standard,
              fee: 0.00003,
              description: 'Standard',
              estimatedTime: 20,
            )).fee;
            
    // Use an iterative approach to find the max amount considering platform fee
    double maxWithdrawable = 0.0;
    double testAmount = maxAmount;
    
    for (int i = 0; i < 10; i++) { // Limit iterations to prevent infinite loop
      final platformFee = testAmount * (context.read<WalletProvider>().wallet?.platformFeePercentage ?? 1.0) / 100;
      final totalCost = testAmount + platformFee + networkFee;
      
      if (totalCost <= maxAmount) {
        maxWithdrawable = testAmount;
        break;
      }
      testAmount = testAmount * 0.95; // Reduce by 5% each iteration
    }
    
    if (maxWithdrawable > 0) {
      _amountController.text = _btcFormat.format(maxWithdrawable);
    }
  }

  void _setPercentageAmount(double balance, double percentage) {
    final amount = balance * percentage;
    _amountController.text = _btcFormat.format(amount);
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Withdrawal initiated successfully'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.read<WalletProvider>().error ?? 'Withdrawal failed',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
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
    final wallet = context.read<WalletProvider>().wallet!;
    final platformFee = wallet.calculatePlatformFee(amount);
    final networkFee = context.read<WalletProvider>().networkFees
        .firstWhere((fee) => fee.type == _selectedFeeType, 
            orElse: () => NetworkFee(
              type: NetworkFeeType.standard,
              fee: 0.00003,
              description: 'Standard',
              estimatedTime: 20,
            )).fee;
    final totalCost = amount + platformFee + networkFee;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Confirm Withdrawal',
          style: TextStyle(color: Colors.black87),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Amount: ${_btcFormat.format(amount)} BTC',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Text(
              'Platform Fee: ${_btcFormat.format(platformFee)} BTC',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Text(
              'Network Fee: ${_btcFormat.format(networkFee)} BTC',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Text(
              'Total Cost: ${_btcFormat.format(totalCost)} BTC',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'To: ${address.substring(0, 8)}...${address.substring(address.length - 8)}',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            const Text(
              'This transaction cannot be reversed. Please verify the address carefully.',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
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
              backgroundColor: Colors.red,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
} 