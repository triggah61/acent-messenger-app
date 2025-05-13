import 'package:chattingapp/views/authentication/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:chattingapp/constants/colors.dart';


class FingerprintSecurityScreen extends StatefulWidget {
  const FingerprintSecurityScreen({super.key});

  @override
  FingerprintSecurityScreenState createState() => FingerprintSecurityScreenState();
}

class FingerprintSecurityScreenState extends State<FingerprintSecurityScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _nextPage() {
    if (_currentPage < 2) {
      setState(() {
        _currentPage++;
      });
      _pageController.animateToPage(_currentPage,
          duration: Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => LoginScreen()));
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: NeverScrollableScrollPhysics(),
              children: [
                _buildFingerprintStep('images/fn1.png', 'Please place your finger on the sensor to get started.', Colors.grey),
                _buildFingerprintStep('images/fn2.png', 'Scanning your fingerprint...', Colors.orange),
                _buildFingerprintStep('images/fn3.png', 'Authentication successful', Colors.green, isSuccess: true),
              ],
            ),
          ),
          _buildBottomButtons(),
        ],
      ),
    );
  }

  Widget _buildFingerprintStep(String image, String text, Color borderColor, {bool isSuccess = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 2),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Image.asset(image, height: 150),
        ),
        SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15,vertical: 10),
          child: Text(
            text,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: isSuccess ? Colors.green : Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () {},
            child: Text("Skip", style: TextStyle(fontSize: 16, color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.buttonColor,
              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text("Continue", style: TextStyle(fontSize: 16, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
