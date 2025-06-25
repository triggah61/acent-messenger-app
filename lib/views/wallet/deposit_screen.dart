import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/wallet_provider.dart';
import '../../services/wallet_service.dart';

class DepositScreen extends StatefulWidget {
  final String? currency;

  const DepositScreen({Key? key, this.currency}) : super(key: key);

  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  final TextEditingController _amountController = TextEditingController();
  String? _qrData;
  late String _currentCurrency;

  @override
  void initState() {
    super.initState();
    _currentCurrency = widget.currency ?? 'BTC';
    _generateQRCode();
  }

  void _generateQRCode() {
    final wallet = context.read<WalletProvider>().wallet;
    if (wallet != null) {
      final walletService = WalletService(context.read());
      final address = wallet.getAddressForCurrency(_currentCurrency);
      _qrData = walletService.generateQRCodeData(address, currency: _currentCurrency);
    }
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

  String _getCurrencyIcon() {
    switch (_currentCurrency.toUpperCase()) {
      case 'BTC':
        return 'assets/icons/crypto/bitcoin.png';
      case 'ETH':
        return 'assets/icons/crypto/ethereum.png';
      case 'BNB':
        return 'assets/icons/crypto/bnb.png';
      default:
        return 'assets/icons/crypto/bitcoin.png'; // fallback
    }
  }

  String _getCurrencySymbol() {
    switch (_currentCurrency.toUpperCase()) {
      case 'BTC':
        return '₿';
      case 'ETH':
        return 'Ξ';
      case 'BNB':
        return 'BNB';
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
                      'Deposit ${_getCurrencyDisplayName()}',
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

                    final address = wallet.getAddressForCurrency(_currentCurrency);
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          _buildInstructionCard(),
                          const SizedBox(height: 24),
                          _buildQRCodeCard(address),
                          const SizedBox(height: 24),
                          _buildAddressCard(address),
                          const SizedBox(height: 24),
                          _buildWarningCard(),
                        ],
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

  Widget _buildInstructionCard() {
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getCurrencyColor().withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Image.asset(
                  _getCurrencyIcon(),
                  width: 24,
                  height: 24,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback to info icon if image assets are not found
                    return Icon(
                      Icons.info_outline,
                      color: _getCurrencyColor(),
                      size: 24,
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'How to Deposit',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInstructionStep(
            '1',
            'Copy the wallet address below or scan the QR code',
          ),
          _buildInstructionStep(
            '2',
            'Send ${_getCurrencyDisplayName()} from your external wallet to this address',
          ),
          _buildInstructionStep(
            '3',
            'Wait for network confirmations (usually 10-60 minutes)',
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(String step, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRCodeCard(String address) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Scan QR Code',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (_qrData != null)
            QrImageView(
              data: _qrData!,
              version: QrVersions.auto,
              size: 200.0,
              foregroundColor: Colors.black87,
            )
          else
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('QR Code not available'),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Scan this QR code with your ${_getCurrencyDisplayName()} wallet',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(String address) {
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
          Text(
            'Your ${_getCurrencyDisplayName()} Address',
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    address,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _copyToClipboard(address),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.copy,
                      color: Colors.green,
                      size: 20,
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

  Widget _buildAmountSection() {
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
            'Specify Amount (Optional)',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
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
            onChanged: (value) {
              _updateQRCode(value);
            },
          ),
          const SizedBox(height: 8),
          Text(
            'If you specify an amount, it will be included in the QR code',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning,
                color: Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Important Notice',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _getWarningText(),
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  String _getWarningText() {
    switch (_currentCurrency.toUpperCase()) {
      case 'BTC':
        return '• Only send Bitcoin (BTC) to this address\n'
            '• Sending any other cryptocurrency will result in permanent loss\n'
            '• Minimum deposit: 0.00001 BTC\n'
            '• Deposits require network confirmations';
      case 'ETH':
        return '• Only send Ethereum (ETH) to this address\n'
            '• Sending any other cryptocurrency will result in permanent loss\n'
            '• Minimum deposit: 0.001 ETH\n'
            '• Deposits require network confirmations';
      case 'BNB':
        return '• Only send Binance Coin (BNB) on BSC network to this address\n'
            '• Sending any other cryptocurrency will result in permanent loss\n'
            '• Minimum deposit: 0.001 BNB\n'
            '• Deposits require network confirmations';
      default:
        return '• Only send ${_getCurrencyDisplayName()} to this address\n'
            '• Sending any other cryptocurrency will result in permanent loss\n'
            '• Minimum deposit varies by network\n'
            '• Deposits require network confirmations';
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Address copied to clipboard'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _updateQRCode(String amountText) {
    final wallet = context.read<WalletProvider>().wallet;
    if (wallet != null) {
      final walletService = WalletService(context.read());
      double? amount;
      if (amountText.isNotEmpty) {
        amount = double.tryParse(amountText);
      }
      setState(() {
        final address = wallet.getAddressForCurrency(_currentCurrency);
        _qrData = walletService.generateQRCodeData(address, amount: amount, currency: _currentCurrency);
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
} 