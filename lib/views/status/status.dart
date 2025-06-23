import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/models/post.dart';
import 'package:acent_messenger/services/auth_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:photo_view/photo_view.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final AuthService _authService = AuthService();
  List<Post> _posts = [];
  bool _isLoading = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadFeed() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/post/feed'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body)['data'];
        setState(() {
          _posts = (data as List).map((post) => Post.fromJson(post)).toList();
        });
      } else {
        throw Exception('Failed to load feed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load feed: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshFeed() async {
    try {
      await _loadFeed();
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status refreshed successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh status: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _uploadStatus() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image == null) return;

      setState(() {
        _isUploading = true;
      });

      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('No authentication token available');
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.baseApiUrl}/user/post/createPost'),
      );

      request.headers.addAll({
        'Authorization': 'Bearer $token',
      });

      request.files.add(
        await http.MultipartFile.fromPath(
          'attachment',
          image.path,
        ),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        await _loadFeed();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Status uploaded successfully')),
          );
        }
      } else {
        throw Exception('Failed to upload status: $responseBody');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload status: ${e.toString()}')),
        );
      }
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Status', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshFeed,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: InkWell(
                      onTap: _isUploading ? null : _uploadStatus,
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
                    child: _posts.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              Container(
                                height: MediaQuery.of(context).size.height * 0.4,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.update,
                                        size: 64,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No status updates yet',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Pull down to refresh',
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(top: 8.0),
                            children: _posts.map((post) => _buildStatusItem(
                              context: context,
                              name: '${post.user.firstName} ${post.user.lastName}',
                              time: timeago.format(post.createdAt),
                              imageUrl: post.attachment.url,
                              initials: post.user.photo == null ? post.user.firstName[0] : null,
                            )).toList(),
                          ),
                  ),
                ],
              ),
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
            backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
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