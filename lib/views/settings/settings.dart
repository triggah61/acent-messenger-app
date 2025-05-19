import 'package:chattingapp/views/helpcenter/helpcenter.dart';
import 'package:chattingapp/views/notifications/notifications.dart';
import 'package:chattingapp/views/profile/profilescreen.dart';
import 'package:chattingapp/views/search/search.dart';
import 'package:flutter/material.dart';

import '../chats/chat_screen.dart';
import '../security/security.dart';
import '../userinfo/userinfor.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121829),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 16),
                  const Text('Settings',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: ListView(
                    children: [
                      _buildSettingsItem(
                        context: context,
                        icon: Icons.person,
                        title: 'User Info',
                        subtitle: 'Privacy, security, change number',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const UserInformationScreen(),
                            ),
                          );
                        },
                      ), _buildSettingsItem(
                        context: context,
                        icon: Icons.person,
                        title: 'Profile',
                        subtitle: 'email, number',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ProfileScreen(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsItem(
                        context: context,
                        icon: Icons.notifications,
                        title: 'Notifications',
                        subtitle: 'Messages, group, and others',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ChatNotifications(),
                            ),
                          );
                        },
                      ),
                      _buildSettingsItem(
                        context: context,
                        icon: Icons.help_outline,
                        title: 'Help',
                        subtitle: 'Help center, contact us, privacy policy',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const HelpCenterScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey[100],
              radius: 24,
              child: Icon(icon, color: Colors.grey[600]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
