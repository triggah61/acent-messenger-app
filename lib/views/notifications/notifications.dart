import 'package:flutter/material.dart';
import '../../../constants/colors.dart';
import '../../../widgets/detailstext2.dart';
import '../../../widgets/text11.dart';
import '../../widgets/detailstext1.dart';

class ChatNotifications extends StatefulWidget {
  const ChatNotifications({super.key});

  @override
  State<ChatNotifications> createState() => _ChatNotificationsState();
}

class _ChatNotificationsState extends State<ChatNotifications> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.text3Color),
                        ),
                        height: 30,
                        width: 30,
                        child: const Icon(
                          Icons.arrow_back,
                          size: 17,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Text1(text1: 'Chat Notifications'),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.buttonColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text11(text2: '5 New', color: Colors.white),
                    )
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text1(text1: 'Today'),
                          Text11(text2: 'Mark all as read', color: AppColors.text3Color),
                        ],
                      ),
                    ),
                    // Chat Notifications List
                    ..._buildNotifications(),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNotifications() {
    return List.generate(_notifications.length, (index) {
      final notification = _notifications[index];
      return Card(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: notification['iconBackgroundColor'],
                radius: 24,
                child: Icon(
                  notification['icon'],
                  size: 28,
                  color: notification['iconColor'],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text1(text1: notification['title']),
                    Text2(text2: notification['content']),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 22),
                child: CircleAvatar(
                  radius: 5,
                  backgroundColor: Colors.deepOrange,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  final List<Map<String, dynamic>> _notifications = [
    {
      'icon': Icons.message,
      'iconColor': Colors.blue,
      'iconBackgroundColor': Colors.blue.shade100,
      'title': 'New Message',
      'content': 'John: Hey! How are you?'
    },
    {
      'icon': Icons.call_missed,
      'iconColor': Colors.red,
      'iconBackgroundColor': Colors.red.shade100,
      'title': 'Missed Call',
      'content': 'You missed a call from Lisa.'
    },
    {
      'icon': Icons.group_add,
      'iconColor': Colors.green,
      'iconBackgroundColor': Colors.green.shade100,
      'title': 'Group Invite',
      'content': 'You were added to "Flutter Devs" group.'
    },
    {
      'icon': Icons.videocam,
      'iconColor': Colors.purple,
      'iconBackgroundColor': Colors.purple.shade100,
      'title': 'Video Call',
      'content': 'Mark started a video call.'
    },
    {
      'icon': Icons.mic_off,
      'iconColor': Colors.orange,
      'iconBackgroundColor': Colors.orange.shade100,
      'title': 'Muted in Group',
      'content': 'Admin muted you in "Family Chat".'
    },
    {
      'icon': Icons.thumb_up,
      'iconColor': Colors.teal,
      'iconBackgroundColor': Colors.teal.shade100,
      'title': 'Reaction Received',
      'content': 'Mike reacted ❤️ to your message.'
    },
  ];
}
