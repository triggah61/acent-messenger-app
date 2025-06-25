import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/auth_middleware.dart';
import 'deposit_screen.dart';
import 'withdraw_screen.dart';
import 'transactions_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({Key? key}) : super(key: key);

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final NumberFormat _cryptoFormat = NumberFormat('#,##0.00000000', 'en_US');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().refreshWalletData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthMiddleware(
      child: Scaffold(
        backgroundColor: const Color(0xFF121829),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16.0),
                child: _buildHeader(),
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
                    onRefresh: () => context.read<WalletProvider>().refreshWalletData(),
                    child: Consumer<WalletProvider>(
                      builder: (context, walletProvider, child) {
                        if (walletProvider.isLoading && walletProvider.wallet == null) {
                          return _buildLoadingState();
                        }

                        if (walletProvider.error != null) {
                          return _buildErrorState(walletProvider.error!);
                        }

                        final wallet = walletProvider.wallet;
                        if (wallet == null) {
                          return _buildErrorState('Wallet not found');
                        }

                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 10),
                                _buildTotalBalanceCard(wallet),
                                const SizedBox(height: 30),
                                _buildCurrencyTiles(wallet),
                              ],
                            ),
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
      ),
    );
  }

  Widget _buildHeader() {
    return const Row(
      children: [
        Expanded(
          child: Center(
            child: Text(
              'Assets',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalBalanceCard(wallet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.deepPurple, Colors.blueAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: 28,
              ),
              SizedBox(width: 10),
              Text(
                'Total Portfolio Value',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '\$${_currencyFormat.format(wallet.usdBalance)} USD',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencyTiles(wallet) {
    final currencies = [
      {
        'code': 'BTC',
        'name': 'Bitcoin',
        'balance': wallet.btcBalance,
        'color': Colors.orange,
        'icon': 'assets/icons/crypto/bitcoin.png',
      },
      {
        'code': 'ETH',
        'name': 'Ethereum',
        'balance': wallet.ethBalance,
        'color': Colors.purple,
        'icon': 'assets/icons/crypto/ethereum.png',
      },
      {
        'code': 'BNB',
        'name': 'Binance Coin',
        'balance': wallet.bscBalance,
        'color': Colors.yellow[700]!,
        'icon': 'assets/icons/crypto/bnb.png',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Assets',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ...currencies.map((currency) => _buildCurrencyTile(
          wallet,
          currency['code'] as String,
          currency['name'] as String,
          currency['balance'] as double,
          currency['color'] as Color,
          currency['icon'] as String,
        )).toList(),
      ],
    );
  }

  Widget _buildCurrencyTile(wallet, String code, String name, double balance, Color color, String icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Center(
                  child: Image.asset(
                    icon,
                    width: 24,
                    height: 24,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to original text icons if image assets are not found
                      final fallbackIcon = _getFallbackIcon(code);
                      return Text(
                        fallbackIcon,
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_currencyFormat.format(wallet.getUsdEquivalent(code))} USDT',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                    // const SizedBox(height: 2),
                    // Text(
                    //   '\$${_currencyFormat.format(wallet.getUsdEquivalent(code))} USD',
                    //   style: TextStyle(
                    //     color: Colors.grey[500],
                    //     fontSize: 12,
                    //   ),
                    // ),
                  ],
                ),
              ),
              Text(
                '${_cryptoFormat.format(balance)} ${code.toUpperCase()}',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.arrow_downward,
                  label: 'Deposit',
                  color: Colors.green,
                  onTap: () => _navigateToDeposit(code),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.arrow_upward,
                  label: 'Withdraw',
                  color: Colors.red,
                  onTap: () => _navigateToWithdraw(code),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.receipt_long,
                  label: 'Transactions',
                  color: color,
                  onTap: () => _navigateToTransactions(code),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            // const SizedBox(height: 4),
            // Text(
            //   label,
            //   style: TextStyle(
            //     color: color,
            //     fontSize: 12,
            //     fontWeight: FontWeight.w600,
            //   ),
            // ),
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
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
          ),
          SizedBox(height: 16),
          Text(
            'Loading wallet...',
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
          const Icon(Icons.error, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Error loading wallet',
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
            onPressed: () => context.read<WalletProvider>().refreshWalletData(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _navigateToDeposit(String currency) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DepositScreen(currency: currency),
      ),
    );
  }

  void _navigateToWithdraw(String currency) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WithdrawScreen(currency: currency),
      ),
    );
    
    // Refresh wallet data when returning from withdrawal screen
    if (mounted) {
      context.read<WalletProvider>().refreshWalletData();
    }
  }

  void _navigateToTransactions(String currency) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionsScreen(currency: currency),
      ),
    );
  }

  String _getFallbackIcon(String code) {
    // Fallback to original text icons if image assets are not found
    switch (code) {
      case 'BTC':
        return '₿';
      case 'ETH':
        return 'Ξ';
      case 'BNB':
        return 'BNB';
      default:
        return code;
    }
  }
} 