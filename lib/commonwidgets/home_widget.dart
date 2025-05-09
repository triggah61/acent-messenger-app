// import 'package:doctorconsultationapp/views/notificationsss/notificationsss.dart';
// import 'package:flutter/material.dart';
//
// import '../constants/colors.dart';
//
// class HomeWidgte extends StatelessWidget {
//   const HomeWidgte({
//     super.key,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.only(top: 10),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Builder(builder: (context) {
//             return InkWell(
//               onTap: () {
//                 Scaffold.of(context).openDrawer();
//               },
//               child: const Icon(
//                 Icons.menu_outlined,
//                 color: Colors.white,
//                 size: 34,
//               ),
//             );
//           }),
//           Padding(
//             padding: const EdgeInsets.only(top: 5),
//             child: Text(
//               "Find your Consultant",
//               style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                   color: Colors.white),
//             ),
//           ),
//           GestureDetector(
//             onTap: () {
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                     builder: (context) => NotificationsScreen()),
//               );
//             },
//             child: Container(
//               height: 42,
//               width: 42,
//               padding: const EdgeInsets.all(5),
//               decoration: BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: Stack(
//                 children: [
//                   const Icon(
//                     Icons.notification_important_rounded,
//                     color: AppColors.buttonColor,
//                   ),
//                   Positioned(
//                     right: 0,
//                     top: 0,
//                     child: Container(
//                       padding: EdgeInsets.all(2),
//                       decoration: BoxDecoration(
//                         color: Colors.red,
//                         shape: BoxShape.circle,
//                       ),
//                       child: Text(
//                         "3",
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontSize: 10,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
