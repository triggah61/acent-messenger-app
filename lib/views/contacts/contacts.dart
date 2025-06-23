import 'package:acent_messenger/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:acent_messenger/constants/config.dart';
import 'dart:convert';
import '../../widgets/auth_middleware.dart';
import 'package:provider/provider.dart';
import '../../providers/contacts_provider.dart';
import '../../services/chat_service.dart';
import 'invitation_screen.dart';
import '../consversations/chatdetailsscreen.dart';
import 'package:http/http.dart' as http;

// Global contact model for search results
class GlobalContact {
  final String id;
  final String firstName;
  final String lastName;
  final String? username;
  final String dialCode;
  final String phone;
  final String? photo;

  GlobalContact({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.username,
    required this.dialCode,
    required this.phone,
    this.photo,
  });

  factory GlobalContact.fromJson(Map<String, dynamic> json) {
    return GlobalContact(
      id: json['_id'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      username: json['username'],
      dialCode: json['dialCode'] ?? '',
      phone: json['phone'] ?? '',
      photo: json['photo'],
    );
  }
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ChatService _chatService = ChatService(AuthService());
  final AuthService _authService = AuthService();
  
  // Search related state
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<FormattedContact> _filteredContacts = [];
  List<GlobalContact> _globalSearchResults = [];
  bool _isGlobalSearchLoading = false;

  @override
  void initState() {
    super.initState();
    // Load contacts when screen initializes
    Future.microtask(() => context.read<ContactsProvider>().loadContacts());
    
    // Listen to search input changes
    _searchController.addListener(_performSearch);
  }

  @override
  void dispose() {
    _searchController.removeListener(_performSearch);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    final provider = context.read<ContactsProvider>();
    final query = _searchController.text.toLowerCase().trim();
    
    if (query.isEmpty) {
      setState(() {
        _filteredContacts = _sortContacts(provider.formattedContacts);
        _globalSearchResults.clear();
      });
      return;
    }

    // Perform local search
    setState(() {
      _filteredContacts = _sortContacts(
        provider.formattedContacts.where((contact) {
          final firstName = contact.firstName?.toLowerCase() ?? '';
          final lastName = contact.lastName?.toLowerCase() ?? '';
          final fullName = '$firstName $lastName'.trim();
          final number = contact.number?.toLowerCase() ?? '';
          final username = contact.username?.toLowerCase() ?? '';
          
          return firstName.contains(query) ||
                 lastName.contains(query) ||
                 fullName.contains(query) ||
                 number.contains(query) ||
                 username.contains(query);
        }).toList(),
      );
    });

    // Perform global search if query has 3 or more characters
    if (query.length >= 3) {
      _performGlobalSearch(query);
    } else {
      setState(() {
        _globalSearchResults.clear();
      });
    }
  }

  Future<void> _performGlobalSearch(String query) async {
    setState(() {
      _isGlobalSearchLoading = true;
    });

    try {
      final token = await _authService.getToken();
      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Get list of existing contact IDs to exclude from global search
      final provider = context.read<ContactsProvider>();
      final existingContactIds = provider.formattedContacts
          .where((contact) => contact.isExisting && contact.id != null)
          .map((contact) => contact.id!)
          .toList();

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/user/contact/globalSearch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'search': query,
          'except': existingContactIds,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> results = data is List ? data : (data['users'] ?? []);
        
        setState(() {
          _globalSearchResults = results
              .map((json) => GlobalContact.fromJson(json))
              .toList();
        });
      } else {
        setState(() {
          _globalSearchResults.clear();
        });
      }
    } catch (e) {
      print('Global search error: $e');
      setState(() {
        _globalSearchResults.clear();
      });
    } finally {
      setState(() {
        _isGlobalSearchLoading = false;
      });
    }
  }

  List<FormattedContact> _sortContacts(List<FormattedContact> contacts) {
    final sortedContacts = List<FormattedContact>.from(contacts);
    
    sortedContacts.sort((a, b) {
      // First sort by existing users (registered users first)
      if (a.isExisting && !b.isExisting) return -1;
      if (!a.isExisting && b.isExisting) return 1;
      
      // Then sort alphabetically by name
      final nameA = '${a.firstName ?? ''} ${a.lastName ?? ''}'.trim().toLowerCase();
      final nameB = '${b.firstName ?? ''} ${b.lastName ?? ''}'.trim().toLowerCase();
      
      return nameA.compareTo(nameB);
    });
    
    return sortedContacts;
  }

  void _toggleSearch() {
    setState(() {
      if (_isSearching) {
        // Closing search
        _isSearching = false;
        _searchController.clear();
        _searchFocusNode.unfocus();
        _globalSearchResults.clear();
      } else {
        // Opening search
        _isSearching = true;
        Future.delayed(const Duration(milliseconds: 100), () {
          _searchFocusNode.requestFocus();
        });
      }
    });
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

  Future<void> _handleGlobalContactAction(GlobalContact contact) async {
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

      // Find or create chat session for global contact
      final chatSession = await _chatService.findOrCreateSession(contact.id);

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
  }

  Widget _buildSearchBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isSearching ? MediaQuery.of(context).size.width - 80 : 48,
      height: 48,
      child: _isSearching
          ? Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Search contacts...',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: _toggleSearch,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: const TextStyle(color: Colors.black),
              ),
            )
          : IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: _toggleSearch,
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey[800],
              ),
            ),
    );
  }

  Future<void> _refreshContacts() async {
    try {
      // Clear search state when refreshing
      if (_isSearching) {
        setState(() {
          _searchController.clear();
          _filteredContacts.clear();
          _globalSearchResults.clear();
        });
      }

      // Trigger contacts reload from ContactsProvider
      await context.read<ContactsProvider>().loadContacts();
      
      // Show success message
      if (mounted) {
        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(
        //     content: Text('Contacts refreshed successfully'),
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
            content: Text('Failed to refresh contacts: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildSearchResults() {
    final hasLocalResults = _filteredContacts.isNotEmpty;
    final hasGlobalResults = _globalSearchResults.isNotEmpty;
    final hasQuery = _searchController.text.isNotEmpty;

    if (!hasQuery) {
      return _buildContactsList();
    }

    return RefreshIndicator(
      onRefresh: _refreshContacts,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Local Search Results
            if (hasLocalResults) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'My Contacts (${_filteredContacts.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _filteredContacts.length,
                itemBuilder: (context, index) {
                  final contact = _filteredContacts[index];
                  return _buildContactItem(
                    name: '${contact.firstName ?? ''} ${contact.lastName ?? ''}'.trim(),
                    username: contact.username,
                    status: contact.isExisting ? 'Send Message' : 'Send Invitation',
                    imageUrl: contact.photo != null && contact.isExisting
                        ? Config.getPhotoUrl(contact.photo)
                        : contact.photo != null
                            ? 'data:image/jpeg;base64,${contact.photo}'
                            : "",
                    isExisting: contact.isExisting,
                    onTap: () => _handleContactAction(contact),
                  );
                },
              ),
            ],

            // Global Search Results
            if (_isGlobalSearchLoading) ...[
              if (hasLocalResults) const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Global Search',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ] else if (hasGlobalResults) ...[
              if (hasLocalResults) const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  'Global Search (${_globalSearchResults.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _globalSearchResults.length,
                itemBuilder: (context, index) {
                  final contact = _globalSearchResults[index];
                  return _buildGlobalContactItem(
                    contact: contact,
                    onTap: () => _handleGlobalContactAction(contact),
                  );
                },
              ),
            ],

            // No Results Message
            if (!hasLocalResults && !hasGlobalResults && !_isGlobalSearchLoading) ...[
              Container(
                height: MediaQuery.of(context).size.height * 0.5,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No results found',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                        ),
                      ),
                      if (_searchController.text.length < 3) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Type at least 3 characters for global search',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            // Add extra space at bottom for better pull-to-refresh experience
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsList() {
    return Consumer<ContactsProvider>(
      builder: (context, contactsProvider, child) {
        // Initialize filtered contacts if empty
        if (_filteredContacts.isEmpty && contactsProvider.formattedContacts.isNotEmpty) {
          _filteredContacts = _sortContacts(contactsProvider.formattedContacts);
        }

        final contactsToShow = _sortContacts(contactsProvider.formattedContacts);

        return RefreshIndicator(
          onRefresh: _refreshContacts,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: contactsToShow.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Container(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.contacts,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No contacts available',
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
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: contactsToShow.length,
                    itemBuilder: (context, index) {
                      final contact = contactsToShow[index];
                      return _buildContactItem(
                        name: '${contact.firstName ?? ''} ${contact.lastName ?? ''}'.trim(),
                        username: contact.username,
                        status: contact.isExisting ? 'Send Message' : 'Send Invitation',
                        imageUrl: contact.photo != null && contact.isExisting
                            ? Config.getPhotoUrl(contact.photo)
                            : contact.photo != null
                                ? 'data:image/jpeg;base64,${contact.photo}'
                                : "",
                        isExisting: contact.isExisting,
                        onTap: () => _handleContactAction(contact),
                      );
                    },
                  ),
          ),
        );
      },
    );
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
                    if (!_isSearching) ...[
                      const SizedBox(width: 48), // Placeholder for balance
                      Expanded(
                        child: Center(
                          child: const Text(
                            'Contacts',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                    _buildSearchBar(),
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

                      return _buildSearchResults();
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
    String? username,
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
                  : imageUrl.isNotEmpty
                      ? NetworkImage(imageUrl) as ImageProvider
                      : null,
              child: imageUrl.isEmpty ? Text(_getInitials(name)) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unknown Contact' : name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (username != null && username.isNotEmpty && isExisting) ...[
                    Text(
                      '@$username',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[600],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
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

  Widget _buildGlobalContactItem({
    required GlobalContact contact,
    required VoidCallback onTap,
  }) {
    final name = '${contact.firstName} ${contact.lastName}'.trim();
    final imageUrl = contact.photo != null ? Config.getPhotoUrl(contact.photo!) : '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundImage: imageUrl.isNotEmpty
                  ? NetworkImage(imageUrl) as ImageProvider
                  : null,
              child: imageUrl.isEmpty ? Text(_getInitials(name)) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unknown User' : name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (contact.username != null && contact.username!.isNotEmpty) ...[
                    Text(
                      '@${contact.username}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[600],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  Text(
                    '${contact.dialCode} ${contact.phone}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.message,
              color: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }
  
  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) {
      return '?';
    }
    final words = name.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0].substring(0, 1).toUpperCase()}${words[1].substring(0, 1).toUpperCase()}';
    }
    return name.trim().substring(0, 1).toUpperCase();
  }
}
