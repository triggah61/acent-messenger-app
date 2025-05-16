import 'package:chattingapp/views/status/status.dart';
import 'package:chattingapp/widgets/auth_middleware.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chattingapp/providers/chat_provider.dart';
import 'package:chattingapp/models/chat_session.dart';
import 'package:chattingapp/constants/config.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../addfriend/addfriend.dart';
import '../creategroups/creategroups.dart';
import '../consversations/chatdetailsscreen.dart';
import '../search/search.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    print("HomeScreen - initState: Initializing");
    _scrollController.addListener(_onScroll);
    // Initial fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print("HomeScreen - initState: Fetching initial sessions");
      context.read<ChatProvider>().fetchSessions();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
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
    print("HomeScreen - build: Building screen");
    return AuthMiddleware(child: Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF121829),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      ).then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                    ),
                  ),
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
                  MenuAnchor(
                    builder: (
                        BuildContext context,
                        MenuController controller,
                        Widget? child,
                        ) {
                      return IconButton(
                        onPressed: () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                        icon: const Icon(Icons.add, color: Colors.white),
                      );
                    },
                    menuChildren: [
                      MenuItemButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AddFriendScreen(),
                            ),
                          ).then((_) {
                            if (mounted) {
                              setState(() {});
                            }
                          });
                        },
                        child: const Text('Add Friend'),
                      ),
                      MenuItemButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CreateGroups(),
                            ),
                          ).then((_) {
                            if (mounted) {
                              setState(() {});
                            }
                          });
                        },
                        child: const Text('Create Group'),
                      ),
                    ],
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
                        MaterialPageRoute(builder: (_) => const StatusScreen()),
                      ).then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    },
                    child: _buildStatusItem(
                      name: 'My status',
                      imageUrl:
                      'https://images.unsplash.com/photo-1580489944761-15a19d654956?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTB8fHBlcnNvbnxlbnwwfHwwfHx8MA%3D%3D&auto=format&fit=crop&w=500&q=60',
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Conversations(),
                        ),
                      ).then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    },
                    child: _buildStatusItem(
                      name: 'Adil',
                      imageUrl:
                      'https://images.unsplash.com/photo-1547425260-76bcadfb4f2c?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8NXx8cGVyc29ufGVufDB8fDB8fHww&auto=format&fit=crop&w=500&q=60',
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Conversations(),
                        ),
                      ).then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    },
                    child: _buildStatusItem(
                      name: 'Marina',
                      imageUrl:
                      'https://images.unsplash.com/photo-1580489944761-15a19d654956?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTB8fHBlcnNvbnxlbnwwfHwwfHx8MA%3D%3D&auto=format&fit=crop&w=500&q=60',
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Conversations(),
                        ),
                      ).then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    },
                    child: _buildStatusItem(
                      name: 'Dean',
                      imageUrl:
                      'https://images.unsplash.com/photo-1568602471122-7832951cc4c5?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTh8fHBlcnNvbnxlbnwwfHwwfHx8MA%3D%3D&auto=format&fit=crop&w=500&q=60',
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Conversations(),
                        ),
                      ).then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    },
                    child: _buildStatusItem(
                      name: 'Max',
                      imageUrl:
                      'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTZ8fHBlcnNvbnxlbnwwfHwwfHx8MA%3D%3D&auto=format&fit=crop&w=500&q=60',
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Conversations(),
                        ),
                      ).then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    },
                    child: _buildStatusItem(
                      name: 'Alice',
                      imageUrl:
                      'https://images.unsplash.com/photo-1580489944761-15a19d654956?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTh8fHBlcnNvbnxlbnwwfHwwfHx8MA%3D%3D&auto=format&fit=crop&w=500&q=60',
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Conversations(),
                        ),
                      ).then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    },
                    child: _buildStatusItem(
                      name: 'Bob',
                      imageUrl:
                      'https://images.unsplash.com/photo-1580489944761-15a19d654956?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTh8fHBlcnNvbnxlbnwwfHwwfHx8MA%3D%3D&auto=format&fit=crop&w=500&q=60',
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const Conversations(),
                        ),
                      ).then((_) {
                        if (mounted) {
                          setState(() {});
                        }
                      });
                    },
                    child: _buildStatusItem(
                      name: 'Charlie',
                      imageUrl:
                      'https://images.unsplash.com/photo-1580489944761-15a19d654956?ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTh8fHBlcnNvbnxlbnwwfHwwfHx8MA%3D%3D&auto=format&fit=crop&w=500&q=60',
                    ),
                  ),
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
                      print("HomeScreen - build: Consumer rebuilding. Sessions: ${chatProvider.sessions.length}, Loading: ${chatProvider.isLoading}");
                      
                      if (chatProvider.sessions.isEmpty && chatProvider.isLoading) {
                        print("HomeScreen - build: Showing loading indicator");
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (chatProvider.sessions.isEmpty) {
                        print("HomeScreen - build: No sessions to display");
                        return const Center(child: Text('No conversations yet'));
                      }

                      print("HomeScreen - build: Building session list with ${chatProvider.sessions.length} items");
                      return RefreshIndicator(
                        onRefresh: () {
                          print("HomeScreen - build: Refreshing sessions");
                          return chatProvider.refreshSessions();
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: chatProvider.sessions.length + (chatProvider.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == chatProvider.sessions.length) {
                              print("HomeScreen - build: Showing loading more indicator");
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final session = chatProvider.sessions[index];
                            print("HomeScreen - build: Building session tile for ${session.title}");
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
      ),
    ));
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
            ? Text(session.title.substring(0, 1).toUpperCase())
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
}
