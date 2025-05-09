import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';


class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: InkWell(
              onTap: () {
                // Logic to add your status
              },
              child: Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.red),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('My Status',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        Text('Tap to add your status',
                            style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16.0, top: 8.0),
            child: Text('Recent Updates',
                style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8.0),
              children: [
                _buildStatusItem(
                  context: context,
                  name: 'Micheal Brown',
                  time: 'Just now',
                  imageUrl:
                  'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTN3-b6hE_5K-l4bv_gBuFtF5zWoPEhSkLsuw&s',
                ),
                _buildStatusItem(
                  context: context,
                  name: 'Oliver Taylor',
                  time: '10 minutes ago',
                  imageUrl:
                  'https://images.unsplash.com/photo-1552058544-f2b08422138a?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTh8fHVzZXJ8ZW58MHx8MHx8MA%3D%3D&auto=format&fit=crop&w=500&q=60',
                ),
                _buildStatusItem(
                  context: context,
                  name: 'Liam Anderson',
                  time: '16 hours ago',
                  imageUrl:
                    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTDpWYsLSeY1sLvwgFNwBeJGjszUfEofDpwJw&s'
                ),
                _buildStatusItem(
                  context: context,
                  name: 'Lauren Taylor',
                  time: '18 hours ago',
                  imageUrl:
                    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcScGQQPJTeRXYxfbXVhLLXPl4aCJCexZ4dS7Q&s'
                ),
                _buildStatusItem(
                  context: context,
                  name: 'Charlotte Martinez',
                  time: '21 hours ago',
                  imageUrl:
                    'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRC8kiSH5ZSAcVoj3tAQQDoP_ux0sSricMyUg&s'
                ),
                _buildStatusItem(
                  context: context,
                  name: 'Emma Wilson',
                  time: '21 hours ago',
                  initials: 'E',

                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem({
    required BuildContext context,
    required String name,
    required String time,
    String? imageUrl,
    String? initials,
  }) {
    return ListTile(
      leading: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.red,
            width: 3,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: CircleAvatar(
            backgroundColor: Colors.white,
            radius: 24,
            backgroundImage:
            imageUrl != null ? NetworkImage(imageUrl) : null,
            child: imageUrl == null && initials != null
                ? Center(
              child: Text(
                initials,
                style: const TextStyle(fontSize: 20, color: Colors.red),
              ),
            )
                : null,
          ),
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(time, style: TextStyle(color: Colors.grey[600])),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PhotoViewPage(
              imageUrl: imageUrl ?? "https://www.pngitem.com/pimgs/m/146-1468479_my-profile-icon-blank-profile-picture-circle-hd.png",
              name: name,
            ),
          ),
        );
      },
    );
  }
}

class PhotoViewPage extends StatelessWidget {
  final String imageUrl;
  final String name;
  const PhotoViewPage({super.key, required this.imageUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: PhotoView(
          imageProvider: NetworkImage(imageUrl),
        ),
      ),
    );
  }
}