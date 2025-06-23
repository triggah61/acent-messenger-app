import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:acent_messenger/providers/global_event_provider.dart';

class GlobalNotificationBadge extends StatelessWidget {
  final Widget child;
  final bool showUnreadCount;
  final VoidCallback? onTap;

  const GlobalNotificationBadge({
    Key? key,
    required this.child,
    this.showUnreadCount = true,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<GlobalEventProvider>(
      builder: (context, globalEventProvider, _) {
        final unreadCount = globalEventProvider.unreadMessageCount;
        final hasNotifications = globalEventProvider.hasNewNotifications;

        return Stack(
          children: [
            GestureDetector(
              onTap: onTap,
              child: child,
            ),
            if (showUnreadCount && unreadCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (!showUnreadCount && hasNotifications)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class GlobalConnectionIndicator extends StatelessWidget {
  const GlobalConnectionIndicator({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<GlobalEventProvider>(
      builder: (context, globalEventProvider, _) {
        final isConnected = globalEventProvider.isGlobalConnected;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isConnected ? Colors.green : Colors.red,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isConnected ? Icons.wifi : Icons.wifi_off,
                color: Colors.white,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                isConnected ? 'Online' : 'Offline',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<GlobalEventProvider>(
      builder: (context, globalEventProvider, _) {
        final incomingCall = globalEventProvider.incomingCall;
        
        if (incomingCall == null) return const SizedBox.shrink();
        
        return Positioned.fill(
          child: Material(
            color: Colors.black.withOpacity(0.8),
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.phone,
                      size: 60,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Incoming Call',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      incomingCall['callerName'] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            globalEventProvider.dismissIncomingCall();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(16),
                          ),
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // Handle accept call
                            globalEventProvider.dismissIncomingCall();
                            // Navigate to call screen or handle call acceptance
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(16),
                          ),
                          child: const Icon(
                            Icons.call,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class GlobalNotificationsList extends StatelessWidget {
  const GlobalNotificationsList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<GlobalEventProvider>(
      builder: (context, globalEventProvider, _) {
        final notifications = globalEventProvider.notifications;
        
        if (notifications.isEmpty) {
          return const Center(
            child: Text('No notifications'),
          );
        }
        
        return ListView.builder(
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            final notification = notifications[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: _getNotificationIcon(notification['type']),
                title: Text(notification['title'] ?? 'Notification'),
                subtitle: Text(notification['content'] ?? ''),
                trailing: Text(
                  _formatTime(notification['timestamp']),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                onTap: () {
                  // Handle notification tap
                  _handleNotificationTap(context, notification);
                },
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _getNotificationIcon(String? type) {
    switch (type) {
      case 'message':
        return const Icon(Icons.message, color: Colors.blue);
      case 'call':
        return const Icon(Icons.phone, color: Colors.green);
      case 'group':
        return const Icon(Icons.group, color: Colors.orange);
      case 'conversation':
        return const Icon(Icons.chat, color: Colors.purple);
      default:
        return const Icon(Icons.notifications, color: Colors.grey);
    }
  }
  
  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) {
        return 'Now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return '';
    }
  }
  
  void _handleNotificationTap(BuildContext context, Map<String, dynamic> notification) {
    // Handle different notification types
    switch (notification['type']) {
      case 'message':
        // Navigate to chat screen
        break;
      case 'call':
        // Navigate to call screen or show call history
        break;
      case 'group':
        // Navigate to group screen
        break;
      case 'conversation':
        // Navigate to conversation screen
        break;
      default:
        break;
    }
  }
} 