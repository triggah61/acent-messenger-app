import 'package:acent_messenger/services/auth_service.dart';
import 'package:acent_messenger/views/status/status.dart';
import 'package:acent_messenger/widgets/auth_middleware.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:acent_messenger/providers/chat_provider.dart';
import 'package:acent_messenger/providers/auth_provider.dart';
import 'package:acent_messenger/models/chat_session.dart';
import 'package:acent_messenger/constants/config.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../consversations/chatdetailsscreen.dart';
import '../../services/chat_service.dart';

// Contact model for API response
class Contact {
  final String id;
  final String firstName;
  final String lastName;
  final String? photo;
  final String dialCode;
  final String phone;

  Contact({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.dialCode,
    required this.phone,
    this.photo,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['_id'],
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      dialCode: json['dialCode'] ?? '',
      phone: json['phone'] ?? '',
      photo: json['photo'],
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService(AuthService());

  List<Contact> _contacts = [];
  bool _isContactsLoading = false;

  @override
  void initState() {
    super.initState();
    print("HomeScreen - initState: Initializing");
    _scrollController.addListener(_onScroll);

    // Initial fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print("HomeScreen - initState: Fetching initial sessions");
      context.read<ChatProvider>().fetchSessions();
      _fetchContacts();
    });
  }

  Future<void> _fetchContacts() async {
    setState(() {
      _isContactsLoading = true;
    });
    try {
      final token = await _authService.getToken();
      if (token == null) throw Exception('No token');
      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/contact/list?limit=-1'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        print("HomeScreen - _fetchContacts: Fetched data: $data");
        final List<Contact> contacts = (data['contacts']['docs'] as List)
            .map((c) => Contact.fromJson(c))
            .toList();
        setState(() {
          _contacts = contacts;
        });
      } else {
        throw Exception('Failed to fetch contacts');
      }
    } catch (e) {
      // Optionally show error
    } finally {
      setState(() {
        _isContactsLoading = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      print("HomeScreen - _onScroll: Near bottom, loading more sessions");
      context.read<ChatProvider>().fetchSessions();
    }
  }

  @override
  void dispose() {
    print("HomeScreen - dispose: Cleaning up");
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthMiddleware(
      child: Consumer<AuthProvider>(builder: (context, authProvider, child) {
        final profile = authProvider.profile;
        return Scaffold(
            key: _scaffoldKey,
            backgroundColor: const Color(0xFF121829),
            body: SafeArea(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        // IconButton(
                        //   icon: const Icon(Icons.search, color: Colors.white),
                        //   onPressed: () {
                        //     Navigator.push(
                        //       context,
                        //       MaterialPageRoute(
                        //           builder: (_) => const SearchScreen()),
                        //     ).then((_) {
                        //       if (mounted) {
                        //         setState(() {});
                        //       }
                        //     });
                        //   },
                        //   style: IconButton.styleFrom(
                        //     backgroundColor: Colors.grey[800],
                        //   ),
                        // ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Center(
                            child: const Text(
                              'Messages',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 100,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const StatusScreen()),
                            ).then((_) {
                              if (mounted) {
                                setState(() {});
                              }
                            });
                          },
                          child: _buildStatusItem(
                            name: 'My status',
                            imageUrl: Config.getPhotoUrl(profile?.photo ?? ''),
                          ),
                        ),
                        ..._contacts.map((contact) => GestureDetector(
                            onTap: () async {
                              final session = await _chatService
                                  .findOrCreateSession(contact.id);
                              // You can add navigation to contact chat here
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        Conversations(session: session)),
                              ).then((_) {
                                if (mounted) {
                                  setState(() {});
                                }
                              });
                            },
                            // child: _buildContactAvatar(contact),
                            child: _buildStatusItem(
                              name: '${contact.firstName} ${contact.lastName}',
                              imageUrl: Config.getPhotoUrl(contact.photo ?? ''),
                            ))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Consumer<ChatProvider>(
                          builder: (context, chatProvider, child) {
                            print("HomeScreen - build: Consumer rebuilding. Sessions: " +
                                "${chatProvider.sessions.length}, Loading: ${chatProvider.isLoading}");

                            if (chatProvider.sessions.isEmpty &&
                                chatProvider.isLoading) {
                              print(
                                  "HomeScreen - build: Showing loading indicator");
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            if (chatProvider.sessions.isEmpty) {
                              print(
                                  "HomeScreen - build: No sessions to display");
                              return const Center(
                                  child: Text('No conversations yet'));
                            }

                            print(
                                "HomeScreen - build: Building session list with ${chatProvider.sessions.length} items");
                            return RefreshIndicator(
                              onRefresh: () {
                                print(
                                    "HomeScreen - build: Refreshing sessions");
                                return chatProvider.refreshSessions();
                              },
                              child: ListView.builder(
                                controller: _scrollController,
                                itemCount: chatProvider.sessions.length +
                                    (chatProvider.hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == chatProvider.sessions.length) {
                                    print(
                                        "HomeScreen - build: Showing loading more indicator");
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }

                                  final session = chatProvider.sessions[index];
                                  print(
                                      "HomeScreen - build: Building session tile for ${session.title}");
                                  return _ChatSessionTile(session: session);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ));
      }),
    );
  }

  Widget _buildContactAvatar(Contact contact) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: contact.photo != null
                ? NetworkImage(Config.getPhotoUrl(contact.photo!))
                : null,
            child: contact.photo == null
                ? Text(_getInitials(contact.firstName))
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            '${contact.firstName} ${contact.lastName}'.trim(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem({required String name, required String imageUrl}) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(radius: 30, backgroundImage: NetworkImage(imageUrl)),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.add, size: 12, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) {
      return '?';
    }
    return name.trim().substring(0, 1).toUpperCase();
  }
}

class _ChatSessionTile extends StatelessWidget {
  final ChatSession session;

  const _ChatSessionTile({Key? key, required this.session}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print("ChatSessionTile - build: Building tile for session ${session.id}");
    final lastMessage = session.lastMessage;

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: session.photo != null
            ? NetworkImage(Config.getPhotoUrl(session.photo!))
            : null,
        child: session.photo == null
            ? Text(_getSessionInitials(session.title))
            : null,
      ),
      title: Text(session.title),
      subtitle: lastMessage != null
          ? Text(
              lastMessage.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: lastMessage != null
          ? Text(
              timeago.format(lastMessage.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      onTap: () {
        print("ChatSessionTile - onTap: Tapped session ${session.id}");
        // TODO: Navigate to chat detail
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Conversations(session: session),
          ),
        );
      },
    );
  }
  
  String _getSessionInitials(String? title) {
    if (title == null || title.trim().isEmpty) {
      return '?';
    }
    return title.trim().substring(0, 1).toUpperCase();
  }
}
