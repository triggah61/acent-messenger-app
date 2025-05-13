import 'package:country_code_picker/country_code_picker.dart';
import 'package:flutter/material.dart';
import '../../../constants/colors.dart';

class AddFriendScreen extends StatelessWidget {
  const AddFriendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor,
      appBar: AppBar(
        backgroundColor: AppColors.tabColor,
        elevation: 0,
        toolbarHeight: 55,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add Friend',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
        ),
        actions: [
          Builder(
            builder: (context) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  // Handle menu selection
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: "Create Group", child: Text("Create Group")),
                  const PopupMenuItem(value: "Settings", child: Text("Settings")),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding( // Removed SizedBox.expand
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Search Bar
              Container(
                decoration: BoxDecoration(
                  color: AppColors.button2Color,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: CountryCodePicker(
                        onChanged: (country) {},
                        initialSelection: 'GB',
                        favorite: ['+44', 'GB'],
                        showCountryOnly: false,
                        showOnlyCountryWhenClosed: false,
                        alignLeft: false,
                        textStyle: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: "Enter Phone Number",
                          hintStyle: TextStyle(color: Colors.white70),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search, color: Colors.white),
                      onPressed: () {
                        // Handle search action
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Friend List
              Expanded( // Changed Flexible to Expanded
                child: ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha((0.1 * 255).toInt()),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          radius: 26,
                          backgroundImage: AssetImage(friend['image']!),
                        ),
                        title: Text(
                          friend['name']!,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          friend['phone']!,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.buttonColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: () {
                            // Handle Add Friend action
                          },
                          icon: const Icon(Icons.person_add, size: 18, color: Colors.white),
                          label: const Text("Add", style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Dummy Friend Data
final List<Map<String, String>> friends = [
  {"name": "David Wayne", "phone": "(+44) 905 326 3022", "image": "images/c2.png"},
  {"name": "Edward Mint", "phone": "(+44) 926 2322", "image": "images/c3.png"},
  {"name": "May HG. Kang", "phone": "(+44) 9288 214", "image": "images/c4.png"},
  {"name": "Lily Dare", "phone": "(+44) 905 5299", "image": "images/c5.png"},
  {"name": "Dennis Dang", "phone": "(+44) 923 939", "image": "images/c2.png"},
  {"name": "Cayla Rajji", "phone": "(+44) 905 2329", "image": "images/c3.png"},
  {"name": "Erin Turcotte", "phone": "(+44) 928 214", "image": "images/c4.png"},
  {"name": "Bob Walter", "phone": "(+44) 50 9286 2355", "image": "images/c5.png"},
];