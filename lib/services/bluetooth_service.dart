import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';

/// Service for detecting and managing Bluetooth audio devices
class BluetoothService {
  static final BluetoothService _instance = BluetoothService._internal();
  factory BluetoothService() => _instance;
  BluetoothService._internal();

  static const MethodChannel _channel =
      MethodChannel('bluetooth_audio_service');

  StreamController<BluetoothDeviceInfo>? _deviceController;
  Stream<BluetoothDeviceInfo>? get deviceStream => _deviceController?.stream;

  /// Initialize the Bluetooth service
  Future<void> initialize() async {
    try {
      _deviceController = StreamController<BluetoothDeviceInfo>.broadcast();

      // Set up method call handler for device updates
      _channel.setMethodCallHandler(_handleMethodCall);

      debugPrint('BluetoothService: Initialized successfully');
    } catch (e) {
      debugPrint('BluetoothService: Initialization failed: $e');
    }
  }

  /// Handle method calls from native code
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceConnected':
        final deviceName = call.arguments['deviceName'] as String?;
        _deviceController?.add(BluetoothDeviceInfo(
          isConnected: true,
          deviceName: deviceName ?? 'Unknown Device',
        ));
        break;
      case 'onDeviceDisconnected':
        _deviceController?.add(BluetoothDeviceInfo(
          isConnected: false,
          deviceName: 'No device',
        ));
        break;
    }
  }

  /// Check if a Bluetooth audio device is connected
  Future<BluetoothDeviceInfo> checkConnection() async {
    try {
      debugPrint('BluetoothService: Checking Bluetooth connection...');

      final result = await _channel.invokeMethod('checkBluetoothConnection');

      if (result is Map) {
        final isConnected = result['isConnected'] as bool? ?? false;
        final deviceName = result['deviceName'] as String? ?? 'No device';

        debugPrint(
            'BluetoothService: Connected: $isConnected, Device: $deviceName');

        return BluetoothDeviceInfo(
          isConnected: isConnected,
          deviceName: deviceName,
        );
      }

      return BluetoothDeviceInfo(
        isConnected: false,
        deviceName: 'No device',
      );
    } catch (e) {
      debugPrint('BluetoothService: Error checking connection: $e');
      return BluetoothDeviceInfo(
        isConnected: false,
        deviceName: 'No device',
      );
    }
  }

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    try {
      final result = await _channel.invokeMethod('requestBluetoothPermissions');
      return result as bool? ?? false;
    } catch (e) {
      debugPrint('BluetoothService: Error requesting permissions: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _deviceController?.close();
  }
}

/// Bluetooth device information
class BluetoothDeviceInfo {
  final bool isConnected;
  final String deviceName;

  BluetoothDeviceInfo({
    required this.isConnected,
    required this.deviceName,
  });

  @override
  String toString() {
    return 'BluetoothDeviceInfo(isConnected: $isConnected, deviceName: $deviceName)';
  }
}
