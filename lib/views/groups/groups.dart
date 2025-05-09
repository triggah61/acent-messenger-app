import 'package:flutter/material.dart';
import 'package:flutter_image_stack/flutter_image_stack.dart';
import '../groupsconversations/groupsconversations.dart';

class GroupChatList extends StatelessWidget {
  const GroupChatList({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          centerTitle: true,
          title: const Text(
            'Groups',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: const ChatListView(),
      ),
    );
  }
}

class ChatListView extends StatelessWidget {
  const ChatListView({super.key});

  @override
  Widget build(BuildContext context) {
    List<GroupChat> chats = [
      GroupChat("Diamond Team 🌟", "Thanks a bunch! Have a great day! 😊", "18:25", 5, [
        'https://randomuser.me/api/portraits/men/1.jpg',
        'https://randomuser.me/api/portraits/women/2.jpg',
        'https://randomuser.me/api/portraits/men/3.jpg'
      ]),

      GroupChat("My Charity Group ❤", "Appreciate it! See you soon! ", "08/05", 10, [
        'https://randomuser.me/api/portraits/men/6.jpg',
        'https://randomuser.me/api/portraits/women/7.jpg'
      ]),
      GroupChat("Diamond Team 🌟", "Thanks a bunch! Have a great day! 😊", "18:25", 5, [
        'https://randomuser.me/api/portraits/men/1.jpg',
        'https://randomuser.me/api/portraits/women/2.jpg',
        'https://randomuser.me/api/portraits/men/3.jpg'
      ]), GroupChat("My Charity Group ❤", "Appreciate it! See you soon! ", "08/05", 10, [
        'https://randomuser.me/api/portraits/men/6.jpg',
        'https://randomuser.me/api/portraits/women/7.jpg'
      ]),
      GroupChat("Diamond Team 🌟", "Thanks a bunch! Have a great day! 😊", "18:25", 5, [
        'https://randomuser.me/api/portraits/men/1.jpg',
        'https://randomuser.me/api/portraits/women/2.jpg',
        'https://randomuser.me/api/portraits/men/3.jpg'
      ]),
      GroupChat("My Charity Group ❤", "Appreciate it! See you soon! ", "08/05", 10, [
        'https://randomuser.me/api/portraits/men/6.jpg',
        'https://randomuser.me/api/portraits/women/7.jpg'
      ]),
      GroupChat("Diamond Team 🌟", "Thanks a bunch! Have a great day! 😊", "18:25", 5, [
        'https://randomuser.me/api/portraits/men/1.jpg',
        'https://randomuser.me/api/portraits/women/2.jpg',
        'https://randomuser.me/api/portraits/men/3.jpg'
      ]), GroupChat("My Charity Group ❤", "Appreciate it! See you soon! ", "08/05", 10, [
        'https://randomuser.me/api/portraits/men/6.jpg',
        'https://randomuser.me/api/portraits/women/7.jpg'
      ]),
      GroupChat("Diamond Team 🌟", "Thanks a bunch! Have a great day! 😊", "18:25", 5, [
        'https://randomuser.me/api/portraits/men/1.jpg',
        'https://randomuser.me/api/portraits/women/2.jpg',
        'https://randomuser.me/api/portraits/men/3.jpg'
      ]), GroupChat("My Charity Group ❤", "Appreciate it! See you soon! ", "08/05", 10, [
        'https://randomuser.me/api/portraits/men/6.jpg',
        'https://randomuser.me/api/portraits/women/7.jpg'
      ]),
      GroupChat("Diamond Team 🌟", "Thanks a bunch! Have a great day! 😊", "18:25", 5, [
        'https://randomuser.me/api/portraits/men/1.jpg',
        'https://randomuser.me/api/portraits/women/2.jpg',
        'https://randomuser.me/api/portraits/men/3.jpg'
      ]),
    ];

    return ListView.builder(
      itemCount: chats.length,
      itemBuilder: (context, index) {
        return ChatTile(chat: chats[index]);
      },
    );
  }
}

class ChatTile extends StatelessWidget {
  final GroupChat chat;

  const ChatTile({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const GroupChatScreen(),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 4, spreadRadius: 1),
          ],
        ),
        child: ListTile(
          leading: FlutterImageStack(
            imageList: chat.avatars,
            showTotalCount: true,
            totalCount: chat.avatars.length,
            itemRadius: 50,
            itemCount: 3,
            itemBorderWidth: 2,
          ),
          title: Text(
            chat.groupName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            chat.lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[600]),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                chat.timestamp,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              if (chat.unreadMessages > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    chat.unreadMessages.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GroupChat {
  final String groupName;
  final String lastMessage;
  final String timestamp;
  final int unreadMessages;
  final List<String> avatars;

  GroupChat(this.groupName, this.lastMessage, this.timestamp, this.unreadMessages, this.avatars);
}
