import 'package:chattingapp/constants/colors.dart';
import 'package:flutter/material.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),

        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            margin: EdgeInsets.only(top: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Color.fromARGB((0.2 * 255).toInt(), 128, 128, 128),
                  spreadRadius: 2,
                  blurRadius: 10,
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                hintText: 'Search',
                hintStyle: const TextStyle(color: Colors.grey),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 20,
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: chatData.length,
        itemBuilder: (context, index) {
          final chat = chatData[index];
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 2.0,
            ),
            child: Card(
              color: Colors.white,
              elevation: 1,
              margin: const EdgeInsets.only(bottom: 5, left: 8, right: 8),
              child: ListTile(
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: CircleAvatar(
                  backgroundImage: AssetImage(chat['image']),
                  radius: 28,
                ),
                title: Text(
                  chat['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  chat['message'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      chat['time'],
                      style: const TextStyle(color: Colors.grey),
                    ),
                    if (chat['unread'] > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.tabColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${chat['unread']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

final List<Map<String, dynamic>> chatData = [
  {
    'name': 'David Wayne',
    'message': 'Thanks a bunch! Have a great day! 😊',
    'time': '10:25',
    'unread': 5,
    'image': 'images/c4.png',
  },
  {
    'name': 'Edward Davidson',
    'message': 'Great, thanks so much! ✏️',
    'time': '22:20',
    'unread': 0,
    'image': 'images/c2.png',
  },
  {
    'name': 'Angela Kelly',
    'message': 'Appreciate it! See you soon! 🚀',
    'time': '10:45',
    'unread': 8,
    'image': 'images/c3.png',
  },
  {
    'name': 'Jean Dare',
    'message': 'Hooray! 🎉',
    'time': '20:10',
    'unread': 2,
    'image': 'images/c4.png',
  },
  {
    'name': 'Dennis Borer',
    'message': 'Your order has been successfully delivered.',
    'time': '17:32',
    'unread': 3,
    'image': 'images/c5.png',
  },
  {
    'name': 'Cayla Rath',
    'message': 'See you soon!',
    'time': '11:20',
    'unread': 1,
    'image': 'images/c3.png',
  },
  {
    'name': 'Erin Turcotte',
    'message': 'I’m ready to drop off your delivery. 🚚',
    'time': '19:25',
    'unread': 6,
    'image': 'images/c4.png',
  },
  {
    'name': 'Rodolfo Walter',
    'message': 'Appreciate it! Hope you enjoy it! ✨',
    'time': '07:35',
    'unread': 0,
    'image': 'images/c5.png',
  },
  {
    'name': 'David Wayne',
    'message': 'Thanks a bunch! Have a great day! 😊',
    'time': '10:25',
    'unread': 5,
    'image': 'images/c2.png',
  },
  {
    'name': 'Edward Davidson',
    'message': 'Great, thanks so much! ✏️',
    'time': '22:20',
    'unread': 0,
    'image': 'images/c2.png',
  },
  {
    'name': 'Angela Kelly',
    'message': 'Appreciate it! See you soon! 🚀',
    'time': '10:45',
    'unread': 8,
    'image': 'images/c3.png',
  },
  {
    'name': 'Jean Dare',
    'message': 'Hooray! 🎉',
    'time': '20:10',
    'unread': 2,
    'image': 'images/c4.png',
  },
  {
    'name': 'Dennis Borer',
    'message': 'Your order has been successfully delivered.',
    'time': '17:32',
    'unread': 3,
    'image': 'images/c5.png',
  },
  {
    'name': 'Cayla Rath',
    'message': 'See you soon!',
    'time': '11:20',
    'unread': 1,
    'image': 'images/c4.png',
  },
  {
    'name': 'Erin Turcotte',
    'message': 'I’m ready to drop off your delivery. 🚚',
    'time': '19:25',
    'unread': 6,
    'image': 'images/c3.png',
  },
  {
    'name': 'Rodolfo Walter',
    'message': 'Appreciate it! Hope you enjoy it! ✨',
    'time': '07:35',
    'unread': 0,
    'image': 'images/c2.png',
  },
];
