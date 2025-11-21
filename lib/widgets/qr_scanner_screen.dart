import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({Key? key}) : super(key: key);

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController controller = MobileScannerController();
  bool isFlashOn = false;
  bool hasScanned = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Scan QR Code',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
            onPressed: () {
              controller.toggleTorch();
              setState(() {
                isFlashOn = !isFlashOn;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (BarcodeCapture capture) {
              if (!hasScanned && capture.barcodes.isNotEmpty) {
                hasScanned = true;
                final String code = capture.barcodes.first.rawValue ?? '';
                final extractedAddress = _extractBitcoinAddress(code);

                if (extractedAddress.isNotEmpty) {
                  Navigator.pop(context, extractedAddress);
                } else {
                  // Show error and allow scanning again
                  _showErrorDialog(code);
                  setState(() {
                    hasScanned = false;
                  });
                }
              }
            },
          ),
          // Overlay with scanning area
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
            ),
            child: Stack(
              children: [
                // Dark overlay with transparent center
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.6),
                    BlendMode.srcOut,
                  ),
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          backgroundBlendMode: BlendMode.dstOut,
                        ),
                      ),
                      Center(
                        child: Container(
                          height: 250,
                          width: 250,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Scanning frame
                Center(
                  child: Container(
                    height: 250,
                    width: 250,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        // Corner decorations
                        Positioned(
                          top: 0,
                          left: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Instructions
                Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: const Text(
                      'Position the QR code within the frame to scan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
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

  String _extractBitcoinAddress(String qrData) {
    if (qrData.isEmpty) return '';

    // Clean the data
    String cleanData = qrData.trim();

    // Handle Bitcoin URI format (bitcoin:address?amount=...)
    if (cleanData.toLowerCase().startsWith('bitcoin:')) {
      final uri = Uri.tryParse(cleanData);
      if (uri != null) {
        // Extract address from the path
        String address = uri.path;
        if (address.isNotEmpty) {
          return address;
        }
      }

      // Fallback: extract address manually
      final addressMatch =
          RegExp(r'bitcoin:([a-zA-Z0-9]+)').firstMatch(cleanData);
      if (addressMatch != null) {
        return addressMatch.group(1) ?? '';
      }
    }

    // Validate if it's a direct Bitcoin address
    if (_isValidBitcoinAddress(cleanData)) {
      return cleanData;
    }

    return '';
  }

  bool _isValidBitcoinAddress(String address) {
    if (address.isEmpty) return false;

    // Basic Bitcoin address validation
    // Legacy addresses (P2PKH) start with '1'
    // Script addresses (P2SH) start with '3'
    // Bech32 addresses (P2WPKH/P2WSH) start with 'bc1'
    final bitcoinAddressRegex = RegExp(
        r'^(1[a-km-zA-HJ-NP-Z1-9]{25,34}|3[a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[a-z0-9]{39,59})$');

    return bitcoinAddressRegex.hasMatch(address);
  }

  void _showErrorDialog(String scannedData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'Invalid QR Code',
              style: TextStyle(color: Colors.black87),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The scanned QR code does not contain a valid Bitcoin address.',
              style: TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 12),
            if (scannedData.isNotEmpty) ...[
              const Text(
                'Scanned content:',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  scannedData,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
