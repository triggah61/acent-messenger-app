// import 'package:flutter/material.dart';
// import 'package:font_awesome_flutter/font_awesome_flutter.dart';
// import 'package:homeconstruction/views/home/home.dart';
//
// import '../views/assetsavaluation/assetsavaluations.dart';
// import '../views/booking/booking.dart';
// import '../views/budgetestimation/budgetestimation.dart';
// import '../views/budgettracking/budgettracking.dart';
// import '../views/cameraview/cameraview.dart';
// import '../views/customdesign/customdesign.dart';
// import '../views/designercategories/designercategories.dart';
// import '../views/designgallery/designgallery.dart';
// import '../views/documentstorage/documentstorage.dart';
// import '../views/earnings/earnings.dart';
// import '../views/homeevaluation/homeevaluation.dart';
// import '../views/inventorymanagement/inventorymanagement.dart';
// import '../views/messages/chat_screen.dart';
// import '../views/newhomeconstruction/newhomeconstruction.dart';
// import '../views/packages/residentialpackages.dart';
// import '../views/prodesign/prodesign.dart';
// import '../views/projectgallery/myproject.dart';
// import '../views/projectplanners/projectplanner.dart';
// import '../views/reviews/reviews.dart';
// import '../views/searchlivingroom/searchliving.dart';
// import '../views/settings/settings.dart';
// import '../views/susbscription/susbscription.dart';
// import '../views/tickets/tickets.dart';
// import '../views/timeline/timeline.dart';
// import '../views/usercollection/collection.dart';
// import '../views/usernotifications/usernotifications.dart';
// import '../views/userprofile/userprofile.dart';
// import '../views/workshedule/workshedule.dart';
//
//
//
//
//
//
// class DrawerWidget extends StatefulWidget {
//   const DrawerWidget({super.key});
//
//   @override
//   State<DrawerWidget> createState() => _DrawerWidgetState();
// }
//
// class _DrawerWidgetState extends State<DrawerWidget> {
//   String selectedMenuItem = '';
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       width: 270,
//       decoration: BoxDecoration(
//         color: Colors.grey[50],  //Light background
//         borderRadius: BorderRadius.circular(15), //Soften the corners
//         boxShadow: [
//           BoxShadow(
//             color: Colors.grey.withOpacity(0.3),  //Subtle Shadow
//             spreadRadius: 2,
//             blurRadius: 5,
//             offset: const Offset(0, 3),
//           ),
//         ],
//       ),
//       child: Column(
//         children: [
//           _buildProfileSection(),
//           const SizedBox(height: 10),
//           Expanded(
//             child: ListView(
//               physics: const BouncingScrollPhysics(),
//               padding: const EdgeInsets.symmetric(horizontal: 10),
//               children: [
//                 buildMenuItem("Home", FontAwesomeIcons.house, () => navigateTo(HomeScreen())),
//                 buildMenuItem("Search", FontAwesomeIcons.magnifyingGlass, () => navigateTo(SearchModernLivingRoom())),
//                 buildMenuItem("DesignGallery", FontAwesomeIcons.images, () => navigateTo(DesignGalleryScreen())),
//                 buildMenuItem("ProjectPlanner", FontAwesomeIcons.solidClipboard, () => navigateTo(ProjectPlannerScreen())),
//                 buildMenuItem("MyProjects", FontAwesomeIcons.folderOpen, () => navigateTo(MyProjectsScreen())),
//                 buildMenuItem("ProjectBudget", FontAwesomeIcons.coins, () => navigateTo(ProjectBudgetTrackingScreen())),
//                 buildMenuItem("HomeConstruction", FontAwesomeIcons.hammer, () => navigateTo(NewHomeConstruction())),
//                 buildMenuItem("BudgetEstimation", FontAwesomeIcons.calculator, () => navigateTo(BudgetEstimationScreen())),
//                 buildMenuItem("DocumentStorage", FontAwesomeIcons.fileArchive, () => navigateTo(DocumentStorageScreen())),
//                 buildMenuItem("HomeValuation", FontAwesomeIcons.chartLine, () => navigateTo(HomeValuationScreen())),
//                 buildMenuItem("AssetsValuation", FontAwesomeIcons.moneyBillWave, () => navigateTo(AssetsValuationScreen())),
//                 buildMenuItem("InventoryManage", FontAwesomeIcons.boxesStacked, () => navigateTo(InventoryScreen())),
//                 buildMenuItem("DesignerCategories", FontAwesomeIcons.palette, () => navigateTo(DesignerCategoriesScreen())),
//                 buildMenuItem("CustomDesign", FontAwesomeIcons.pencilRuler, () => navigateTo(CustomDesign1())),
//                 buildMenuItem("UserCollection", FontAwesomeIcons.bookmark, () => navigateTo(CollectionScreen())),
//                 buildMenuItem("Booking", FontAwesomeIcons.calendarCheck, () => navigateTo(BookingScreen())),
//                 buildMenuItem("CameraView", FontAwesomeIcons.camera, () => navigateTo(CameraView())),
//                 buildMenuItem("Earnings", FontAwesomeIcons.dollarSign, () => navigateTo(EarningsScreen())),
//                 buildMenuItem("Packages", FontAwesomeIcons.box, () => navigateTo(ResidentialPackagesScreen())),
//                 buildMenuItem("ProDesign", FontAwesomeIcons.briefcase, () => navigateTo(ProDesign())),
//                 buildMenuItem("Subscriptions", FontAwesomeIcons.receipt, () => navigateTo(SubscriptionScreen())),
//                 buildMenuItem("YourTickets", FontAwesomeIcons.ticket, () => navigateTo(YourTicketsScreen())),
//                 buildMenuItem("Timeline", FontAwesomeIcons.clock, () => navigateTo(TimelineScreen())),
//                 buildMenuItem("WorkSchedule", FontAwesomeIcons.calendar, () => navigateTo(WorkScheduleScreen())),
//                 buildMenuItem("Chat", FontAwesomeIcons.comments, () => navigateTo(ChatScreen())),
//                 buildMenuItem("UserProfile", FontAwesomeIcons.user, () => navigateTo(UserProfileScreen())),
//                 buildMenuItem("Notifications", FontAwesomeIcons.bell, () => navigateTo(NotificationsScreen())),
//                 buildMenuItem("Settings", FontAwesomeIcons.gear, () => navigateTo(SettingsScreen())),
//                 buildMenuItem("Reviews", FontAwesomeIcons.star, () => navigateTo(Reviews())),
//                 const SizedBox(height: 10),
//                 const Divider(color: Colors.grey, thickness: 0.5),
//                 buildLogoutButton(),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildProfileSection() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: const BorderRadius.only(topRight: Radius.circular(15)), //Match the Drawer radius
//       ),
//       child: Row(
//         children: [
//           Container(  //Added Container for background
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               border: Border.all(color: Colors.blue, width: 2),  //Profile highlight
//             ),
//             child: const CircleAvatar(
//               radius: 30,
//               backgroundImage: AssetImage('images/c3.png'), //User Profile Image
//             ),
//           ),
//
//           const SizedBox(width: 12),
//           Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               const Text(
//                 'Hello, James!',
//                 style: TextStyle(
//                   color: Colors.black87,
//                   fontSize: 18,
//                   fontWeight: FontWeight.w600,
//                 ),
//               ),
//               GestureDetector(
//                 onTap: () {
//                   // Navigate to profile screen
//                 },
//                 child: Text(
//                   'View Profile',
//                   style: TextStyle(
//                     color: Colors.blue,
//                     fontSize: 14,
//                     decoration: TextDecoration.underline,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget buildMenuItem(String title, IconData icon, VoidCallback onTap) {
//     bool isSelected = title == selectedMenuItem;
//     return GestureDetector(
//       onTap: () {
//         setState(() {
//           selectedMenuItem = title;
//         });
//         onTap();
//       },
//       child: AnimatedContainer(
//         duration: const Duration(milliseconds: 300),
//         margin: const EdgeInsets.symmetric(vertical: 4),
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
//         decoration: BoxDecoration(
//           color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent, // Subtler highlight
//           borderRadius: BorderRadius.circular(12),
//         ),
//         child: Row(
//           children: [
//             Container(  //Added Container for background
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 color: isSelected ? Colors.blue : Colors.grey[200], // Softer selection color
//               ),
//               padding: const EdgeInsets.all(8),
//               child: Icon(
//                 icon,
//                 size: 20,
//                 color: isSelected ? Colors.white : Colors.blueGrey, //Contrasting color
//               ),
//             ),
//             const SizedBox(width: 14),
//             Expanded(
//               child: Text(
//                 title,
//                 style: TextStyle(
//                   fontSize: 16,
//                   color: isSelected ? Colors.black87 : Colors.blueGrey,  //Readability
//                   fontWeight: FontWeight.w500,
//                 ),
//               ),
//             ),
//             Icon(
//               Icons.navigate_next,
//               size: 20,
//               color: isSelected ? Colors.black87 : Colors.blueGrey,  //Readability
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget buildLogoutButton() {
//     return GestureDetector(
//       onTap: () {
//         // Handle logout
//       },
//       child: Container(  //Container so that boxShadow will work
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(10),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.redAccent.withOpacity(0.2),  //Lighter shadow
//               spreadRadius: 0,
//               blurRadius: 4,
//               offset: const Offset(0, 2),
//             ),
//           ],
//         ),
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 200),
//           margin: const EdgeInsets.symmetric(vertical: 4),
//           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
//           decoration: BoxDecoration(
//             color: Colors.redAccent,
//             borderRadius: BorderRadius.circular(10),
//           ),
//           child: Row(
//             children: const [
//               Icon(Icons.logout, color: Colors.white, size: 20),
//               SizedBox(width: 10),
//               Text(
//                 "Logout",
//                 style: TextStyle(
//                   fontSize: 16,
//                   color: Colors.white,
//                   fontWeight: FontWeight.w500,
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   void navigateTo(Widget page) {
//     Navigator.push(context, MaterialPageRoute(builder: (context) => page));
//   }
// }