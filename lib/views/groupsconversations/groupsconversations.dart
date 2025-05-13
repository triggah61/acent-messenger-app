import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../groupscalls/groupscalls.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  bool _isAttachmentSheetVisible = false;
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _toggleAttachmentSheet() {
    setState(() {
      _isAttachmentSheetVisible = !_isAttachmentSheetVisible;
    });
  }

  void _hideAttachmentSheet() {
    setState(() {
      _isAttachmentSheetVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_isAttachmentSheetVisible) {
          _hideAttachmentSheet();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundImage: AssetImage('images/c2.png'),
              ),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Devs Group',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    '5 Members Online',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.video_call, color: Colors.black),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GroupsCallScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.phone, color: Colors.black),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GroupsCallScreen()),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                reverse: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildMessage('images/c2.png', 'Alice', 'Hey everyone! Hows itgoing?', '10:00 AM', false),
                          _buildMessage('images/c3.png', 'Bob', 'Doing great! Just working on some Flutter projects.', '10:05 AM', false),
                      _buildMessage('images/c4.png', 'Charlie', 'Same here! Excited for the new Flutter updates!', '10:10 AM', false),_buildMessage('images/c2.png', 'Alice', 'Hey everyone! Hows itgoing?', '10:00 AM', false),
                          _buildMessage('images/c3.png', 'Bob', 'Doing great! Just working on some Flutter projects.', '10:05 AM', false),
                      _buildMessage('images/c4.png', 'Charlie', 'Same here! Excited for the new Flutter updates!', '10:10 AM', false),_buildMessage('images/c2.png', 'Alice', 'Hey everyone! Hows itgoing?', '10:00 AM', false),
                          _buildMessage('images/c3.png', 'Bob', 'Doing great! Just working on some Flutter projects.', '10:05 AM', false),
                      _buildMessage('images/c4.png', 'Charlie', 'Same here! Excited for the new Flutter updates!', '10:10 AM', false),
                      _buildMessage('images/c2.png', 'You', 'Awesome! Have you tried the new animations package?', '10:15 AM', true),
                    ],
                  ),
                ),
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(String avatar, String sender, String message, String time, bool isSent) {
    return Align(
      alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment:
          isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isSent)
              CircleAvatar(
                backgroundImage: AssetImage(avatar),
                radius: 20,
              ),
            SizedBox(width: 8),
            Container(
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: isSent ? Colors.blueAccent : Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isSent)
                    Text(
                      sender,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSent ? Colors.white : Colors.black,
                      ),
                    ),
                  Text(
                    message,
                    style: TextStyle(
                      color: isSent ? Colors.white : Colors.black,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      time,
                      style: TextStyle(
                        fontSize: 10,
                        color: isSent ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgColor,
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                color: Colors.grey, size: 30),
            onPressed: _toggleAttachmentSheet,
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message ...',
                border: InputBorder.none,
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          IconButton(
            onPressed: () {
              if (_messageController.text.isNotEmpty) {
                _messageController.clear();
              }
            },
            icon: const Icon(
              Icons.send,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }
}