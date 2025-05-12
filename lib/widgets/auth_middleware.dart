import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../views/authentication/login_screen.dart';

class AuthMiddleware extends StatefulWidget {
  final Widget child;

  const AuthMiddleware({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<AuthMiddleware> createState() => _AuthMiddlewareState();
}

class _AuthMiddlewareState extends State<AuthMiddleware> {
  @override
  void initState() {
    super.initState();
    // Check auth status when the middleware is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthProvider>(context, listen: false).checkAuthStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        print("AuthMiddleware: ${authProvider.isAuthenticated}, ${authProvider.isInitialized}, ${authProvider.isLoading}");
        if (!authProvider.isInitialized || authProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }else if (!authProvider.isAuthenticated) {
          // return const LoginScreen();
        }


        return widget.child;
      },
    );
  }
} 