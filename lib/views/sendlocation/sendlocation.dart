import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  LocationScreenState createState() => LocationScreenState();
}

class LocationScreenState extends State<LocationScreen> {
  String? _selectedLocation;

  final List<Map<String, String>> _dummyLocations = [
    {
      'name': 'Warren Law College',
      'address': '1234 Elm Street, Oakville, USA',
      'icon': 'graduation-cap',
    },
    {
      'name': 'Greenwood Central Park',
      'address': '5678 Oak Avenue, Greenwood, USA',
      'icon': 'tree',
    },
    {
      'name': 'Saint John\'s Community Church',
      'address': '910 Pine Road, Oakville, USA',
      'icon': 'church',
    },
    {
      'name': 'Maple Grove Shopping Mall',
      'address': '123 Main Street, Greenwood, USA',
      'icon': 'shopping-cart',
    },
    {
      'name': 'Evergreen Public Library',
      'address': '456 Maple Lane, Oakville, USA',
      'icon': 'book',
    },
    {
      'name': 'Cedar City Hall',
      'address': '789 Cedar Boulevard, Greenwood, USA',
      'icon': 'building',
    },
    {
      'name': 'Birchwood Police Station',
      'address': '1011 Birch Drive, Oakville, USA',
      'icon': 'shield-alt',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send location'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search location...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey[100],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'images/mapppp.PNG', // Replace with your map image
                  fit: BoxFit.cover,
                  height: 200,
                  width: double.infinity,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Your current location',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _dummyLocations.length,
              itemBuilder: (context, index) {
                final location = _dummyLocations[index];
                final isSelected = _selectedLocation == location['name'];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red[50],
                    child: FaIcon(
                      getIconData(location['icon']!), // Use getIconData to map icon names to FaIcon
                      color: Colors.red[400],
                      size: 20,
                    ),
                  ),
                  title: Text(location['name']!),
                  subtitle: Text(location['address']!),
                  selected: isSelected,
                  selectedTileColor: Colors.blue[50],
                  onTap: () {
                    setState(() {
                      _selectedLocation = location['name'];
                    });
                  },
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.blue)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper function to get FontAwesome icons from the name
  IconData getIconData(String iconName) {
    switch (iconName) {
      case 'graduation-cap':
        return FontAwesomeIcons.graduationCap;
      case 'tree':
        return FontAwesomeIcons.tree;
      case 'church':
        return FontAwesomeIcons.church;
      case 'shopping-cart':
        return FontAwesomeIcons.cartShopping;
      case 'book':
        return FontAwesomeIcons.book;
      case 'building':
        return FontAwesomeIcons.building;
      case 'shield-alt':
        return FontAwesomeIcons.shieldHalved;
      default:
        return FontAwesomeIcons.locationDot;
    }
  }
}