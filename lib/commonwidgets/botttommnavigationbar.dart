import 'package:acent_messenger/views/contacts/contacts.dart';
import 'package:acent_messenger/views/settings/settings.dart';
import 'package:acent_messenger/views/translator/realtime_translator.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../views/chats/chat_screen.dart';
import '../views/groups/groups.dart';
import '../models/subscription_plan.dart';
import '../widgets/subscription_modal.dart';

class BottomNavBarScreen extends StatefulWidget {
  const BottomNavBarScreen({super.key});

  @override
  BottomNavBarScreenState createState() => BottomNavBarScreenState();
}

class BottomNavBarScreenState extends State<BottomNavBarScreen> {
  int _selectedIndex = 0;

  // TODO: Replace with actual user subscription from provider/state management
  // For now, using default free plan with sample balance
  UserSubscription _userSubscription = const UserSubscription(
    planId: 'free',
    creditBalance: 100.0,
  );

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
    // Handle subscription/credits item separately (last item)
    if (index == _screens.length) {
      _showSubscriptionModal();
      return;
    }
    
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showSubscriptionModal() {
    SubscriptionModal.show(context, _userSubscription);
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
            _buildSubscriptionNavBarItem(), // Subscription/Credits
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

  BottomNavigationBarItem _buildSubscriptionNavBarItem() {
    final plan = _userSubscription.plan;
    final isSelected = _selectedIndex == _screens.length;
    
    return BottomNavigationBarItem(
      icon: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAnimatedIcon(_getPlanIcon(plan.id)),
          const SizedBox(height: 2),
          Text(
            '${_userSubscription.creditBalance.toStringAsFixed(0)}',
            style: GoogleFonts.montserrat(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : Colors.white70,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      label: 'Credits',
      tooltip: '${_userSubscription.creditBalance.toStringAsFixed(0)} Credits - ${plan.name} Plan',
    );
  }

  IconData _getPlanIcon(String planId) {
    switch (planId) {
      case 'free':
        return Icons.free_breakfast;
      case 'standard':
        return Icons.star;
      case 'premium':
        return Icons.diamond;
      default:
        return Icons.workspace_premium;
    }
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
