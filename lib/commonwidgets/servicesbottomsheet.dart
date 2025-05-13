import 'package:flutter/material.dart';

import '../../../constants/colors.dart';

class ServicesBottomSheet extends StatelessWidget {
  const ServicesBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Delivery Rates',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 20),
          DeliveryOption(
            title: 'Regular',
            description: '2-3 Days',
            price: '\$15',
            icon: Icons.delivery_dining,
          ),
          DeliveryOption(
            title: 'Cargo',
            description: '3-6 Days',
            price: '\$31',
            icon: Icons.local_shipping,
          ),
          DeliveryOption(
            title: 'Express',
            description: '1-2 Days',
            price: '\$42',
            icon: Icons.speed,
          ),
        ],
      ),
    );
  }
}

class DeliveryOption extends StatelessWidget {
  final String title;
  final String description;
  final String price;
  final IconData icon;

  const DeliveryOption({
    super.key,
    required this.title,
    required this.description,
    required this.price,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,

      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 5),
        child: Row(
          children: [
            CircleAvatar(
                backgroundColor: AppColors.tabColor,
                child: Icon(icon, size: 30,color: AppColors.buttonColor,)),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
              ],
            ),
            const Spacer(),
            Text(
              price,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}