import 'package:chattingapp/constants/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/profile.dart';

class UserInformationScreen extends StatefulWidget {
  const UserInformationScreen({super.key});

  @override
  State<UserInformationScreen> createState() => _UserInformationScreenState();
}

class _UserInformationScreenState extends State<UserInformationScreen> {
  bool isMuteNotification = false;
  bool isProtectedChat = false;
  bool isHideChat = false;
  bool isHideChatHistory = false;
  final String placeholderImageUrl = 'https://i.pravatar.cc/150';

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final profile = authProvider.profile;
        
        return Scaffold(
          backgroundColor: const Color(0xFFF5F6FA),
          appBar: _buildAppBar(context),
          body: ListView(
            children: [
              _buildProfileSection(profile),
              _buildSettingsList(context),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 16.0),
          child: Row(
            children: [
              Icon(Icons.videocam_outlined, color: Colors.black),
              SizedBox(width: 16),
              Icon(Icons.call_outlined, color: Colors.black),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection(Profile? profile) {
    final fullName = profile != null 
        ? '${profile.firstName ?? ''} ${profile.lastName ?? ''}'.trim()
        : 'Loading...';

    final fullPhone = profile != null ? '(${profile.dialCode}) ${profile.phone}' : 'Loading...';
    
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundImage: profile?.photo != null
                ? NetworkImage(Config.getPhotoUrl(profile!.photo!))
                : null,
            child: profile?.photo == null
                ? Text(
              '${(profile?.firstName?.substring(0, 1).toUpperCase() ?? "")}'
                  '${(profile?.lastName?.substring(0, 1).toUpperCase() ?? "")}',
              style: const TextStyle(
                  fontSize: 36), // Slightly smaller to fit 2 letters
            ) : null,
          ),
          const SizedBox(height: 16),
          Text(
            fullName,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Color(0xFF343A40)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                fullPhone ?? 'Loading...',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20, color: Colors.grey),
                onPressed: () {
                  if (fullPhone != null) {
                    Clipboard.setData(ClipboardData(text: fullPhone));
                  }
                },
              ),
            ],
          ),
          // if (profile?.status != null) ...[
          //   const SizedBox(height: 8),
          //   Text(
          //     profile!.status!,
          //     style: const TextStyle(fontSize: 14, color: Colors.grey),
          //   ),
          // ],
          // const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSettingsList(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          buildSettingsListItem(
            leading: const Icon(Icons.insert_drive_file_outlined, color: Colors.black54),
            title: 'Media, Links & Documents',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('152', style: TextStyle(color: Colors.grey)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const MediaLinksDocumentsScreen()),
                    );
                  },
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MediaLinksDocumentsScreen()),
              );
            },
          ),
          const Divider(height: 0),
          buildSettingsListItem(
            leading: const Icon(FontAwesomeIcons.bellSlash, color: Colors.black54),
            title: 'Mute Notification',
            trailing: FlutterSwitch(
              width: 55.0,
              height: 30.0,
              valueFontSize: 12.0,
              toggleSize: 20.0,
              value: isMuteNotification,
              borderRadius: 30.0,
              padding: 8.0,
              showOnOff: false,
              onToggle: (val) {
                setState(() {
                  isMuteNotification = val;
                });
              },
            ),
            onTap: () {
              setState(() {
                isMuteNotification = !isMuteNotification;
              });
            },
          ),
          const Divider(height: 0),
          buildSettingsListItem(
            leading: const Icon(Icons.notifications_outlined, color: Colors.black54),
            title: 'Custom Notification',
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              onPressed: () {},
            ),
          ),
          const Divider(height: 0),
          buildSettingsListItem(
            leading: const Icon(FontAwesomeIcons.lock, color: Colors.black54),
            title: 'Protected Chat',
            trailing: FlutterSwitch(
              width: 55.0,
              height: 30.0,
              valueFontSize: 12.0,
              toggleSize: 20.0,
              value: isProtectedChat,
              borderRadius: 30.0,
              padding: 8.0,
              showOnOff: false,
              onToggle: (val) {
                setState(() {
                  isProtectedChat = val;
                });
              },
            ),
            onTap: () {
              setState(() {
                isProtectedChat = !isProtectedChat;
              });
            },
          ),
          const Divider(height: 0),
          buildSettingsListItem(
            leading: const Icon(Icons.visibility_off_outlined, color: Colors.black54),
            title: 'Hide Chat',
            trailing: FlutterSwitch(
              width: 55.0,
              height: 30.0,
              valueFontSize: 12.0,
              toggleSize: 20.0,
              value: isHideChat,
              borderRadius: 30.0,
              padding: 8.0,
              showOnOff: false,
              onToggle: (val) {
                setState(() {
                  isHideChat = val;
                });
              },
            ),
            onTap: () {
              setState(() {
                isHideChat = !isHideChat;
              });
            },
          ),
          const Divider(height: 0),
          buildSettingsListItem(
            leading: const Icon(Icons.history, color: Colors.black54),
            title: 'Hide Chat History',
            trailing: FlutterSwitch(
              width: 55.0,
              height: 30.0,
              valueFontSize: 12.0,
              toggleSize: 20.0,
              value: isHideChatHistory,
              borderRadius: 30.0,
              padding: 8.0,
              showOnOff: false,
              onToggle: (val) {
                setState(() {
                  isHideChatHistory = val;
                });
              },
            ),
            onTap: () {
              setState(() {
                isHideChatHistory = !isHideChatHistory;
              });
            },
          ),
          const Divider(height: 0),
          buildSettingsListItem(
            leading: const Icon(Icons.group_add_outlined, color: Colors.black54),
            title: 'Add To Group',
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddToGroupScreen()),
                );
              },
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddToGroupScreen()),
              );
            },
          ),
          const Divider(height: 0),
          buildSettingsListItem(
            leading: const Icon(Icons.color_lens_outlined, color: Colors.black54),
            title: 'Custom Color Chat',
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          const Divider(height: 0),
          buildSettingsListItem(
            leading: const Icon(Icons.image_outlined, color: Colors.black54),
            title: 'Custom Background Chat',
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Center(
                child: Icon(Icons.add, color: Colors.grey, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSettingsListItem({
    required Widget leading,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 20),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 16, color: Color(0xFF495057))),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class MediaLinksDocumentsScreen extends StatelessWidget {
  const MediaLinksDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: const Text('David Wayne', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w500)),
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.w500),
            tabs: [
              Tab(text: 'Media'),
              Tab(text: 'Links'),
              Tab(text: 'Documents'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMediaTab(),
            _buildLinksTab(),
            _buildDocumentsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Today', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemCount: 6,
          itemBuilder: (context, index) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.network('https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRcsJiqhjIaeBhVG4gRLIOUPCv05RXN8Zq_YQ&s'),
            );
          },
        ),
        const SizedBox(height: 24),
        const Text('Yesterday', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemCount: 3,
          itemBuilder: (context, index) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.network('https://t4.ftcdn.net/jpg/00/76/25/75/360_F_76257590_OMqEbhnSnz30cLj6xAG511xSZrJabcsq.jpg'),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLinksTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text('Today', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
        SizedBox(height: 12),
        LinkItem(title: '160+ Free Tab Bar Component Types', link: 'https://www.example.com/tab-bar'),
        SizedBox(height: 16),
        LinkItem(title: 'Speedy Chow : Food Delivery App UI Kit', link: 'https://www.example.com/food-app'),
        SizedBox(height: 24),
        Text('Yesterday', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
        SizedBox(height: 12),
        LinkItem(title: '15+ Free Shopper / Wizard Component', link: 'https://www.example.com/shopper'),
        SizedBox(height: 16),
        LinkItem(title: '60+ Free Skeleton / Shimmer / Loading Components', link: 'https://www.example.com/skeleton'),
        SizedBox(height: 24),
        Text('Last Month', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
        SizedBox(height: 12),
        LinkItem(title: 'Fast VPN : VPN Mobile App UI Kit Design', link: 'https://www.example.com/vpn-app'),
      ],
    );
  }

  Widget _buildDocumentsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text('Today', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
        SizedBox(height: 12),
        DocumentItem(title: 'Duo Quindate', size: '24 KB', icon: FontAwesomeIcons.filePdf),
        SizedBox(height: 16),
        DocumentItem(title: 'Design System', size: '1.5 GB', icon: FontAwesomeIcons.fileImage),
        SizedBox(height: 16),
        DocumentItem(title: 'The Lord of The Rings', size: '20.8 GB', icon: FontAwesomeIcons.fileVideo),
        SizedBox(height: 16),
        DocumentItem(title: 'War and Peace', size: '14.2 GB', icon: FontAwesomeIcons.fileWord),
        SizedBox(height: 24),
        Text('Yesterday', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
        SizedBox(height: 12),
        DocumentItem(title: 'Engineer Character', size: '100 KB', icon: FontAwesomeIcons.fileCode),
        SizedBox(height: 24),
        Text('Last Month', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey)),
        SizedBox(height: 12),
        DocumentItem(title: 'Talk Character', size: '120 MB', icon: FontAwesomeIcons.fileCsv),
        SizedBox(height: 16),
        DocumentItem(title: 'The Odyssey by Homer', size: '22.1 GB', icon: FontAwesomeIcons.fileZipper),
      ],
    );
  }
}

class AddToGroupScreen extends StatelessWidget {
  const AddToGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text('Add to Groups', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w500)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const TextField(
            decoration: InputDecoration(
              hintText: 'Search for groups',
              prefixIcon: Icon(Icons.search, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Color(0xFFF0F0F0),
              contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add, size: 24),
            label: const Text('Create new group'),
            onPressed: () {},
          ),
          const SizedBox(height: 24),
          const Text('All groups', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Color(0xFF495057))),
          const SizedBox(height: 12),
          GroupItem(name: 'Diamond Team', description: 'Thanks to awesome', action: 'Add'),
          GroupItem(name: 'Group Shares Experiences', description: 'Our first meeting', action: 'Added'),
          GroupItem(name: 'My charity group', description: 'Appreciate it', action: 'Add'),
          GroupItem(name: 'Game', description: 'Hooray!', action: 'Add'),
          GroupItem(name: 'Delivery', description: 'Our order has', action: 'Add'),
          GroupItem(name: 'Sky-diving Lion Team', description: 'See you soon!', action: 'Add'),
          GroupItem(name: 'football', description: 'New uniforms', action: 'Add'),
          GroupItem(name: 'IT Training', description: 'Appreciate them', action: 'Add'),
        ],
      ),
    );
  }
}

class GroupItem extends StatelessWidget {
  final String name;
  final String description;
  final String action;

  const GroupItem({super.key, required this.name, required this.description, required this.action});

  @override
  Widget build(BuildContext context) {
    return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
        padding: const EdgeInsets.all(16),
    child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
    Expanded(
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Color(0xFF343A40))),
        const SizedBox(height: 4),
        Text(description, style: const TextStyle(fontSize: 15, color: Colors.grey)),
      ],
    ),
    ),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {},
        child: Text(action),
      ),
    ],
    ),
        ),
    );
  }
}

class LinkItem extends StatelessWidget {
  final String title;
  final String link;

  const LinkItem({super.key, required this.title, required this.link});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Color(0xFF343A40))),
        Text(link, style: const TextStyle(fontSize: 15, color: Colors.blue)),
      ],
    );
  }
}

class DocumentItem extends StatelessWidget {
  final String title;
  final String size;
  final IconData icon;

  const DocumentItem({super.key, required this.title, required this.size, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            FaIcon(icon, size: 20, color: Colors.grey),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Color(0xFF343A40))),
          ],
        ),
        Text(size, style: const TextStyle(fontSize: 15, color: Colors.grey)),
      ],
    );
  }
}