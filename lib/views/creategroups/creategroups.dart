import 'package:acent_messenger/providers/group_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import 'package:acent_messenger/constants/config.dart';
import 'package:http/http.dart' as http;
import '../consversations/chatdetailsscreen.dart';

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

class CreateGroups extends StatefulWidget {
  const CreateGroups({Key? key}) : super(key: key);

  @override
  State<CreateGroups> createState() => _CreateGroupsState();
}

class _CreateGroupsState extends State<CreateGroups> {
  final TextEditingController _titleController = TextEditingController();
  final List<String> _selectedMemberIds = [];
  bool _isLoading = false;
  final ChatService _chatService = ChatService(AuthService());
  List<Contact> _contacts = [];
  bool _isContactsLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    setState(() {
      _isContactsLoading = true;
    });
    try {
      final token = await AuthService().getToken();
      if (token == null) throw Exception('No token');
      final response = await http.get(
        Uri.parse('${Config.baseApiUrl}/user/contact/list'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch contacts: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isContactsLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a group title'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one member'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final chatSession = await _chatService.createGroup(
        _titleController.text.trim(),
        _selectedMemberIds,
      );
      await context.read<GroupProvider>().fetchSessions(refresh: true);
      if (mounted) {
        Navigator.pushReplacement(
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
            content: Text('Failed to create group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121829),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Group',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Group Details',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText: 'Enter group title',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Select Members',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_selectedMemberIds.length} members selected',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isContactsLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _contacts.isEmpty
                        ? const Center(
                            child: Text(
                              'No contacts available',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _contacts.length,
                            itemBuilder: (context, index) {
                              final contact = _contacts[index];
                              final isSelected = _selectedMemberIds.contains(contact.id);
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundImage: contact.photo != null
                                      ? NetworkImage(Config.getPhotoUrl(contact.photo!))
                                      : null,
                                  child: contact.photo == null
                                      ? Text(contact.firstName.isNotEmpty ? contact.firstName[0].toUpperCase() : '?')
                                      : null,
                                ),
                                title: Text(
                                  '${contact.firstName} ${contact.lastName}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                trailing: Checkbox(
                                  value: isSelected,
                                  onChanged: (bool? value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedMemberIds.add(contact.id);
                                      } else {
                                        _selectedMemberIds.remove(contact.id);
                                      }
                                    });
                                  },
                                ),
                              );
                            },
                          ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createGroup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Create Group',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}