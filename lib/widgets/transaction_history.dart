import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/wallet.dart';
import '../providers/wallet_provider.dart';
import 'transaction_details_modal.dart';

class TransactionHistory extends StatefulWidget {
  const TransactionHistory({Key? key}) : super(key: key);

  @override
  State<TransactionHistory> createState() => _TransactionHistoryState();
}

class _TransactionHistoryState extends State<TransactionHistory> {
  final ScrollController _scrollController = ScrollController();
  final NumberFormat _btcFormat = NumberFormat('#,##0.00000000', 'en_US');

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().fetchTransactions(refresh: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      // User has scrolled to the bottom, load more transactions
      context.read<WalletProvider>().loadMoreTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WalletProvider>(
      builder: (context, walletProvider, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (walletProvider.transactionPagination != null)
                  Text(
                    '${walletProvider.transactionPagination!.totalDocs} total',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (walletProvider.isLoadingTransactions && walletProvider.transactions.isEmpty)
              _buildLoadingState()
            else if (walletProvider.hasTransactionError && walletProvider.transactions.isEmpty)
              _buildErrorState(walletProvider.transactionError!)
            else if (walletProvider.transactions.isEmpty)
              _buildEmptyState()
            else
              _buildTransactionList(walletProvider),
          ],
        );
      },
    );
  }

  Widget _buildTransactionList(WalletProvider walletProvider) {
    return SizedBox(
      height: 400, // Fixed height for scrollable area
      child: ListView.builder(
        controller: _scrollController,
        itemCount: walletProvider.transactions.length + 
                   (walletProvider.canLoadMoreTransactions ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == walletProvider.transactions.length) {
            // Loading indicator for pagination
            return _buildLoadMoreIndicator(walletProvider);
          }
          
          final transaction = walletProvider.transactions[index];
          return _buildTransactionItem(transaction);
        },
      ),
    );
  }

  Widget _buildTransactionItem(Transaction transaction) {
    final isDeposit = transaction.isDeposit;
    final color = isDeposit ? Colors.green : Colors.red;
    final icon = isDeposit ? Icons.arrow_downward : Icons.arrow_upward;
    final sign = isDeposit ? '+' : '-';

    return GestureDetector(
      onTap: () => _showTransactionDetails(transaction),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTransactionTitle(transaction),
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(transaction.submittedAt),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  if (transaction.confirmations > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${transaction.confirmations} confirmation${transaction.confirmations > 1 ? 's' : ''}',
                      style: TextStyle(
                        color: Colors.green[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$sign${_btcFormat.format(transaction.amount)} ${transaction.currency}',
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(transaction.status).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    transaction.status.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusColor(transaction.status),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (transaction.fee > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Fee: ${_btcFormat.format(transaction.fee)} ${transaction.currency}',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadMoreIndicator(WalletProvider walletProvider) {
    if (walletProvider.isLoadingMoreTransactions) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildLoadingState() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Error loading transactions',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
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

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long,
            color: Colors.grey[400],
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _getTransactionTitle(Transaction transaction) {
    if (transaction.description != null && transaction.description!.isNotEmpty) {
      return transaction.description!;
    }
    
    final currencyName = _getCurrencyName(transaction.currency);
    if (transaction.isDeposit) {
      return '$currencyName Received';
    } else {
      return '$currencyName Sent';
    }
  }

  String _getCurrencyName(String currency) {
    switch (currency.toUpperCase()) {
      case 'BTC':
        return 'Bitcoin';
      case 'ETH':
        return 'Ethereum';
      case 'BNB':
        return 'Binance Coin';
      default:
        return currency.toUpperCase();
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final localDate = date.toLocal(); // Convert to local timezone
    final difference = now.difference(localDate);

    // Show relative time for recent transactions with local time
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago • ${DateFormat('h:mm a').format(localDate)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday • ${DateFormat('h:mm a').format(localDate)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago • ${DateFormat('h:mm a').format(localDate)}';
    } else {
      // For older transactions, show full date with local time
      return DateFormat('MMM dd • h:mm a').format(localDate);
    }
  }

  void _showTransactionDetails(Transaction transaction) {
    TransactionDetailsModal.show(context, transaction);
  }
} 