import 'package:chattingapp/views/contacts/contacts.dart';
import 'package:flutter/material.dart';

import '../../Constants/colors.dart';
import '../camera/camera.dart';
import '../chatcalls/chatcalls.dart';
import '../createpoll/createpoll.dart';
import '../documents/documents.dart';
import '../gallery/gallery.dart';
import '../record/record.dart';
import '../sendlocation/sendlocation.dart';

class Conversations extends StatefulWidget {
  const Conversations({super.key});

  @override
  State<Conversations> createState() => _ConversationsState();
}

class _ConversationsState extends State<Conversations> {
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

  void _handleCameraAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CameraScreen()), // Replace CameraScreen with your actual camera widget/route
    );
  }

  void _handleRecordAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => RecordScreen()), // Replace RecordScreen with your actual record widget/route
    );
  }
  void _handlePollAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreatePollScreen()), // Replace RecordScreen with your actual record widget/route
    );
  }

  void _handleContactAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ContactsScreen()), // Replace ContactScreen with your actual contact widget/route
    );
  }

  void _handleGalleryAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => GalleryScreen()), // Replace GalleryScreen with your actual gallery widget/route
    );
  }

  void _handleLocationAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => LocationScreen()), // Replace LocationScreen with your actual location widget/route
    );
  }

  void _handleDocumentAttachment() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DocumentScreen()), // Replace DocumentScreen with your actual document widget/route
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard if open
        FocusScope.of(context).unfocus();
        // Hide attachment sheet if visible
        if (_isAttachmentSheetVisible) {
          _hideAttachmentSheet();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.video_call),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CallScreen()),
                );

              },
            ),
            IconButton(
              icon: const Icon(Icons.phone),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CallScreen()),
                );
              },
            ),
          ],
          title: const Row(
            children: [
              CircleAvatar(
                backgroundImage:
                AssetImage('images/c2.png'), // Assuming image is in assets folder
              ),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Maddy Max',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '(+44) 50 9285 3022',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
                      Text(
                        'Yesterday',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const MessageBubble(
                        message:
                        'Hai Rizal, I\'m on the way to your home, Please wait a moment. Thanks!',
                        isSent: false,
                        time: '4:26 Am',
                      ),
                      const SizedBox(height: 8),
                      const MessageBubble(
                        message: 'Sure. I\'ll be there in a minute',
                        isSent: true,
                        time: '7:22 Am',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message ...',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const CallScreen()),
                      );
                      // Implement send message functionality here
                      if (_messageController.text.isNotEmpty) {
                        // Send the message
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
            ),
          ],
        ),
        bottomSheet: _isAttachmentSheetVisible ? _buildAttachmentSheet(context) : null,
      ),
    );
  }



  Widget _buildAttachmentSheet(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.3 * 255).toInt(), 128, 128, 128),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 20,
        runSpacing: 20,
        children: [
          _AttachmentButton(
            icon: Icons.poll,
            label: 'Poll',
            onPressed: () {
              _hideAttachmentSheet();
              _handlePollAttachment(); // Navigate to the camera screen
            },
          ),
          _AttachmentButton(
            icon: Icons.person,
            label: 'Contact',
            onPressed: () {
              _hideAttachmentSheet();
              _handleContactAttachment(); // Navigate to the contact screen
            },
          ),
          _AttachmentButton(
            icon: Icons.location_on,
            label: 'My Location',
            onPressed: () {
              _hideAttachmentSheet();
              _handleLocationAttachment(); // Navigate to the location screen
            },
          ),
          _AttachmentButton(
            icon: Icons.insert_drive_file,
            label: 'Document',
            onPressed: () {
              _hideAttachmentSheet();
              _handleDocumentAttachment(); // Navigate to the document screen
            },
          ),
          _AttachmentButton(
            icon: Icons.camera_alt,
            label: 'Camera',
            onPressed: () {
              _hideAttachmentSheet();
              _handleCameraAttachment(); // Navigate to the camera screen
            },
          ),


          _AttachmentButton(
            icon: Icons.mic,
            label: 'Record',
            onPressed: () {
              _hideAttachmentSheet();
              _handleRecordAttachment(); // Navigate to the record screen
            },
          ),

          _AttachmentButton(
            icon: Icons.image,
            label: 'Gallery',
            onPressed: () {
              _hideAttachmentSheet();
              _handleGalleryAttachment(); // Navigate to the gallery screen
            },
          ),

        ],
      ),
    );
  }
}

class _AttachmentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _AttachmentButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onPressed,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.blue, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String message;
  final bool isSent;
  final String time;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isSent,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    Color bubbleColor = isSent
        ? const Color(0xFFDCF8C6) // Light green for sent
        : Colors.white; // White for received (or a light grey like #F0F0F0)
    Color textColor = Colors.black87;
    Color timeColor = Colors.grey[600]!;

    return Align(
      alignment: isSent ? Alignment.bottomRight : Alignment.bottomLeft,
      child: Container(
        padding: const EdgeInsets.all(12), // Reduced padding slightly
        margin: const EdgeInsets.symmetric(vertical: 2), // Added vertical margin
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: !isSent ? const Radius.circular(18) : const Radius.circular(12), // More rounded
            topRight: isSent ? const Radius.circular(18) : const Radius.circular(12),
            bottomLeft: const Radius.circular(18),
            bottomRight: const Radius.circular(18),
          ),
          boxShadow: [ // Added a subtle shadow for depth
            BoxShadow(
              color: Color.fromARGB((0.1 * 255).toInt(), 128, 128, 128),
              spreadRadius: 0.5,
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
          isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(
                color: textColor,
              ),
            ),
            const SizedBox(height: 2), // Reduced spacing between message and time
            Text(
              time,
              style: TextStyle(
                color: timeColor,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}











