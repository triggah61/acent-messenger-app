import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  static PermissionService get instance => _instance;

  // Track permission status
  bool _microphoneGranted = false;
  bool _cameraGranted = false;
  bool _permissionsInitialized = false;

  // Getters for permission status
  bool get isMicrophoneGranted => _microphoneGranted;
  bool get isCameraGranted => _cameraGranted;
  bool get isPermissionsInitialized => _permissionsInitialized;

  /// Initialize and request all necessary permissions for the app
  Future<void> initializePermissions() async {
    try {
      debugPrint('PermissionService: Initializing permissions...');

      // Small delay to ensure app is fully loaded
      await Future.delayed(const Duration(milliseconds: 500));

      // Check current permission status first
      await _checkCurrentPermissionStatus();

      // Log detailed status before requesting
      final detailedStatus = await getDetailedPermissionStatus();
      debugPrint(
          'PermissionService: Detailed status before request: $detailedStatus');

      // Request missing permissions
      await _requestMissingPermissions();

      _permissionsInitialized = true;
      debugPrint('PermissionService: Permissions initialization complete');
      debugPrint(
          'PermissionService: Final status - Microphone: $_microphoneGranted, Camera: $_cameraGranted');
    } catch (e) {
      debugPrint('PermissionService: Error initializing permissions: $e');
      debugPrint('PermissionService: Stack trace: ${StackTrace.current}');
      _permissionsInitialized = true; // Mark as initialized even if failed
    }
  }

  /// Check current permission status
  Future<void> _checkCurrentPermissionStatus() async {
    final micStatus = await Permission.microphone.status;
    final camStatus = await Permission.camera.status;

    _microphoneGranted = micStatus.isGranted;
    _cameraGranted = camStatus.isGranted;

    debugPrint(
        'PermissionService: Current status - Microphone: $micStatus, Camera: $camStatus');
  }

  /// Request missing permissions
  Future<void> _requestMissingPermissions() async {
    final List<Permission> toRequest = [];

    if (!_microphoneGranted) {
      toRequest.add(Permission.microphone);
    }

    if (!_cameraGranted) {
      toRequest.add(Permission.camera);
    }

    if (toRequest.isNotEmpty) {
      debugPrint(
          'PermissionService: Requesting permissions: ${toRequest.map((p) => p.toString()).join(', ')}');

      try {
        final results = await toRequest.request();

        // Update status based on results
        if (results.containsKey(Permission.microphone)) {
          _microphoneGranted =
              results[Permission.microphone]?.isGranted ?? false;
          debugPrint(
              'PermissionService: Microphone permission result: ${results[Permission.microphone]}');
        }

        if (results.containsKey(Permission.camera)) {
          _cameraGranted = results[Permission.camera]?.isGranted ?? false;
          debugPrint(
              'PermissionService: Camera permission result: ${results[Permission.camera]}');
        }

        debugPrint('PermissionService: All permission results: $results');

        // If permissions were denied, show helpful message
        if (!_microphoneGranted || !_cameraGranted) {
          debugPrint(
              'PermissionService: Some permissions were denied. Users can grant them later in settings.');
        }
      } catch (e) {
        debugPrint('PermissionService: Error requesting permissions: $e');
        // Even if request fails, don't throw - app should continue
      }
    } else {
      debugPrint('PermissionService: All required permissions already granted');
    }
  }

  /// Request microphone permission specifically
  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.request();
      _microphoneGranted = status.isGranted;
      debugPrint('PermissionService: Microphone permission result: $status');
      return _microphoneGranted;
    } catch (e) {
      debugPrint(
          'PermissionService: Error requesting microphone permission: $e');
      return false;
    }
  }

  /// Request camera permission specifically
  Future<bool> requestCameraPermission() async {
    try {
      final status = await Permission.camera.request();
      _cameraGranted = status.isGranted;
      debugPrint('PermissionService: Camera permission result: $status');
      return _cameraGranted;
    } catch (e) {
      debugPrint('PermissionService: Error requesting camera permission: $e');
      return false;
    }
  }

  /// Check if permissions are sufficient for voice calls
  bool canMakeVoiceCall() {
    return _microphoneGranted;
  }

  /// Check if permissions are sufficient for video calls
  bool canMakeVideoCall() {
    return _microphoneGranted && _cameraGranted;
  }

  /// Show permission explanation dialog
  Future<bool> showPermissionRationale({
    required bool needsMicrophone,
    required bool needsCamera,
  }) async {
    // This should be called from UI context
    final List<String> permissions = [];

    if (needsMicrophone) permissions.add('Microphone');
    if (needsCamera) permissions.add('Camera');

    debugPrint(
        'PermissionService: Need to show rationale for: ${permissions.join(', ')}');

    // Return true to indicate user should be prompted
    return true;
  }

  /// Open app settings if permissions are permanently denied
  Future<void> openSettings() async {
    try {
      debugPrint('PermissionService: Opening app settings...');
      await openAppSettings();
    } catch (e) {
      debugPrint('PermissionService: Error opening app settings: $e');
    }
  }

  /// Refresh permission status (call after returning from settings)
  Future<void> refreshPermissionStatus() async {
    await _checkCurrentPermissionStatus();
    debugPrint('PermissionService: Permission status refreshed');
  }

  /// Get detailed permission status for debugging
  Future<Map<String, dynamic>> getDetailedPermissionStatus() async {
    final micStatus = await Permission.microphone.status;
    final camStatus = await Permission.camera.status;

    return {
      'microphone': {
        'status': micStatus.toString(),
        'isGranted': micStatus.isGranted,
        'isDenied': micStatus.isDenied,
        'isPermanentlyDenied': micStatus.isPermanentlyDenied,
      },
      'camera': {
        'status': camStatus.toString(),
        'isGranted': camStatus.isGranted,
        'isDenied': camStatus.isDenied,
        'isPermanentlyDenied': camStatus.isPermanentlyDenied,
      },
      'initialized': _permissionsInitialized,
    };
  }
}
