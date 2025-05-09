import 'package:flutter/material.dart';


import '../Constants/colors.dart';
import '../Widgets/custombtn.dart';
import '../Widgets/detailstext1.dart';
import '../Widgets/detailstext2.dart';
import 'ordersucessbottomsheet.dart';

class PaymentBottomSheet extends StatefulWidget {
  const PaymentBottomSheet({super.key});

  @override
  State<PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends State<PaymentBottomSheet> {
  bool _isTrackyBalanceSelected = false;
  bool _isMastercardSelected = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text1(
          text1:   'Payment Method',
          size: 18,
          ),
          const SizedBox(height: 20),
          PaymentOption(
            icon: Icons.monetization_on,
            title: 'Tracky Balance',
            subtitle: '\$4.875.00',
            isSelected: _isTrackyBalanceSelected,
            onTap: () {
              setState(() {
                _isTrackyBalanceSelected = !_isTrackyBalanceSelected;
                _isMastercardSelected = false; // Deselect Mastercard
              });
            },
          ),
          PaymentOption(
            icon: Icons.credit_card,
            title: 'Mastercard',
            subtitle: '6895 3526 8456 ****',
            isSelected: _isMastercardSelected,
            onTap: () {
              setState(() {
                _isMastercardSelected = !_isMastercardSelected;
                _isTrackyBalanceSelected = false; // Deselect Tracky Balance
              });
            },
          ),
          const SizedBox(height: 24),
          CustomButton(text: 'ConfirmPayment', onTap:(){
            showModalBottomSheet(
              context: context,
              builder: (context) => const OrderSuccessBottomSheet(),
            );


          }),
        ],
      ),
    );
  }
}

class PaymentOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const PaymentOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 10,vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.buttonColor : AppColors.bgColor, // Change border color based on selection
            width: 2, // Set border width
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.tabColor,
                child: Icon(icon, size: 25,color: AppColors.buttonColor,)),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text1(
                 text1:  title,
                 size: 14,
                ),
                const SizedBox(height: 8),
                Text2(
                 text2:  subtitle,
                ),
              ],
            ),
            const Spacer(),
            Radio(
              value: isSelected,
              groupValue: true,
              onChanged: (value) {
                onTap();
              },
              activeColor: AppColors.buttonColor,
            ),
          ],
        ),
      ),
    );
  }
}