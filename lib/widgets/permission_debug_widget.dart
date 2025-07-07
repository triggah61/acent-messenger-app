import 'package:flutter/material.dart';
import '../services/permission_service.dart';

class PermissionDebugWidget extends StatefulWidget {
  const PermissionDebugWidget({Key? key}) : super(key: key);

  @override
  State<PermissionDebugWidget> createState() => _PermissionDebugWidgetState();
}

class _PermissionDebugWidgetState extends State<PermissionDebugWidget> {
  Map<String, dynamic>? _permissionStatus;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPermissionStatus();
  }

  Future<void> _loadPermissionStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final status =
          await PermissionService.instance.getDetailedPermissionStatus();
      setState(() {
        _permissionStatus = status;
      });
    } catch (e) {
      debugPrint('PermissionDebugWidget: Error loading permission status: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await PermissionService.instance.initializePermissions();
      await _loadPermissionStatus();
    } catch (e) {
      debugPrint('PermissionDebugWidget: Error requesting permissions: $e');
    } finally {
      setState(() {
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
                const Icon(Icons.settings, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Permission Debug',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isLoading ? null : _loadPermissionStatus,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              )
            else if (_permissionStatus != null) ...[
              _buildPermissionTile(
                'Microphone',
                _permissionStatus!['microphone'],
                Icons.mic,
              ),
              const SizedBox(height: 8),
              _buildPermissionTile(
                'Camera',
                _permissionStatus!['camera'],
                Icons.videocam,
              ),
              const SizedBox(height: 16),

              // Call capabilities
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Call Capabilities',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.call,
                          size: 16,
                          color: PermissionService.instance.canMakeVoiceCall()
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Voice calls: ${PermissionService.instance.canMakeVoiceCall() ? 'Available' : 'Not available'}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.videocam,
                          size: 16,
                          color: PermissionService.instance.canMakeVideoCall()
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Video calls: ${PermissionService.instance.canMakeVideoCall() ? 'Available' : 'Not available'}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _requestPermissions,
                      child: const Text('Request Permissions'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              await PermissionService.instance.openSettings();
                            },
                      child: const Text('Open Settings'),
                    ),
                  ),
                ],
              ),
            ] else
              const Center(
                child: Text('Failed to load permission status'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile(
      String name, Map<String, dynamic> permissionData, IconData icon) {
    final isGranted = permissionData['isGranted'] as bool;
    final status = permissionData['status'] as String;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isGranted ? Colors.green : Colors.red,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isGranted ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isGranted ? Icons.check_circle : Icons.error,
            color: isGranted ? Colors.green : Colors.red,
          ),
        ],
      ),
    );
  }
}
