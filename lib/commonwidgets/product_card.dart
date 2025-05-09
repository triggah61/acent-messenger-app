// import 'package:flutter/material.dart';
// import 'package:google_fonts/google_fonts.dart'; // For modern fonts
// import '../../../Constants/colors.dart';
// import '../Screens/Home/details.dart';
//
// class ProductCard extends StatelessWidget {
//   final String imagePath;
//   final String name;
//   final String price;
//   final String distance;
//   final String availability;
//
//   const ProductCard({
//     super.key,
//     required this.imagePath,
//     required this.name,
//     required this.price,
//     required this.distance,
//     required this.availability,
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return GestureDetector(
//       onTap: () {
//         Navigator.push(
//           context,
//           MaterialPageRoute(
//             builder: (context) => const ParkingDetailsScreen(),
//           ),
//         );
//       },
//       child: Card(
//         elevation: 6,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(15),
//         ),
//         margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
//         child: Column(
//           children: [
//             // Animated image with a hero effect
//             Hero(
//               tag: name,
//               child: ClipRRect(
//                 borderRadius: const BorderRadius.only(
//                   topLeft: Radius.circular(15),
//                   topRight: Radius.circular(15),
//                 ),
//                 child: Image.asset(
//                   imagePath,
//                   height: 120,
//                   width: double.infinity,
//                   fit: BoxFit.cover,
//                 ),
//               ),
//             ),
//             const SizedBox(height: 3),
//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 10),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     name,
//                     style: GoogleFonts.roboto(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: AppColors.text1Color,
//                     ),
//                   ),
//                   const SizedBox(height: 1),
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                     children: [
//                       Text(
//                         price,
//                         style: GoogleFonts.roboto(
//                           fontSize: 16,
//                           color: AppColors.text3Color,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                       Row(
//                         children: [
//                           Icon(
//                             Icons.star,
//                             size: 18,
//                             color: AppColors.text3Color,
//                           ),
//                           const SizedBox(width: 2),
//                           Text(
//                             '4.5',
//                             style: GoogleFonts.roboto(
//                               fontSize: 14,
//                               color: AppColors.text2Color,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                   const SizedBox(height: 2),
//                   Row(
//                     children: [
//                       Text(
//                         '$distance miles away',
//                         style: GoogleFonts.roboto(
//                           fontSize: 13,
//                           color: AppColors.text2Color,
//                         ),
//                       ),
//                       const Spacer(),
//                       Text(
//                         availability,
//                         style: GoogleFonts.roboto(
//                           fontSize: 13,
//                           color: availability == 'Available'
//                               ? AppColors.text3Color
//                               : Colors.red,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 6),
//           ],
//         ),
//       ),
//     );
//   }
// }
//
// // Updated GridView with animations
