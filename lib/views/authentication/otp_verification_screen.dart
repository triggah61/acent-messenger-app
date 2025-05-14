import 'package:chattingapp/constants/config.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../../constants/colors.dart';
import '../../commonwidgets/botttommnavigationbar.dart';
import '../../widgets/custombtn.dart';
import '../../widgets/detailstext1.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_request.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phone;
  final String dialCode;
  final String traceId;

  const OtpVerificationScreen({
    super.key,
    required this.phone,
    required this.dialCode,
    required this.traceId,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _isResending = false;
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

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
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onOtpChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  Future<void> _handleResendOtp() async {
    if (_isResending) return;
    setState(() {
      _isResending = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/auth/resendOTP'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'traceId': widget.traceId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data']['token'] != null) {
          // Implement resend OTP functionality
          print("Resending OTP");
        }
      }
    } catch (e) {
      print("Error resending OTP: $e");
    } finally {
      setState(() {
        _isResending = false;
      });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpControllers.map((controller) => controller.text).join();
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the complete OTP')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/auth/login/verify'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'code': otp,
          'phone': widget.phone,
          'dialCode': widget.dialCode,
          'traceId': widget.traceId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data']['token'] != null) {
          // Use AuthProvider to handle login success
          await Provider.of<AuthProvider>(context, listen: false)
              .handleLoginSuccess(data['data']['token']);

          if (mounted) {
            Navigator.pushReplacement(
              context,
              _createRoute(const BottomNavBarScreen()),
            );
          }
        }
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'].toString())),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(height: 100),
                  Text1(
                    text1: 'Acent Messenger',
                    color: Colors.white,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          // OTP Form
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
                            text1: 'OTP Verification',
                            size: 24,
                            color: AppColors.buttonColor,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Enter the 6-digit code sent to\n${widget.dialCode}${widget.phone}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(
                              6,
                              (index) => SizedBox(
                                width: 45,
                                child: TextField(
                                  controller: _otpControllers[index],
                                  focusNode: _focusNodes[index],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  maxLength: 1,
                                  decoration: InputDecoration(
                                    counterText: '',
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color:
                                            AppColors.textFormFieldBorderColor,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: AppColors.buttonColor,
                                      ),
                                    ),
                                  ),
                                  onChanged: (value) =>
                                      _onOtpChanged(value, index),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          CustomButton(
                            text: _isLoading ? 'Verifying...' : 'Verify OTP',
                            onTap: () {
                              if (!_isLoading) {
                                _verifyOtp();
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text("Didn't receive the code? "),
                              GestureDetector(
                                onTap: () {
                                  // Implement resend OTP functionality
                                  _handleResendOtp();
                                },
                                child: _isResending
                                    ? const Text(
                                        'Resending...', 
                                        style: TextStyle(
                                          color: AppColors.buttonColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : const Text(
                                        'Resend',
                                        style: TextStyle(
                                          color: AppColors.buttonColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ],
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
