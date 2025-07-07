import 'package:flutter/material.dart';
import '../services/permission_service.dart';

class PermissionTestWidget extends StatefulWidget {
  const PermissionTestWidget({Key? key}) : super(key: key);

  @override
  State<PermissionTestWidget> createState() => _PermissionTestWidgetState();
}

class _PermissionTestWidgetState extends State<PermissionTestWidget> {
  String _status = 'Checking permissions...';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() {
      _isLoading = true;
      _status = 'Checking permissions...';
    });

    try {
      final permissionService = PermissionService.instance;

      // Get detailed status
      final detailedStatus =
          await permissionService.getDetailedPermissionStatus();

      setState(() {
        _status = '''
Permission Status:

Microphone: ${detailedStatus['microphone']['status']}
  - Granted: ${detailedStatus['microphone']['isGranted']}
  - Denied: ${detailedStatus['microphone']['isDenied']}
  - Permanently Denied: ${detailedStatus['microphone']['isPermanentlyDenied']}

Camera: ${detailedStatus['camera']['status']}
  - Granted: ${detailedStatus['camera']['isGranted']}
  - Denied: ${detailedStatus['camera']['isDenied']}
  - Permanently Denied: ${detailedStatus['camera']['isPermanentlyDenied']}

Call Capabilities:
- Voice calls: ${permissionService.canMakeVoiceCall() ? 'Available' : 'Not available'}
- Video calls: ${permissionService.canMakeVideoCall() ? 'Available' : 'Not available'}

Permissions Initialized: ${detailedStatus['initialized']}
        ''';
      });
    } catch (e) {
      setState(() {
        _status = 'Error checking permissions: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isLoading = true;
      _status = 'Requesting permissions...';
    });

    try {
      await PermissionService.instance.initializePermissions();
      await _checkPermissions();
    } catch (e) {
      setState(() {
        _status = 'Error requesting permissions: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _requestMicrophoneOnly() async {
    setState(() {
      _isLoading = true;
      _status = 'Requesting microphone permission...';
    });

    try {
      final granted =
          await PermissionService.instance.requestMicrophonePermission();
      setState(() {
        _status = 'Microphone permission result: $granted';
      });
      await _checkPermissions();
    } catch (e) {
      setState(() {
        _status = 'Error requesting microphone permission: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.bug_report, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'Permission Test',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                _status,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _checkPermissions,
                  child: const Text('Check Status'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Request All'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _requestMicrophoneOnly,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Mic Only'),
                ),
                OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          await PermissionService.instance.openSettings();
                        },
                  child: const Text('Open Settings'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              'Use this widget to test permissions before making calls',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
