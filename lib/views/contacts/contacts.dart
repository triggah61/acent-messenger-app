import 'package:chattingapp/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:chattingapp/constants/config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../widgets/auth_middleware.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  Map<String, bool> _existingContacts = {};
  bool _isLoading = true;
  bool _permissionDenied = false;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

    // Request both READ and WRITE contacts permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.contacts,
    ].request();

    if (statuses[Permission.contacts]!.isGranted) {
      await _fetchContacts();
    } else {
      setState(() {
        _isLoading = false;
        _permissionDenied = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contacts permission is required. Please enable it in settings.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _fetchContacts() async {
    try {
      // Get all contacts
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: true,
      );

      print(contacts);

      // Extract phone numbers
      final phoneNumbers = contacts
          .expand((contact) => contact.phones)
          .map((phone) => phone.number.replaceAll(RegExp(r'[^0-9+]'), ''))
          .where((number) => number.isNotEmpty)
          .toList();

      // Check existing contacts with backend
      await _checkExistingContacts(phoneNumbers);

      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading contacts: $e')),
        );
      }
    }
  }

  Future<void> _checkExistingContacts(List<String> phoneNumbers) async {

      final token = await _authService.getToken();
    try {
      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/contact/checkPhoneNumbers'),
        headers: {'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'phoneNumbers': phoneNumbers}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Assuming the response contains a list of existing phone numbers
        final existingNumbers =
            List<String>.from(data['existingNumbers'] ?? []);

        setState(() {
          _existingContacts = {
            for (var number in phoneNumbers)
              number: existingNumbers.contains(number)
          };
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking contacts: $e')),
        );
      }
    }
  }

  void _handleContactAction(Contact contact) {
    final phoneNumbers = contact.phones
        .map((phone) => phone.number.replaceAll(RegExp(r'[^0-9+]'), ''))
        .where((number) => number.isNotEmpty)
        .toList();

    if (phoneNumbers.isEmpty) return;

    final isExisting =
        phoneNumbers.any((number) => _existingContacts[number] == true);

    if (isExisting) {
      // Navigate to chat
      // TODO: Implement chat navigation
    } else {
      // Send invitation
      // TODO: Implement invitation sending
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
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _permissionDenied
                          ? Center(
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
                            )
                          : Padding(
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
                                    child: _contacts.isEmpty
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
                                            itemCount: _contacts.length,
                                            itemBuilder: (context, index) {
                                              final contact = _contacts[index];
                                              final phoneNumbers = contact
                                                  .phones
                                                  .map((phone) => phone.number
                                                      .replaceAll(
                                                          RegExp(r'[^0-9+]'),
                                                          ''))
                                                  .where((number) =>
                                                      number.isNotEmpty)
                                                  .toList();

                                              final isExisting = phoneNumbers
                                                      .isNotEmpty &&
                                                  phoneNumbers.any((number) =>
                                                      _existingContacts[
                                                          number] ==
                                                      true);

                                              return _buildContactItem(
                                                name: contact.displayName,
                                                status: isExisting
                                                    ? 'Send Message'
                                                    : 'Send Invitation',
                                                imageUrl: contact.photo != null
                                                    ? 'data:image/jpeg;base64,${base64Encode(contact.photo!)}'
                                                    : 'https://via.placeholder.com/150',
                                                isExisting: isExisting,
                                                onTap: () =>
                                                    _handleContactAction(
                                                        contact),
                                              );
                                            },
                                          ),
                                  ),
                                ],
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
