import 'package:flutter/material.dart';
import 'package:flutter_image_stack/flutter_image_stack.dart';
import 'package:provider/provider.dart';
import 'package:chattingapp/providers/group_provider.dart';
import 'package:chattingapp/models/chat_session.dart';
import 'package:chattingapp/constants/config.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../groupsconversations/groupsconversations.dart';

import '../consversations/chatdetailsscreen.dart';

class GroupChatList extends StatelessWidget {
  const GroupChatList({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          centerTitle: true,
          title: const Text(
            'Groups',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: const ChatListView(),
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
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
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

  @override
  Widget build(BuildContext context) {
    return Consumer<GroupProvider>(
      builder: (context, groupProvider, child) {
        print("ChatListView - build: Consumer rebuilding. Sessions: ${groupProvider.sessions.length}, Loading: ${groupProvider.isLoading}");
        
        if (groupProvider.sessions.isEmpty && groupProvider.isLoading) {
          print("ChatListView - build: Showing loading indicator");
          return const Center(child: CircularProgressIndicator());
        }

        if (groupProvider.sessions.isEmpty) {
          print("ChatListView - build: No groups to display");
          return const Center(child: Text('No groups yet'));
        }

        print("ChatListView - build: Building group list with ${groupProvider.sessions.length} items");
        return RefreshIndicator(
          onRefresh: () {
            print("ChatListView - build: Refreshing groups");
            return groupProvider.refreshSessions();
          },
          child: ListView.builder(
            controller: _scrollController,
            itemCount: groupProvider.sessions.length + (groupProvider.hasMore ? 1 : 0),
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
              print("ChatListView - build: Building group tile for ${session.title}");
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
                ? Text(session.title.substring(0, 1).toUpperCase())
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
}
