import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:acent_messenger/providers/group_provider.dart';
import 'package:acent_messenger/models/chat_session.dart';
import 'package:acent_messenger/constants/config.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../widgets/auth_middleware.dart';

import '../consversations/chatdetailsscreen.dart';
import '../creategroups/creategroups.dart';

class GroupChatList extends StatelessWidget {
  const GroupChatList({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthMiddleware(
      child: Scaffold(
        backgroundColor: const Color(0xFF121829),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Center(
                        child: const Text(
                          'Groups',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreateGroups(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add, color: Colors.white),
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
                  child: const ChatListView(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatListView extends StatefulWidget {
  const ChatListView({super.key});

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    print("ChatListView - initState: Initializing");
    _scrollController.addListener(_onScroll);
    // Initial fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print("ChatListView - initState: Fetching initial groups");
      context.read<GroupProvider>().fetchSessions();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      print("ChatListView - _onScroll: Near bottom, loading more groups");
      context.read<GroupProvider>().fetchSessions();
    }
  }

  @override
  void dispose() {
    print("ChatListView - dispose: Cleaning up");
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshGroups() async {
    try {
      await context.read<GroupProvider>().refreshSessions();

      // Show success message
      if (mounted) {
        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(
        //     content: Text('Groups refreshed successfully'),
        //     backgroundColor: Colors.green,
        //     duration: Duration(seconds: 2),
        //   ),
        // );
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh groups: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GroupProvider>(
      builder: (context, groupProvider, child) {
        print(
            "ChatListView - build: Consumer rebuilding. Sessions: ${groupProvider.sessions.length}, Loading: ${groupProvider.isLoading}");

        if (groupProvider.sessions.isEmpty && groupProvider.isLoading) {
          print("ChatListView - build: Showing loading indicator");
          return const Center(child: CircularProgressIndicator());
        }

        if (groupProvider.sessions.isEmpty) {
          print("ChatListView - build: No groups to display");
          return RefreshIndicator(
            onRefresh: _refreshGroups,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Container(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No groups yet',
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
            ),
          );
        }

        print(
            "ChatListView - build: Building group list with ${groupProvider.sessions.length} items");
        return RefreshIndicator(
          onRefresh: _refreshGroups,
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount:
                groupProvider.sessions.length + (groupProvider.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == groupProvider.sessions.length) {
                print("ChatListView - build: Showing loading more indicator");
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final session = groupProvider.sessions[index];
              print(
                  "ChatListView - build: Building group tile for ${session.title}");
              return ChatTile(session: session);
            },
          ),
        );
      },
    );
  }
}

class ChatTile extends StatelessWidget {
  final ChatSession session;

  const ChatTile({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            // builder: (context) => const GroupChatScreen(),
            builder: (context) => Conversations(session: session),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 4, spreadRadius: 1),
          ],
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundImage: session.photo != null
                ? NetworkImage(Config.getPhotoUrl(session.photo!))
                : null,
            child: session.photo == null
                ? Text(_getInitials(session.title))
                : null,
          ),
          title: Text(
            session.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: session.lastMessage != null
              ? Text(
                  session.lastMessage!.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600]),
                )
              : null,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (session.lastMessage != null)
                Text(
                  timeago.format(session.lastMessage!.createdAt),
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              // if (session.unreadCount > 0)
              //   Container(
              //     padding: const EdgeInsets.all(6),
              //     decoration: BoxDecoration(
              //       color: Colors.redAccent,
              //       borderRadius: BorderRadius.circular(15),
              //     ),
              //     child: Text(
              //       session.unreadCount.toString(),
              //       style: const TextStyle(color: Colors.white, fontSize: 12),
              //     ),
              //   ),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String? title) {
    if (title == null || title.trim().isEmpty) {
      return '?';
    }
    return title.trim().substring(0, 1).toUpperCase();
  }
}
