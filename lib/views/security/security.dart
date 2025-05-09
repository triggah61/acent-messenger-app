import 'package:chattingapp/Constants/colors.dart';
import 'package:flutter/material.dart';



class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool securityEnabled = true;
  bool pinSecurityEnabled = false;
  bool faceRecognitionEnabled = false;
  bool fingerprintSecurityEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {},
        ),
        title: const Text('Security', style: TextStyle(color: Colors.black)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSecurityItem(
              icon: Icons.security,
              title: 'Security',
              value: securityEnabled,
              onChanged: (newValue) => setState(() => securityEnabled = newValue),
            ),
            _buildSecurityItem(
              icon: Icons.lock,
              title: 'PIN Security',
              value: pinSecurityEnabled,
              onChanged: (newValue) => setState(() => pinSecurityEnabled = newValue),
            ),
            _buildSecurityItem(
              icon: Icons.face,
              title: 'Face Recognition',
              value: faceRecognitionEnabled,
              onChanged: (newValue) => setState(() => faceRecognitionEnabled = newValue),
            ),
            _buildSecurityItem(
              icon: Icons.fingerprint,
              title: 'Fingerprint Security',
              value: fingerprintSecurityEnabled,
              onChanged: (newValue) => setState(() => fingerprintSecurityEnabled = newValue),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit, color: Colors.white),
                label: const Text('Change PIN',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                onPressed: () {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityItem({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue[700], size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.blue[600],
            ),
          ],
        ),
      ),
    );
  }
}
