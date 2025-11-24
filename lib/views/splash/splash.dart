import 'package:acent_messenger/views/chats/chat_screen.dart';
import 'package:acent_messenger/views/authentication/login_screen.dart';
import 'package:acent_messenger/views/profile/profile_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:acent_messenger/providers/auth_provider.dart';
import 'package:acent_messenger/commonwidgets/botttommnavigationbar.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);

    // Initialize authentication check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().checkAuthStatus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isProfileComplete(AuthProvider authProvider) {
    final profile = authProvider.profile;
    return profile != null &&
        profile.firstName != null &&
        profile.firstName!.isNotEmpty &&
        profile.lastName != null &&
        profile.lastName!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade800,
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          // If still loading, show splash screen
          if (authProvider.isLoading) {
            return _buildSplashContent();
          }

          // Once loading is done, navigate based on auth state
          WidgetsBinding.instance.addPostFrameCallback((_) {
            print(
                "SplashScreen - _buildSplashContent: isLoading: ${authProvider.isLoading}; Auth status: ${authProvider.isAuthenticated}; token: ${authProvider.token}");
            if (authProvider.isAuthenticated) {
              // Check if profile is complete
              if (_isProfileComplete(authProvider)) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const BottomNavBarScreen()),
                );
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileSetupScreen()),
                );
              }
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            }
          });

          // Return splash screen while navigation is happening
          return _buildSplashContent();
        },
      ),
    );
  }

  Widget _buildSplashContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color.fromARGB((0.5 * 255).toInt(), 68, 138, 255),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/app_icon.png',
                width: 80,
                height: 80,
                fit: BoxFit.contain,
              )
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Q Messenger",
            style: GoogleFonts.montserrat(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Stay connected with your friends",
            style: GoogleFonts.montserrat(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 40),
          const SpinKitFadingCircle(
            color: Colors.white,
            size: 50,
          ),
        ],
      ),
    );
  }
}
