import 'package:acent_messenger/views/contacts/contacts.dart';
import 'package:acent_messenger/views/settings/settings.dart';
import 'package:acent_messenger/views/translator/realtime_translator.dart';
import 'package:flutter/material.dart';

import '../views/chats/chat_screen.dart';
import '../views/groups/groups.dart';

class BottomNavBarScreen extends StatefulWidget {
  const BottomNavBarScreen({super.key});

  @override
  BottomNavBarScreenState createState() => BottomNavBarScreenState();
}

class BottomNavBarScreenState extends State<BottomNavBarScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    HomeScreen(),
    GroupChatList(),
    ContactsScreen(),
    // CallsScreen(),
    const RealtimeTranslator(),
    // SearchScreen(),
    SettingsScreen()
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blueAccent, Colors.purpleAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: BottomNavigationBar(
          items: [
            _buildBottomNavBarItem(Icons.chat, 'Chats'), // Chats Screen
            _buildBottomNavBarItem(Icons.group, 'Groups'), // Groups Screen
            _buildBottomNavBarItem(
                Icons.contacts, 'Contacts'), // Contacts Screen
            // _buildBottomNavBarItem(Icons.call, 'Calls'),         // Calls Screen
            _buildBottomNavBarItem(
                Icons.translate, 'Translator'), // Translator Screen
            // _buildBottomNavBarItem(Icons.search, 'Search'),      // Search Screen
            _buildBottomNavBarItem(
                Icons.settings, 'Settings'), // Settings Screen
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          showUnselectedLabels: true,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor:
              Colors.transparent, // Transparent background to apply gradient
        ),
      ),
    );
  }

  BottomNavigationBarItem _buildBottomNavBarItem(IconData icon, String label) {
    return BottomNavigationBarItem(
      icon: _buildAnimatedIcon(icon),
      label: label,
    );
  }

  Widget _buildAnimatedIcon(IconData iconData) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return ScaleTransition(
          scale: animation,
          child: child,
        );
      },
      child: Icon(
        iconData,
        key: ValueKey<IconData>(iconData),
        size: 30,
      ),
    );
  }
}
