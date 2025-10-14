import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BluetoothTestScreen extends StatefulWidget {
  const BluetoothTestScreen({super.key});

  @override
  State<BluetoothTestScreen> createState() => _BluetoothTestScreenState();
}

class _BluetoothTestScreenState extends State<BluetoothTestScreen> {
  static const MethodChannel _channel =
      MethodChannel('bluetooth_audio_service');

  String _status = 'Press button to test';
  bool _isConnected = false;
  String _deviceName = 'Unknown';

  Future<void> _testBluetooth() async {
    try {
      setState(() {
        _status = 'Testing...';
      });

      final result = await _channel.invokeMethod('checkBluetoothConnection');

      debugPrint('Bluetooth Test Result: $result');

      if (result is Map) {
        setState(() {
          _isConnected = result['isConnected'] as bool? ?? false;
          _deviceName = result['deviceName'] as String? ?? 'Unknown';
          _status =
              'Test complete!\nConnected: $_isConnected\nDevice: $_deviceName';
        });
      } else {
        setState(() {
          _status = 'Unexpected result type: ${result.runtimeType}';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
      debugPrint('Bluetooth Test Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Test'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                size: 100,
                color: _isConnected ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 20),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _testBluetooth,
                child: const Text('Test Bluetooth Detection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
