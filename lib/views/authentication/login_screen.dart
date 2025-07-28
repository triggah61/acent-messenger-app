import 'package:acent_messenger/constants/config.dart';
import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../constants/colors.dart';
import '../../widgets/custombtn.dart';
import '../../widgets/detailstext1.dart';
import 'otp_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _rememberMe = false;
  bool _isLoading = false;
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String _selectedCountryCode = '+1'; // Default country code
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Enhanced input validation
    if (_phoneController.text.isEmpty) {
      _showErrorMessage('Please enter your phone number');
      return;
    }

    // Validate phone number format (basic validation)
    final phoneNumber = _phoneController.text.trim();
    if (phoneNumber.length < 5) {
      _showErrorMessage('Please enter a valid phone number');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/auth/loginRequest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'dialCode': _selectedCountryCode,
          'phone': phoneNumber,
        }),
      );

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await _handleResponse(response);
      } else {
        setState(() {
          _isLoading = false;
        });
        _showErrorMessage(responseBody['message'].toString());
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
    } on http.ClientException catch (e) {
      _showErrorMessage('Network error: Please check your internet connection');
    } on FormatException catch (e) {
      _showErrorMessage('Invalid response from server');
    } catch (e) {
      print('Login error: $e'); // For debugging
      _showErrorMessage('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleResponse(http.Response response) async {
    try {
      // Parse response body safely
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        } else {
          throw FormatException('Invalid JSON response format');
        }
      } catch (e) {
        throw FormatException('Invalid JSON response');
      }

      if (response.statusCode == 200) {
        // Success case
        if (data['data'] != null && data['data']['traceId'] != null) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OtpVerificationScreen(
                  phone: _phoneController.text.trim(),
                  dialCode: _selectedCountryCode,
                  traceId: data['data']['traceId'],
                ),
              ),
            );
          }
        } else {
          // Success but no traceId - show server message or generic error
          final message =
              data['message']?.toString() ?? 'Login failed. Please try again.';
          _showErrorMessage(message);
        }
      } else {
        // Handle different HTTP error codes
        String errorMessage;

        switch (response.statusCode) {
          case 400:
            errorMessage =
                data['message']?.toString() ?? 'Invalid phone number format';
            break;
          case 401:
            errorMessage =
                'Invalid credentials. Please check your phone number.';
            break;
          case 404:
            errorMessage =
                data['message']?.toString() ?? 'Phone number not found';
            break;
          case 429:
            errorMessage = 'Too many login attempts. Please try again later.';
            break;
          case 500:
            errorMessage = 'Server error. Please try again later.';
            break;
          default:
            errorMessage = data['message']?.toString() ??
                'Login failed. Please try again.';
        }

        _showErrorMessage(errorMessage);
      }
    } catch (e) {
      throw FormatException('Failed to process server response');
    }
  }

  void _showErrorMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background with title
          Container(
            width: double.infinity,
            color: AppColors.buttonColor,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(height: 90),
                  Image.asset(
                    'assets/images/app_icon_white.png',
                    width: 60,
                    height: 60,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: 10),
                  Text1(
                    text1: 'Q Messenger',
                    color: Colors.white,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          // Login Form
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: _slideAnimation,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          const Text1(
                            text1: 'Login',
                            size: 24,
                            color: AppColors.buttonColor,
                          ),
                          const SizedBox(height: 20),
                          // Phone Number Input with Country Code
                          Container(
                            height: 42,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.textFormFieldBorderColor),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: Row(
                              children: [
                                CountryCodePicker(
                                  onChanged: (CountryCode countryCode) {
                                    setState(() {
                                      _selectedCountryCode =
                                          countryCode.dialCode!;
                                    });
                                  },
                                  initialSelection: 'US',
                                  favorite: const ['US', 'GB', 'IN'],
                                  showCountryOnly: false,
                                  showOnlyCountryWhenClosed: false,
                                  alignLeft: false,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                ),
                                Expanded(
                                  child: TextFormField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      hintText: 'Phone Number',
                                      contentPadding:
                                          EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CustomButton(
                            text: _isLoading ? 'Logging in...' : 'Login',
                            onTap: () {
                              if (!_isLoading) {
                                _handleLogin();
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PageRouteBuilder _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );
  }
}
