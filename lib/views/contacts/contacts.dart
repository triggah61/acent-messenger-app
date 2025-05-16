import 'package:chattingapp/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:chattingapp/constants/config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../widgets/auth_middleware.dart';

class BackendContact {
  final String id;
  final String firstName;
  final String lastName;
  final String? username;
  final String dialCode;
  final String phone;
  final String? photo;

  BackendContact({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.username,
    required this.dialCode,
    required this.phone,
    this.photo,
  });

  factory BackendContact.fromJson(Map<String, dynamic> json) {
    return BackendContact(
      id: json['_id'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      username: json['username'],
      dialCode: json['dialCode'],
      phone: json['phone'],
      photo: json['photo'],
    );
  }
}

class FormattedContact {
  final String? id;
  final String firstName;
  final String lastName;
  final String number;
  final String? photo;
  final bool isExisting;
  final String? username;
  final String? dialCode;

  FormattedContact({
    this.id,
    required this.firstName,
    required this.lastName,
    required this.number,
    this.photo,
    this.isExisting = false,
    this.username,
    this.dialCode,
  });

  factory FormattedContact.fromPhoneContact(Contact contact, bool isExisting, {BackendContact? backendContact}) {
    // Split the display name into first and last name
    final nameParts = contact.displayName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    // Get the first phone number if available
    final number = contact.phones.isNotEmpty 
        ? contact.phones.first.number.replaceAll(RegExp(r'[^0-9+]'), '')
        : '';

    // Convert photo to base64 if available
    String? photoBase64;
    if (contact.photo != null) {
      photoBase64 = base64Encode(contact.photo!);
    }

    return FormattedContact(
      id: backendContact?.id,
      firstName: backendContact?.firstName ?? firstName,
      lastName: backendContact?.lastName ?? lastName,
      number: number,
      photo: backendContact?.photo ?? photoBase64,
      isExisting: isExisting,
      username: backendContact?.username,
      dialCode: backendContact?.dialCode,
    );
  }

  @override
  String toString() {
    return 'FormattedContact(id: $id, firstName: $firstName, lastName: $lastName, number: $number, isExisting: $isExisting, username: $username, dialCode: $dialCode)';
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<FormattedContact> _formattedContacts = [];
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

      // Extract phone numbers
      final phoneNumbers = contacts
          .expand((contact) => contact.phones)
          .map((phone) => phone.number.replaceAll(RegExp(r'[^0-9+]'), ''))
          .where((number) => number.isNotEmpty)
          .toList();

      // Check existing contacts with backend
      final existingContacts = await _checkExistingContacts(phoneNumbers);
      
      print('Existing contacts from backend: $existingContacts');

      // Format contacts
      final formattedContacts = contacts.map((contact) {
        final contactNumbers = contact.phones
            .map((phone) => phone.number.replaceAll(RegExp(r'[^0-9+]'), ''))
            .where((number) => number.isNotEmpty)
            .toList();

        print('Processing contact: ${contact.displayName}');
        print('Phone numbers: $contactNumbers');

        // Find matching backend contact
        BackendContact? matchingBackendContact;
        for (var number in contactNumbers) {
          try {
            matchingBackendContact = existingContacts.firstWhere(
              (backendContact) {
                final fullNumber = '${backendContact.dialCode}${backendContact.phone}';
                final matches = fullNumber == number || fullNumber.replaceAll('+', '') == number.replaceAll('+', '');
                if (matches) {
                  print('Found match for $number: ${backendContact.firstName} ${backendContact.lastName}');
                }
                return matches;
              },
            );
            if (matchingBackendContact != null) break;
          } catch (e) {
            // No matching contact found, continue to next number
            continue;
          }
        }

        final isExisting = matchingBackendContact != null;
        final formattedContact = FormattedContact.fromPhoneContact(
          contact, 
          isExisting,
          backendContact: matchingBackendContact,
        );
        print('Formatted contact: $formattedContact');
        return formattedContact;
      }).toList();

      print('Formatted contacts: $formattedContacts');

      setState(() {
        _formattedContacts = formattedContacts;
        _isLoading = false;
      });
    } catch (e) {
      print('Error in _fetchContacts: $e'); // Add more detailed error logging
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

  Future<List<BackendContact>> _checkExistingContacts(List<String> phoneNumbers) async {
    try {
      final token = await _authService.getToken();
      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/contact/checkPhoneNumbers'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'phoneNumbers': phoneNumbers}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Backend response: $data');
        
        // Handle both array and map responses
        List<dynamic> contactsJson;
        if (data is List) {
          contactsJson = data;
        } else if (data is Map<String, dynamic> && data.containsKey('contacts')) {
          contactsJson = data['contacts'] ?? [];
        } else {
          contactsJson = [];
        }
        
        return contactsJson.map((json) => BackendContact.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Error in _checkExistingContacts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking contacts: $e')),
        );
      }
      return [];
    }
  }

  void _handleContactAction(FormattedContact contact) {

    print(contact.toString());
    if (contact.isExisting) {

      print('existing');  
      // Navigate to chat
      // TODO: Implement chat navigation
    } else {
      print('not existing');
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
                                    child: _formattedContacts.isEmpty
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
                                            itemCount: _formattedContacts.length,
                                            itemBuilder: (context, index) {
                                              final contact = _formattedContacts[index];
                                              return _buildContactItem(
                                                name: '${contact.firstName} ${contact.lastName}'.trim(),
                                                status: contact.isExisting
                                                    ? 'Send Message'
                                                    : 'Send Invitation',
                                                imageUrl: contact.photo != null
                                                    ? 'data:image/jpeg;base64,${contact.photo}'
                                                    : 'https://via.placeholder.com/150',
                                                isExisting: contact.isExisting,
                                                onTap: () =>
                                                    _handleContactAction(contact),
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
