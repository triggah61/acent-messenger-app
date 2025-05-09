import 'package:flutter/material.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  GalleryScreenState createState() => GalleryScreenState();
}

class GalleryScreenState extends State<GalleryScreen> {
  // Dummy image paths
  final List<String> _dummyImagePaths = [
    'images/bgprofile.png',
    'images/bgprofile.png',
    'images/bgprofile.png',
    'images/bgprofile.png',
    'images/bgprofile.png',
    'images/bgprofile.png',
    'images/bgprofile.png',
    'images/bgprofile.png',

    // Add more dummy image paths here
  ];

  String? _selectedImagePath; // To hold the path of the selected image

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        backgroundColor: Colors.grey[900],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, // 3 images per row
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _dummyImagePaths.length,
        itemBuilder: (context, index) {
          final imagePath = _dummyImagePaths[index];
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedImagePath = imagePath;
              });
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: _selectedImagePath == imagePath
                    ? Border.all(color: Colors.blue, width: 3)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Container(
        color: Colors.grey[900],
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Text(
              _selectedImagePath != null
                  ? 'Selected: ${_selectedImagePath!.split('/').last}'
                  : 'Select an Image',
              style: const TextStyle(color: Colors.white),
            ),
            ElevatedButton(
              onPressed: _selectedImagePath != null
                  ? () {
                Navigator.pop(context, _selectedImagePath);
              }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: const Text('Send', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}