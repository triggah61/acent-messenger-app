import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({Key? key}) : super(key: key);

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool _isScanning = true;
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        _showPermissionDeniedDialog();
      }
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'Camera access is required to scan QR codes. Please grant camera permission in settings.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // QR Scanner View
            QRView(
              key: qrKey,
              onQRViewCreated: _onQRViewCreated,
              overlay: QrScannerOverlayShape(
                borderColor: Colors.white,
                borderRadius: 10,
                borderLength: 30,
                borderWidth: 10,
                cutOutSize: 250,
              ),
            ),
            
            // Top bar with back button and title
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Scan Bitcoin Address',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _flashOn ? Icons.flash_on : Icons.flash_off,
                        color: Colors.white,
                      ),
                      onPressed: _toggleFlash,
                    ),
                  ],
                ),
              ),
            ),
            
            // Bottom instruction text
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.qr_code_scanner,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Position the QR code within the frame',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scanning for Bitcoin addresses...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      if (_isScanning && scanData.code != null) {
        _handleScannedData(scanData.code!);
      }
    });
  }

  void _handleScannedData(String data) {
    setState(() {
      _isScanning = false;
    });

    // Extract Bitcoin address from various QR code formats
    String? bitcoinAddress = _extractBitcoinAddress(data);
    
    if (bitcoinAddress != null) {
      // Valid Bitcoin address found
      Navigator.pop(context, bitcoinAddress);
    } else {
      // Invalid QR code
      _showInvalidQRDialog(data);
    }
  }

  String? _extractBitcoinAddress(String data) {
    // Handle different QR code formats:
    // 1. Plain address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
    // 2. Bitcoin URI: "bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
    // 3. Bitcoin URI with amount: "bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa?amount=0.001"
    
    String address = data.trim();
    
    // Remove bitcoin: prefix if present
    if (address.toLowerCase().startsWith('bitcoin:')) {
      address = address.substring(8);
    }
    
    // Remove query parameters if present
    if (address.contains('?')) {
      address = address.split('?')[0];
    }
    
    // Basic Bitcoin address validation
    if (_isValidBitcoinAddress(address)) {
      return address;
    }
    
    return null;
  }

  bool _isValidBitcoinAddress(String address) {
    // Basic validation for Bitcoin addresses
    // Legacy addresses (P2PKH): start with 1, length 26-35
    // Script addresses (P2SH): start with 3, length 26-35
    // Bech32 addresses (P2WPKH/P2WSH): start with bc1, length varies
    // Testnet addresses: start with m, n, 2, tb1
    
    if (address.isEmpty) return false;
    
    // Check length
    if (address.length < 26 || address.length > 62) return false;
    
    // Check format
    final RegExp bitcoinRegex = RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$|^bc1[a-z0-9]{39,59}$|^[mn2][a-km-zA-HJ-NP-Z1-9]{25,34}$|^tb1[a-z0-9]{39,59}$');
    
    return bitcoinRegex.hasMatch(address);
  }

  void _showInvalidQRDialog(String scannedData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invalid QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The scanned QR code does not contain a valid Bitcoin address.'),
            const SizedBox(height: 16),
            const Text('Scanned data:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                scannedData,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isScanning = true;
              });
            },
            child: const Text('Scan Again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _toggleFlash() {
    controller?.toggleFlash();
    setState(() {
      _flashOn = !_flashOn;
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
} 