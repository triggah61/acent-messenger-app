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
      return [];
    }
  }
} 