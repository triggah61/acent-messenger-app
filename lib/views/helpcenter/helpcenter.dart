import 'package:flutter/material.dart';


class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Help Center',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: TextFormField(
                decoration: InputDecoration(
                  hintText: 'Search for help...',
                  prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
                  suffixIcon: const Icon(Icons.tune, color: Colors.blueAccent),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildCategoryButton('General', true),
                  _buildCategoryButton('Account', false),
                  _buildCategoryButton('Chats', false),
                  _buildCategoryButton('Groups', false),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _buildHelpItem(
                    'How do I create a new account?',
                    'To create a new account, click on "Sign Up" on the login screen and follow the instructions.',
                  ),
                  _buildHelpItem(
                    'I forgot my password. How do I reset it?',
                    'Click "Forgot Password" on the login page, then follow the email instructions to reset it.',
                  ),
                  _buildHelpItem(
                    'I’m having trouble logging in. What can I do?',
                    'Make sure your credentials are correct and you have an active internet connection. Try resetting your password if needed.',
                  ),
                  _buildHelpItem(
                    'How do I create a new chat group?',
                    'Go to the chats tab, tap the "+" icon, and select "New Group". Add members and name your group.',
                  ),
                  _buildHelpItem(
                    'How do I block or report a user?',
                    'Open the user’s profile, tap the menu icon, and select "Block" or "Report".',
                  ),
                  _buildHelpItem(
                    'How does the "Seen" feature work?',
                    'When a message has been viewed, it will show as "Seen" with a timestamp below the message.',
                  ),
                  _buildHelpItem(
                    'How do I change my profile picture?',
                    'Go to your profile, tap your picture, and select a new image from your gallery or camera.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryButton(String title, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.blueAccent : Colors.white,
          foregroundColor: isSelected ? Colors.white : Colors.blueAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.blueAccent),
          ),
        ),
        onPressed: () {},
        child: Text(title),
      ),
    );
  }

  Widget _buildHelpItem(String question, String answer) {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        title: Text(question, style: TextStyle(fontWeight: FontWeight.bold)),
        trailing: Icon(Icons.chevron_right, color: Colors.blueAccent),
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(answer),
          )
        ],
      ),
    );
  }
}