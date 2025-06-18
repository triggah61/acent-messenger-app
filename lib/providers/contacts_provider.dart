import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../constants/config.dart';
import '../services/auth_service.dart';

class BackendContact {
  final String id;
  final String firstName;
  final String lastName;
  final String? username;
  final String dialCode;
  final String phone;
  final String? photo;
  final String searchedPhone;

  BackendContact({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.username,
    required this.dialCode,
    required this.phone,
    this.photo,
    required this.searchedPhone,
  });

  factory BackendContact.fromJson(Map<String, dynamic> json) {
    // Handle MongoDB ObjectId format
    String id = '';
    if (json['_id'] != null) {
      if (json['_id'] is Map<String, dynamic> && json['_id']['\$oid'] != null) {
        // Handle ObjectId format: {"$oid": "64abc123..."}
        id = json['_id']['\$oid'].toString();
      } else {
        // Handle string format or other formats
        id = json['_id'].toString();
      }
    }
    
    return BackendContact(
      id: id,
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      username: json['username']?.toString(),
      dialCode: json['dialCode']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      photo: json['photo']?.toString(),
      searchedPhone: json['searchedPhone']?.toString() ?? '',
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

  factory FormattedContact.fromPhoneContact(
    Contact contact, 
    bool isExisting, 
    {BackendContact? backendContact, String? matchedPhoneNumber}
  ) {
    // Split the display name into first and last name
    final nameParts = contact.displayName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    // Use the matched phone number if provided, otherwise use the first available
    final number = matchedPhoneNumber ?? 
        (contact.phones.isNotEmpty 
            ? contact.phones.first.number.replaceAll(RegExp(r'[^0-9+]'), '')
            : '');

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

class ContactsProvider with ChangeNotifier {
  List<FormattedContact> _formattedContacts = [];
  bool _isLoading = false;
  bool _permissionDenied = false;
  final AuthService _authService = AuthService();

  List<FormattedContact> get formattedContacts => _formattedContacts;
  bool get isLoading => _isLoading;
  bool get permissionDenied => _permissionDenied;

  // Get only existing contacts
  List<FormattedContact> get existingContacts => 
      _formattedContacts.where((contact) => contact.isExisting).toList();

  // Get only non-existing contacts
  List<FormattedContact> get nonExistingContacts => 
      _formattedContacts.where((contact) => !contact.isExisting).toList();

  Future<void> loadContacts() async {
    _isLoading = true;
    _permissionDenied = false;
    notifyListeners();

    Map<Permission, PermissionStatus> statuses = await [
      Permission.contacts,
    ].request();

    if (statuses[Permission.contacts]!.isGranted) {
      await _fetchContacts();
    } else {
      _isLoading = false;
      _permissionDenied = true;
      notifyListeners();
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

      // Format contacts
      final formattedContacts = contacts.map((contact) {
        final contactNumbers = contact.phones
            .map((phone) => phone.number.replaceAll(RegExp(r'[^0-9+]'), ''))
            .where((number) => number.isNotEmpty)
            .toList();

        // Find matching backend contact using searchedPhone field
        BackendContact? matchingBackendContact;
        String? matchedNumber;
        for (var number in contactNumbers) {
          // Check each backend contact for this number
          for (var backendContact in existingContacts) {
            if (backendContact.searchedPhone == number) {
              matchingBackendContact = backendContact;
              matchedNumber = number;
              break;
            }
          }
          
          if (matchingBackendContact != null) {
            break;
          }
        }

        final isExisting = matchingBackendContact != null;
        final formattedContact = FormattedContact.fromPhoneContact(
          contact, 
          isExisting,
          backendContact: matchingBackendContact,
          matchedPhoneNumber: matchedNumber,
        );
        
        return formattedContact;
      }).toList();

      _formattedContacts = formattedContacts;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('Error in _fetchContacts: $e');
      _isLoading = false;
      notifyListeners();
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
        
        // Handle both array and map responses
        List<dynamic> contactsJson;
        if (data is List) {
          contactsJson = data;
        } else if (data is Map<String, dynamic> && data.containsKey('contacts')) {
          contactsJson = data['contacts'] ?? [];
        } else {
          contactsJson = [];
        }
        
        return contactsJson.map((json) {
          try {
            return BackendContact.fromJson(json);
          } catch (e) {
            print('❌ Error parsing backend contact: $e');
            print('   JSON: $json');
            // Return null for invalid contacts, will be filtered out
            return null;
          }
        }).where((contact) => contact != null).cast<BackendContact>().toList();
      }
      return [];
    } catch (e) {
      print('Error in _checkExistingContacts: $e');
      return [];
    }
  }

  // Clear all contacts data (for logout)
  void clearAllData() {
    _formattedContacts.clear();
    _isLoading = false;
    _permissionDenied = false;
    notifyListeners();
  }
} 