import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/wallet.dart';
import '../services/network_config_service.dart';

class TransactionDetailsModal extends StatelessWidget {
  final Transaction transaction;

  const TransactionDetailsModal({
    Key? key,
    required this.transaction,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                _buildTransactionIcon(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getTransactionTitle(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildStatusChip(),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
          ),
          
          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _buildAmountSection(),
                  const SizedBox(height: 24),
                  _buildDetailsSection(),
                  const SizedBox(height: 24),
                  _buildAddressSection(),
                  if (transaction.txHash != null) ...[
                    const SizedBox(height: 24),
                    _buildHashSection(context),
                  ],
                  const SizedBox(height: 24),
                  _buildTimestampSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionIcon() {
    final isDeposit = transaction.isDeposit;
    final color = isDeposit ? Colors.green : Colors.red;
    final icon = isDeposit ? Icons.arrow_downward : Icons.arrow_upward;

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }

  Widget _buildStatusChip() {
    final color = _getStatusColor(transaction.status);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        transaction.status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAmountSection() {
    final NumberFormat btcFormat = NumberFormat('#,##0.00000000', 'en_US');
    final isDeposit = transaction.isDeposit;
    final sign = isDeposit ? '+' : '-';
    final color = isDeposit ? Colors.green : Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            '$sign${btcFormat.format(transaction.btcAmount)} BTC',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (transaction.netAmount.btc != transaction.amount.btc) ...[
            const SizedBox(height: 8),
            Text(
              'Net Amount: ${btcFormat.format(transaction.netAmount.btc.abs())} BTC',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    final NumberFormat btcFormat = NumberFormat('#,##0.00000000', 'en_US');
    
    return _buildSection(
      title: 'Transaction Details',
      children: [
        _buildDetailRow('Type', _getTransactionTypeDisplay()),
        _buildDetailRow('Direction', transaction.direction.toUpperCase()),
        if (transaction.fee.btc > 0)
          _buildDetailRow('Network Fee', '${btcFormat.format(transaction.fee.btc)} BTC'),
        if (transaction.adminFee.btc > 0)
          _buildDetailRow('Platform Fee', '${btcFormat.format(transaction.adminFee.btc)} BTC'),
        if (transaction.confirmations > 0)
          _buildDetailRow('Confirmations', '${transaction.confirmations}'),
        if (transaction.description != null && transaction.description!.isNotEmpty)
          _buildDetailRow('Description', transaction.description!),
      ],
    );
  }

  Widget _buildAddressSection() {
    return _buildSection(
      title: 'Addresses',
      children: [
        if (transaction.fromAddress != null)
          _buildAddressRow('From', transaction.fromAddress!),
        if (transaction.toAddress != null)
          _buildAddressRow('To', transaction.toAddress!),
      ],
    );
  }

  Widget _buildHashSection(BuildContext context) {
    if (transaction.txHash == null) return const SizedBox.shrink();

    return _buildSection(
      title: 'Transaction Hash',
      children: [
        GestureDetector(
          onTap: () => _openTransactionInBrowser(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.txHash!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to view on ${NetworkConfigService.networkName} blockchain explorer',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _copyToClipboard(context, transaction.txHash!),
                      icon: const Icon(Icons.copy, color: Colors.blue, size: 20),
                      tooltip: 'Copy hash',
                    ),
                    const Icon(Icons.open_in_new, color: Colors.blue, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimestampSection() {
    return _buildSection(
      title: 'Timestamps',
      children: [
        _buildDetailRow('Submitted', _formatDateTime(transaction.submittedAt)),
        if (transaction.confirmedAt != null)
          _buildDetailRow('Confirmed', _formatDateTime(transaction.confirmedAt!)),
        _buildDetailRow('Created', _formatDateTime(transaction.createdAt)),
      ],
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
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
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow(String label, String address) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _copyToClipboard(null, address),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy, color: Colors.grey, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getTransactionTitle() {
    if (transaction.description != null && transaction.description!.isNotEmpty) {
      return transaction.description!;
    }
    return transaction.isDeposit ? 'Bitcoin Received' : 'Bitcoin Sent';
  }

  String _getTransactionTypeDisplay() {
    switch (transaction.type.toLowerCase()) {
      case 'withdrawal':
        return 'Withdrawal';
      case 'deposit':
        return 'Deposit';
      default:
        return transaction.type.toUpperCase();
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green;
      case 'processing':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final DateFormat formatter = DateFormat('MMM dd, yyyy • HH:mm');
    return formatter.format(dateTime);
  }

  Future<void> _openTransactionInBrowser(BuildContext context) async {
    if (transaction.txHash == null) return;

    final String url = NetworkConfigService.getExplorerUrl(transaction.txHash!);

    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (context.mounted) {
          _showErrorSnackBar(context, 'Could not open blockchain explorer');
        }
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, 'Error opening URL: ${e.toString()}');
      }
    }
  }

  Future<void> _copyToClipboard(BuildContext? context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Copied to clipboard'),
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
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static void show(BuildContext context, Transaction transaction) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => TransactionDetailsModal(
          transaction: transaction,
        ),
      ),
    );
  }
} 