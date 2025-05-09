// import 'package:flutter/material.dart';
// import 'dart:ui';
//
// class CallScreen extends StatelessWidget {
//   const CallScreen({Key? key}) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFF222831), // Dark background
//       body: SafeArea(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Padding(
//               padding: const EdgeInsets.all(16.0),
//               child: Row(
//                 children: [
//                   IconButton(
//                     icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
//                     onPressed: () {
//                       Navigator.pop(context);
//                     },
//                   ),
//                   const SizedBox(width: 16),
//                   const Text(
//                     'Calling...',
//                     style: TextStyle(color: Colors.white, fontSize: 18),
//                   ),
//                 ],
//               ),
//             ),
//             const CircleAvatar(
//               radius: 80,
//               backgroundImage: AssetImage('images/david_wayne.jpg'), // Replace with your image
//             ),
//             Column(
//               children: const [
//                 Text(
//                   'David Wayne',
//                   style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
//                 ),
//                 SizedBox(height: 8),
//                 Text(
//                   '(+44) 50 9285 3022',
//                   style: TextStyle(color: Colors.white70, fontSize: 16),
//                 ),
//               ],
//             ),
//             Padding(
//               padding: const EdgeInsets.all(32.0),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                 children: [
//                   _buildCircleButton(
//                     icon: Icons.call_end,
//                     color: Colors.redAccent,
//                     onPressed: () {
//                       Navigator.pop(context);
//                     },
//                   ),
//                   _buildCircleButton(
//                     icon: Icons.phone,
//                     color: Colors.greenAccent,
//                     onPressed: () {
//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(builder: (context) => const BlurredCallScreen()),
//                       );
//                     },
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildCircleButton({required IconData icon, required Color color, required VoidCallback onPressed}) {
//     return InkWell(
//       onTap: onPressed,
//       child: Container(
//         width: 70,
//         height: 70,
//         decoration: BoxDecoration(
//           shape: BoxShape.circle,
//           color: color,
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.3),
//               spreadRadius: 2,
//               blurRadius: 5,
//               offset: const Offset(0, 3),
//             ),
//           ],
//         ),
//         child: Icon(icon, color: Colors.white, size: 32),
//       ),
//     );
//   }
// }
//
// class BlurredCallScreen extends StatelessWidget {
//   const BlurredCallScreen({Key? key}) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         fit: StackFit.expand,
//         children: [
//           Image.asset(
//             'images/david_wayne.jpg',
//             fit: BoxFit.cover,
//           ),
//           BackdropFilter(
//             filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
//             child: Container(
//               color: Colors.black.withOpacity(0.5),
//             ),
//           ),
//           SafeArea(
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Padding(
//                   padding: const EdgeInsets.all(16.0),
//                   child: Row(
//                     children: [
//                       IconButton(
//                         icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
//                         onPressed: () {
//                           Navigator.pop(context);
//                         },
//                       ),
//                       const SizedBox(width: 16),
//                       const Text(
//                         'Calling...',
//                         style: TextStyle(color: Colors.white, fontSize: 18),
//                       ),
//                     ],
//                   ),
//                 ),
//                 Column(
//                   children: const [
//                     CircleAvatar(
//                       radius: 80,
//                       backgroundImage: AssetImage('images/david_wayne.jpg'), // Replace with your image
//                     ),
//                     SizedBox(height: 16),
//                     Text(
//                       'David Wayne',
//                       style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
//                     ),
//                     SizedBox(height: 8),
//                     Text(
//                       '(+44) 50 9285 3022',
//                       style: TextStyle(color: Colors.white70, fontSize: 16),
//                     ),
//                   ],
//                 ),
//                 Padding(
//                   padding: const EdgeInsets.all(32.0),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                     children: [
//                       _buildBlurredCircleButton(
//                         icon: Icons.mic,
//                         onPressed: () {},
//                       ),
//                       _buildBlurredCircleButton(
//                         icon: Icons.volume_up,
//                         onPressed: () {},
//                       ),
//                       _buildBlurredCircleButton(
//                         icon: Icons.call_end,
//                         color: Colors.redAccent,
//                         onPressed: () {
//                           Navigator.pop(context);
//                         },
//                       ),
//                       ElevatedButton(
//                         onPressed: () {
//                           Navigator.push(
//                             context,
//                             MaterialPageRoute(builder: (context) => const VideoCallScreen()),
//                           );
//                         },
//                         child: const Text("Go To Video"),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildBlurredCircleButton({required IconData icon, Color color = Colors.white, required VoidCallback onPressed}) {
//     return InkWell(
//       onTap: onPressed,
//       child: Container(
//         width: 60,
//         height: 60,
//         decoration: BoxDecoration(
//           shape: BoxShape.circle,
//           color: Colors.white.withOpacity(0.2),
//         ),
//         child: Icon(icon, color: color, size: 28),
//       ),
//     );
//   }
// }
//
// class VideoCallScreen extends StatelessWidget {
//   const VideoCallScreen({Key? key}) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         fit: StackFit.expand,
//         children: [
//           Image.asset(
//             'images/david_wayne.jpg',
//             fit: BoxFit.cover,
//           ),
//           SafeArea(
//             child: Column(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 Padding(
//                   padding: const EdgeInsets.all(16.0),
//                   child: Row(
//                     children: [
//                       IconButton(
//                         icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
//                         onPressed: () {
//                           Navigator.pop(context);
//                         },
//                       ),
//                       const SizedBox(width: 16),
//                       const Text(
//                         'Calling...',
//                         style: TextStyle(color: Colors.white, fontSize: 18),
//                       ),
//                     ],
//                   ),
//                 ),
//                 Align(
//                   alignment: Alignment.bottomRight,
//                   child: Container(
//                     margin: const EdgeInsets.all(16.0),
//                     width: 100,
//                     height: 150,
//                     decoration: BoxDecoration(
//                       borderRadius: BorderRadius.circular(10),
//                       boxShadow: [
//                         BoxShadow(
//                           color: Colors.black.withOpacity(0.2),
//                           spreadRadius: 1,
//                           blurRadius: 3,
//                           offset: const Offset(0, 2),
//                         ),
//                       ],
//                       image: const DecorationImage(
//                         image: AssetImage('images/david_wayne.jpg'), // Smaller video image
//                         fit: BoxFit.cover,
//                       ),
//                     ),
//                   ),
//                 ),
//                 Padding(
//                   padding: const EdgeInsets.all(32.0),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                     children: [
//                       _buildBlurredCircleButton(
//                         icon: Icons.mic,
//                         onPressed: () {},
//                       ),
//                       _buildBlurredCircleButton(
//                         icon: Icons.videocam,
//                         onPressed: () {},
//                       ),
//                       _buildBlurredCircleButton(
//                         icon: Icons.volume_up,
//                         onPressed: () {},
//                       ),
//                       _buildBlurredCircleButton(
//                         icon: Icons.call_end,
//                         color: Colors.redAccent,
//                         onPressed: () {
//                           Navigator.pop(context);
//                         },
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildBlurredCircleButton({required IconData icon, Color color = Colors.white, required VoidCallback onPressed}) {
//     return InkWell(
//       onTap: onPressed,
//       child: Container(
//         width: 60,
//         height: 60,
//         decoration: BoxDecoration(
//           shape: BoxShape.circle,
//           color: Colors.white.withOpacity(0.2),
//         ),
//         child: Icon(icon, color: color, size: 28),
//       ),
//     );
//   }
// }