import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/colors.dart';
import '../../services/fcm_service.dart';
import '../../widgets/custombtn.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _isLoading = true;
  bool _enabled = true;
  bool _messageNotifications = true;
  bool _callNotifications = true;
  bool _groupNotifications = true;
  bool _sound = true;
  bool _vibration = true;

  Map<String, dynamic>? _notificationData;
  late FCMService _fcmService;

  @override
  void initState() {
    super.initState();
    _fcmService = Provider.of<FCMService>(context, listen: false);
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _fcmService.getNotificationSettings();
      if (data != null) {
        setState(() {
          _notificationData = data;
          final settings = data['settings'] ?? {};
          _enabled = settings['enabled'] ?? true;
          _messageNotifications = settings['messageNotifications'] ?? true;
          _callNotifications = settings['callNotifications'] ?? true;
          _groupNotifications = settings['groupNotifications'] ?? true;
          _sound = settings['sound'] ?? true;
          _vibration = settings['vibration'] ?? true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading notification settings: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateNotificationSettings() async {
    try {
      final settings = {
        'enabled': _enabled,
        'messageNotifications': _messageNotifications,
        'callNotifications': _callNotifications,
        'groupNotifications': _groupNotifications,
        'sound': _sound,
        'vibration': _vibration,
      };

      final success = await _fcmService.updateNotificationSettings(settings);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification settings updated')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to update notification settings')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating settings: $e')),
      );
    }
  }

  Future<void> _sendTestNotification() async {
    try {
      final success = await _fcmService.sendTestNotification();
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test notification sent')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send test notification')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending test notification: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: AppBar(
        backgroundColor: AppColors.buttonColor,
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FCM Status Card
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _fcmService.isInitialized
                                    ? Icons.check_circle
                                    : Icons.error,
                                color: _fcmService.isInitialized
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'FCM Status: ${_fcmService.isInitialized ? "Connected" : "Disconnected"}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_notificationData != null) ...[
                            Text(
                                'Active Tokens: ${_notificationData!['activeTokens'] ?? 0}'),
                            const SizedBox(height: 8),
                            if (_fcmService.currentToken != null)
                              Text(
                                'Current Token: ${_fcmService.currentToken!.substring(0, 20)}...',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Notification Settings
                  const Text(
                    'Notification Settings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Settings Cards
                  _buildSettingCard(
                    'Enable Notifications',
                    'Receive push notifications',
                    _enabled,
                    (value) {
                      setState(() {
                        _enabled = value;
                      });
                    },
                  ),

                  _buildSettingCard(
                    'Message Notifications',
                    'Get notified about new messages',
                    _messageNotifications,
                    (value) {
                      setState(() {
                        _messageNotifications = value;
                      });
                    },
                    enabled: _enabled,
                  ),

                  _buildSettingCard(
                    'Call Notifications',
                    'Get notified about incoming calls',
                    _callNotifications,
                    (value) {
                      setState(() {
                        _callNotifications = value;
                      });
                    },
                    enabled: _enabled,
                  ),

                  _buildSettingCard(
                    'Group Notifications',
                    'Get notified about group messages',
                    _groupNotifications,
                    (value) {
                      setState(() {
                        _groupNotifications = value;
                      });
                    },
                    enabled: _enabled,
                  ),

                  _buildSettingCard(
                    'Sound',
                    'Play sound for notifications',
                    _sound,
                    (value) {
                      setState(() {
                        _sound = value;
                      });
                    },
                    enabled: _enabled,
                  ),

                  _buildSettingCard(
                    'Vibration',
                    'Vibrate for notifications',
                    _vibration,
                    (value) {
                      setState(() {
                        _vibration = value;
                      });
                    },
                    enabled: _enabled,
                  ),

                  const SizedBox(height: 30),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: CustomButton(
                          text: 'Save Settings',
                          onTap: _updateNotificationSettings,
                          color: AppColors.buttonColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: CustomButton(
                          text: 'Test Notification',
                          onTap: _sendTestNotification,
                          color: Colors.grey[600]!,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Registered Devices
                  if (_notificationData != null &&
                      _notificationData!['tokens'] != null) ...[
                    const Text(
                      'Registered Devices',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final token in _notificationData!['tokens'])
                      Card(
                        color: Colors.white,
                        child: ListTile(
                          leading: Icon(
                            token['platform'] == 'android'
                                ? Icons.android
                                : token['platform'] == 'ios'
                                    ? Icons.phone_iphone
                                    : Icons.web,
                            color:
                                token['isActive'] ? Colors.green : Colors.grey,
                          ),
                          title: Text(
                            '${token['platform'].toString().toUpperCase()} Device',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Last used: ${_formatDate(token['lastUsed'])}\n'
                            'Status: ${token['isActive'] ? "Active" : "Inactive"}',
                          ),
                          trailing: Icon(
                            token['isActive']
                                ? Icons.check_circle
                                : Icons.circle,
                            color:
                                token['isActive'] ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSettingCard(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged, {
    bool enabled = true,
  }) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: enabled ? Colors.black87 : Colors.grey,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: enabled ? Colors.black54 : Colors.grey,
          ),
        ),
        value: enabled ? value : false,
        onChanged: enabled ? onChanged : null,
        activeColor: AppColors.buttonColor,
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';

    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays} days ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} hours ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} minutes ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}
