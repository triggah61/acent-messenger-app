// import 'package:flutter/material.dart';
//
// import '../Constants/colors.dart';
// import '../Widgets/custombtn.dart';
// import '../Widgets/detailstext1.dart';
// import '../Widgets/detailstext2.dart';
// import '../views/chatflow/chat_screen.dart';
// import '../widgets/custom_outline_button.dart';
//
//
// class LocationBottomSheet extends StatelessWidget {
//   const LocationBottomSheet({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           const Center(
//             child: CircleAvatar(
//               radius: 40,
//               backgroundColor: AppColors.tabColor,
//               child: Center(
//                 child: Icon(
//                   Icons.location_pin,
//                   size: 45,
//                   color: AppColors.buttonColor,
//                 ),
//               ),
//             ),
//           ),
//           const SizedBox(height: 16),
//           const Center(
//             child: Text1(
//               text1: 'New Montgomery',
//               size: 18,
//
//             ),
//           ),
//           const SizedBox(height: 8),
//           const Center(child: Text2(text2: '4517 Washington Ave. Manchester, Kentucky 39495',)),
//           const SizedBox(height: 16),
//           const Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//
//             children: [
//               Icon(Icons.phone, size: 18),
//               SizedBox(width: 8),
//               Text('0812274616352'),
//             ],
//           ),
//           const SizedBox(height: 8),
//           const Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Icon(Icons.access_time, size: 18),
//               SizedBox(width: 8),
//               Text('09:00 AM - 05:00 PM'),
//             ],
//           ),
//           const SizedBox(height: 8),
//           const Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//
//             children: [
//               Icon(Icons.location_on, size: 18),
//               SizedBox(width: 8),
//               Text('4.5 KM from you'),
//             ],
//           ),
//           const SizedBox(height: 24),
//           CustomButton(text: 'Dial', onTap: (){
//             Navigator.push(context, MaterialPageRoute(builder: (_)=>const ChatScreen()));
//
//           }),
//           CustomOutlinedButton(text: 'Direction', onTap: (){
//             Navigator.push(context, MaterialPageRoute(builder: (_)=>const ChatScreen()));
//
//           }),
//
//         ],
//       ),
//     );
//   }
// }
