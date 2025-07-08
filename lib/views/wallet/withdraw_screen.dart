import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../models/wallet.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/qr_scanner_screen.dart';

class ValidationResult {
  final bool isValid;
  final String errorMessage;

  ValidationResult(this.isValid, this.errorMessage);
}

class WithdrawScreen extends StatefulWidget {
  final String? currency;

  const WithdrawScreen({Key? key, this.currency}) : super(key: key);

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
  final NumberFormat _cryptoFormat = NumberFormat('#,##0.00000000', 'en_US');
  late String _currentCurrency;

  // Debouncing for fee estimation
  Timer? _debounceTimer;
  static const Duration _debounceDuration = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _currentCurrency = widget.currency ?? 'BTC';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().fetchNetworkFees();
    });

    // Listen to amount changes for fee estimation
    _amountController.addListener(_onAmountChanged);

    // Listen to form changes for validation
    _amountController.addListener(_onFormChanged);
    _addressController.addListener(_onFormChanged);
  }

  String _getCurrencyDisplayName() {
    switch (_currentCurrency.toUpperCase()) {
      case 'BTC':
        return 'Bitcoin';
      case 'ETH':
        return 'Ethereum';
      case 'BNB':
        return 'Binance Coin';
      default:
        return _currentCurrency.toUpperCase();
    }
  }

  Color _getCurrencyColor() {
    switch (_currentCurrency.toUpperCase()) {
      case 'BTC':
        return Colors.orange;
      case 'ETH':
        return Colors.purple;
      case 'BNB':
        return Colors.yellow[700]!;
      default:
        return Colors.blue;
    }
  }

  String _getAddressHintText() {
    switch (_currentCurrency.toUpperCase()) {
      case 'BTC':
        return 'Enter Bitcoin address (e.g., 1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa)';
      case 'ETH':
        return 'Enter Ethereum address (e.g., 0x742d35Cc6634C0532925a3b8D7f6d8Eb5f2d9e3A)';
      case 'BNB':
        return 'Enter BNB address (e.g., bnb1grpf0955h0ykzq3ar5nmum7y6gdfl6lxfn46h2)';
      default:
        return 'Enter ${_currentCurrency.toUpperCase()} address';
    }
  }

  String _getAddressValidationRegex() {
    switch (_currentCurrency.toUpperCase()) {
      case 'BTC':
        // Bitcoin address validation regex
        return r'^(1[a-km-zA-HJ-NP-Z1-9]{25,34}|3[a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[a-z0-9]{39,59}|[mn2][a-km-zA-HJ-NP-Z1-9]{25,34}|tb1[a-z0-9]{39,59})$';
      case 'ETH':
        // Ethereum address validation regex (0x followed by 40 hex characters)
        return r'^0x[a-fA-F0-9]{40}$';
      case 'BNB':
        // BNB address validation regex (bnb1 followed by 38 characters)
        return r'^0x[a-fA-F0-9]{40}$';
      default:
        return r'^.+$'; // Generic validation - just not empty
    }
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
                  Expanded(
                    child: Text(
                      'Withdraw ${_getCurrencyDisplayName()}',
                      style: const TextStyle(
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
    final balance = wallet.getBalanceForCurrency(_currentCurrency);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_getCurrencyColor(), _getCurrencyColor().withOpacity(0.7)],
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
            '${_cryptoFormat.format(balance)} ${_currentCurrency.toUpperCase()}',
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
              suffixText: '${_currentCurrency.toUpperCase()}',
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
              final selectedFee =
                  context.read<WalletProvider>().getFeeByType(_selectedFeeType);
              final totalCost = amount + (selectedFee?.totalBtcFee ?? 0.0);
              final currentBalance =
                  wallet.getBalanceForCurrency(_currentCurrency);

              if (totalCost > currentBalance) {
                return 'Insufficient balance (including fees)';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
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
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.blueAccent),
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
                            '${_cryptoFormat.format(fee.totalBtcFee)} ${_currentCurrency.toUpperCase()}',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.black87
                                  : Colors.grey[700],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Network: ${_cryptoFormat.format(fee.networkFee.btc)} ${_currentCurrency.toUpperCase()}',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.grey[600]
                                  : Colors.grey[500],
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            'Platform: ${_cryptoFormat.format(fee.platformFee.btc)} ${_currentCurrency.toUpperCase()}',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.grey[600]
                                  : Colors.grey[500],
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
              hintText: _getAddressHintText(),
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

              // Validate address format based on currency
              if (!_isValidAddressFormat(value)) {
                return 'Please enter a valid ${_getCurrencyDisplayName()} address';
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
          _buildSummaryRow('Amount',
              '${_cryptoFormat.format(amount)} ${_currentCurrency.toUpperCase()}'),
          _buildSummaryRow('Platform Fee',
              '${_cryptoFormat.format(platformFee)} ${_currentCurrency.toUpperCase()}'),
          _buildSummaryRow('Network Fee',
              '${_cryptoFormat.format(networkFee)} ${_currentCurrency.toUpperCase()}'),
          Divider(color: Colors.grey[300]),
          _buildSummaryRow('Total to Deduct',
              '${_cryptoFormat.format(total)} ${_currentCurrency.toUpperCase()}',
              isTotal: true),
          const SizedBox(height: 8),
          Text(
            'Remaining Balance: ${_cryptoFormat.format(wallet.getBalanceForCurrency(_currentCurrency) - total)} ${_currentCurrency.toUpperCase()}',
            style: TextStyle(
              color: total > wallet.getBalanceForCurrency(_currentCurrency)
                  ? Colors.red
                  : Colors.grey[600],
              fontSize: 12,
              fontWeight: total > wallet.getBalanceForCurrency(_currentCurrency)
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          if (total > wallet.getBalanceForCurrency(_currentCurrency))
            const SizedBox(height: 4),
          if (total > wallet.getBalanceForCurrency(_currentCurrency))
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
    final validationResult = _validateWithdrawal(walletProvider);
    final isButtonEnabled =
        validationResult.isValid && !_isLoading && !walletProvider.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!validationResult.isValid &&
            validationResult.errorMessage.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.red[600], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    validationResult.errorMessage,
                    style: TextStyle(
                      color: Colors.red[700],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isButtonEnabled ? _handleWithdraw : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isButtonEnabled ? Colors.red : Colors.grey[400],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: isButtonEnabled ? 2 : 0,
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
                : Text(
                    isButtonEnabled ? 'Confirm Withdrawal' : 'Cannot Withdraw',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isButtonEnabled ? Colors.white : Colors.grey[600],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  ValidationResult _validateWithdrawal(WalletProvider walletProvider) {
    final wallet = walletProvider.wallet;
    if (wallet == null) {
      return ValidationResult(false, 'Wallet not available');
    }

    // Check if amount is entered
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      return ValidationResult(false, 'Please enter an amount to withdraw');
    }

    // Parse amount
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      return ValidationResult(
          false, 'Please enter a valid amount greater than 0');
    }

    // Check if address is entered
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      return ValidationResult(false, 'Please enter a destination address');
    }

    // Check if address is valid (basic validation)
    if (!_isValidAddressFormat(address)) {
      return ValidationResult(
          false, 'Please enter a valid ${_getCurrencyDisplayName()} address');
    }

    // Check if fees are loaded
    final selectedFee = walletProvider.getFeeByType(_selectedFeeType);
    if (selectedFee == null) {
      return ValidationResult(false, 'Loading fees... Please wait');
    }

    // Check if there's a fee loading error
    if (walletProvider.feeError != null) {
      return ValidationResult(
          false, 'Unable to load network fees. Please try again');
    }

    // Calculate total cost including fees
    final totalCost = amount + selectedFee.totalBtcFee;

    // Check balance
    if (totalCost > wallet.getBalanceForCurrency(_currentCurrency)) {
      final shortfall =
          totalCost - wallet.getBalanceForCurrency(_currentCurrency);
      return ValidationResult(false,
          'Insufficient balance. You need ${_cryptoFormat.format(shortfall)} ${_currentCurrency.toUpperCase()} more (including fees)');
    }

    // Check minimum withdrawal amount (if any)
    const minWithdrawal = 0.00001; // 1000 satoshis
    if (amount < minWithdrawal) {
      return ValidationResult(false,
          'Minimum withdrawal amount is ${_cryptoFormat.format(minWithdrawal)} ${_currentCurrency.toUpperCase()}');
    }

    return ValidationResult(true, '');
  }

  bool _isValidAddressFormat(String address) {
    if (address.isEmpty) return false;

    final regex = RegExp(_getAddressValidationRegex());
    return regex.hasMatch(address);
  }

  bool _isValidBitcoinAddressBasic(String address) {
    if (address.isEmpty) return false;

    // Basic Bitcoin address validation
    // Legacy addresses (P2PKH) start with '1'
    // Script addresses (P2SH) start with '3'
    // Bech32 addresses (P2WPKH/P2WSH) start with 'bc1'
    // Testnet addresses start with 'm', 'n', '2', 'tb1'
    final bitcoinAddressRegex = RegExp(
        r'^(1[a-km-zA-HJ-NP-Z1-9]{25,34}|3[a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[a-z0-9]{39,59}|[mn2][a-km-zA-HJ-NP-Z1-9]{25,34}|tb1[a-z0-9]{39,59})$');

    return bitcoinAddressRegex.hasMatch(address);
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
              currency: _currentCurrency,
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
                            'Your ${_currentCurrency.toUpperCase()} withdrawal of ${_cryptoFormat.format(amount)} ${_currentCurrency.toUpperCase()} has been submitted successfully.',
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
                        context.read<WalletProvider>().error ??
                            'Withdrawal failed',
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
          errorMessage =
              errorMessage.substring(11); // Remove 'Exception: ' prefix
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
    final selectedFee =
        context.read<WalletProvider>().getFeeByType(_selectedFeeType);

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
                  _buildConfirmationRow('Amount:',
                      '${_cryptoFormat.format(amount)} ${_currentCurrency.toUpperCase()}'),
                  const SizedBox(height: 8),
                  _buildConfirmationRow('Platform Fee:',
                      '${_cryptoFormat.format(platformFee)} ${_currentCurrency.toUpperCase()}'),
                  const SizedBox(height: 8),
                  _buildConfirmationRow('Network Fee:',
                      '${_cryptoFormat.format(networkFee)} ${_currentCurrency.toUpperCase()}'),
                  const SizedBox(height: 8),
                  _buildConfirmationRow(
                      'Priority:', _getFeeTypeTitle(_selectedFeeType)),
                  const Divider(),
                  _buildConfirmationRow(
                    'Total Cost:',
                    '${_cryptoFormat.format(totalCost)} ${_currentCurrency.toUpperCase()}',
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

  Widget _buildConfirmationRow(String label, String value,
      {bool isTotal = false}) {
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
        context
            .read<WalletProvider>()
            .estimateFeesForAmount(amount, currency: _currentCurrency);
      } else {
        context.read<WalletProvider>().clearFeeEstimation();
      }
    });
  }

  void _onFormChanged() {
    // Trigger UI update to refresh button state and validation
    setState(() {});
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
                Expanded(
                  child: Text(
                      '${_getCurrencyDisplayName()} address scanned successfully!'),
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
    _amountController.removeListener(_onFormChanged);
    _amountController.dispose();
    _addressController.removeListener(_onFormChanged);
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
