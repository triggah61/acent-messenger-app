import 'package:flutter/material.dart';

import '../Constants/colors.dart';
import '../Widgets/custombtn.dart';


class OrderSuccessBottomSheet extends StatelessWidget {
  const OrderSuccessBottomSheet({super.key});



  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey),
                  color: Colors.white,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.book_outlined,
                      size: 48,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 4,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                top: -20,
                left: -20,
                child: Icon(
                  Icons.check_circle,
                  size: 40,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Order Successfully',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Congratulation! your package will be picked up by the courier, please wait a moment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          CustomButton(text: 'Got to Homepage', onTap:(){})
        ],
      ),
    );
  }
}