class NetworkConfigService {
  static const bool _isTestnet = false; // TODO: Make this configurable via environment variables or app settings
  
  /// Returns true if the app is configured for testnet
  static bool get isTestnet => _isTestnet;
  
  /// Returns the appropriate blockchain explorer URL for the current network
  static String getExplorerUrl(String txHash) {
    final baseUrl = _isTestnet 
        ? 'https://blockstream.info/testnet/tx/'
        : 'https://blockstream.info/tx/';
    return '$baseUrl$txHash';
  }
  
  /// Returns the network name for display purposes
  static String get networkName => _isTestnet ? 'Testnet' : 'Mainnet';
  
  /// Returns the network prefix for addresses (if needed)
  static String get networkPrefix => _isTestnet ? 'tb1' : 'bc1';
  
  /// Validates if an address belongs to the current network
  static bool isValidAddressForNetwork(String address) {
    if (_isTestnet) {
      // Testnet addresses start with 'm', 'n', '2', or 'tb1'
      return address.startsWith('m') || 
             address.startsWith('n') || 
             address.startsWith('2') || 
             address.startsWith('tb1');
    } else {
      // Mainnet addresses start with '1', '3', or 'bc1'
      return address.startsWith('1') || 
             address.startsWith('3') || 
             address.startsWith('bc1');
    }
  }
  
  /// Returns alternative explorer URLs for the current network
  static List<String> getAlternativeExplorerUrls(String txHash) {
    if (_isTestnet) {
      return [
        'https://blockstream.info/testnet/tx/$txHash',
        'https://mempool.space/testnet/tx/$txHash',
        'https://live.blockcypher.com/btc-testnet/tx/$txHash',
      ];
    } else {
      return [
        'https://blockstream.info/tx/$txHash',
        'https://mempool.space/tx/$txHash',
        'https://live.blockcypher.com/btc/tx/$txHash',
        'https://www.blockchain.com/btc/tx/$txHash',
      ];
    }
  }
} 