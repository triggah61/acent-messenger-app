import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/wallet.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/transaction_details_modal.dart';

class TransactionsScreen extends StatefulWidget {
  final String currency;

  const TransactionsScreen({
    Key? key,
    required this.currency,
  }) : super(key: key);

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final ScrollController _scrollController = ScrollController();
  final NumberFormat _cryptoFormat = NumberFormat('#,##0.00000000', 'en_US');

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().fetchTransactions(
        refresh: true,
        currency: widget.currency,
      );
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
      context.read<WalletProvider>().loadMoreTransactions(currency: widget.currency);
    }
  }

  Color _getCurrencyColor() {
    switch (widget.currency.toUpperCase()) {
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

  String _getCurrencySymbol() {
    switch (widget.currency.toUpperCase()) {
      case 'BTC':
        return '₿';
      case 'ETH':
        return 'Ξ';
      case 'BNB':
        return 'BNB';
      default:
        return widget.currency.toUpperCase();
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
                      '${widget.currency.toUpperCase()} Transactions',
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
                child: RefreshIndicator(
                  onRefresh: () => context.read<WalletProvider>().fetchTransactions(
                    refresh: true,
                    currency: widget.currency,
                  ),
                  child: Consumer<WalletProvider>(
                    builder: (context, walletProvider, child) {
                      return Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            _buildHeader(walletProvider),
                            const SizedBox(height: 20),
                            Expanded(child: _buildTransactionsList(walletProvider)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(WalletProvider walletProvider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              child: Center(
                child: Text(
                  _getCurrencySymbol(),
                  style: TextStyle(
                    color: _getCurrencyColor(),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${widget.currency.toUpperCase()} Transactions',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (walletProvider.transactionPagination != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getCurrencyColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              '${walletProvider.transactionPagination!.totalDocs} total',
              style: TextStyle(
                color: _getCurrencyColor(),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTransactionsList(WalletProvider walletProvider) {
    if (walletProvider.isLoadingTransactions && walletProvider.transactions.isEmpty) {
      return _buildLoadingState();
    }

    if (walletProvider.hasTransactionError && walletProvider.transactions.isEmpty) {
      return _buildErrorState(walletProvider.transactionError!);
    }

    if (walletProvider.transactions.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
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
                  '$sign${_cryptoFormat.format(transaction.amount)} ${transaction.currency}',
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
                    'Fee: ${_cryptoFormat.format(transaction.fee)} ${transaction.currency}',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading transactions...',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Error loading transactions',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
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
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.read<WalletProvider>().fetchTransactions(
              refresh: true,
              currency: widget.currency,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long,
            color: Colors.grey[400],
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'No ${widget.currency.toUpperCase()} transactions',
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your ${widget.currency.toUpperCase()} transaction history will appear here',
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

  Widget _buildLoadMoreIndicator(WalletProvider walletProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: walletProvider.isLoadingMoreTransactions
            ? const CircularProgressIndicator()
            : const SizedBox.shrink(),
      ),
    );
  }

  String _getTransactionTitle(Transaction transaction) {
    if (transaction.isDeposit) {
      return 'Received ${widget.currency.toUpperCase()}';
    } else {
      return 'Sent ${widget.currency.toUpperCase()}';
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy • HH:mm').format(date);
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green;
      case 'processing':
        return Colors.orange;
      case 'pending':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _showTransactionDetails(Transaction transaction) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => TransactionDetailsModal(
        transaction: transaction,
        currency: widget.currency,
      ),
    );
  }
} 