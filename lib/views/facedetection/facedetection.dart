import 'package:flutter/material.dart';
import 'package:chattingapp/Constants/colors.dart';

import '../fingerprint/fingerprint.dart';

class FaceRecognitionScreen extends StatefulWidget {
  const FaceRecognitionScreen({super.key});

  @override
  FaceRecognitionScreenState createState() => FaceRecognitionScreenState();
}

class FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  int _currentIndex = 0;
  final List<String> _faceImages = [
    'images/fi1.png',
    'images/fi2.png',
    'images/fi3.png',
  ];

  void _nextStep() {
    if (_currentIndex < _faceImages.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => FingerprintSecurityScreen()),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'images/bgprofile.png', // Background image of the person
              fit: BoxFit.cover,
              height: 400,
              width: 400,
            ),
          ),
          Positioned.fill(
            top: 130,

            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  _faceImages[_currentIndex],
                  height: 400,
                ),
                SizedBox(height: 20),
                Text(
                  "Face Recognition",
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 10),
                Text(
                  "Secure your account with your face",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: Text("Skip",
                          style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ),
                    ElevatedButton(
                      onPressed: _nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.buttonColor,
                        padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text("Continue", style: TextStyle(fontSize: 16,color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
