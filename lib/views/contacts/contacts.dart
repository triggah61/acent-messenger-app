import 'package:chattingapp/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:chattingapp/constants/config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../widgets/auth_middleware.dart';
import 'package:provider/provider.dart';
import '../../providers/contacts_provider.dart';
import '../../services/chat_service.dart';
import 'invitation_screen.dart';
import '../consversations/chatdetailsscreen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ChatService _chatService = ChatService(AuthService());

  @override
  void initState() {
    super.initState();
    // Load contacts when screen initializes
    Future.microtask(() => context.read<ContactsProvider>().loadContacts());
  }

  Future<void> _handleContactAction(FormattedContact contact) async {
    if (contact.isExisting && contact.id != null) {
      try {
        // Show loading indicator
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening chat...'),
              duration: Duration(seconds: 1),
            ),
          );
        }

        // Find or create chat session
        final chatSession = await _chatService.findOrCreateSession(contact.id!);

        // Navigate to chat details screen
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Conversations(
                session: chatSession,
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error opening chat: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // Navigate to invitation screen for non-existing contacts
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => InvitationScreen(
              contact: contact,
            ),
          ),
        );
      }
    }
  }

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
                    IconButton(
                      icon: const Icon(Icons.search, color: Colors.white),
                      onPressed: () {},
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                      ),
                    ),
                    const Text('Contacts',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: const Icon(Icons.person_add, color: Colors.white),
                      onPressed: () {},
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue[400],
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
                  child: Consumer<ContactsProvider>(
                    builder: (context, contactsProvider, child) {
                      if (contactsProvider.isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (contactsProvider.permissionDenied) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.no_accounts,
                                size: 64,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Contacts Permission Required',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Please enable contacts access in settings',
                                style: TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () async {
                                  await openAppSettings();
                                },
                                child: const Text('Open Settings'),
                              ),
                            ],
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('My Contacts',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87)),
                            const SizedBox(height: 20),
                            Expanded(
                              child: contactsProvider.formattedContacts.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No contacts found',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: contactsProvider
                                          .formattedContacts.length,
                                      itemBuilder: (context, index) {
                                        final contact = contactsProvider
                                            .formattedContacts[index];
                                        return _buildContactItem(
                                          name:
                                              '${contact.firstName} ${contact.lastName}'
                                                  .trim(),
                                          status: contact.isExisting
                                              ? 'Send Message'
                                              : 'Send Invitation',
                                          imageUrl: contact.photo != null &&
                                                  contact.isExisting
                                              ? Config.getPhotoUrl(
                                                  contact.photo)
                                              : contact.photo != null
                                                  ? 'data:image/jpeg;base64,${contact.photo}'
                                                  : "",
                                          isExisting: contact.isExisting,
                                          onTap: () =>
                                              _handleContactAction(contact),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactItem({
    required String name,
    required String status,
    required String imageUrl,
    required bool isExisting,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: imageUrl.startsWith('data:')
                  ? MemoryImage(base64Decode(imageUrl.split(',')[1]))
                  : NetworkImage(imageUrl) as ImageProvider,
              child: imageUrl.isEmpty ? Text(name.substring(0, 1).toUpperCase()) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 14,
                      color: isExisting ? Colors.blue : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isExisting ? Icons.message : Icons.person_add,
              color: isExisting ? Colors.blue : Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }
}
