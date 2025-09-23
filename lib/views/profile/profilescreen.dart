import 'package:acent_messenger/providers/auth_provider.dart';
import 'package:acent_messenger/constants/config.dart';
import 'package:acent_messenger/services/auth_service.dart';
import 'package:acent_messenger/services/config_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:acent_messenger/views/authentication/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final ConfigService _configService = ConfigService.instance;
  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _usernameController;
  String _gender = 'Male';
  DateTime? _birthday;
  Language? _selectedLanguage;
  List<Language> _supportedLanguages = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final profile = Provider.of<AuthProvider>(context, listen: false).profile;
    _firstNameController =
        TextEditingController(text: profile?.firstName ?? '');
    _lastNameController = TextEditingController(text: profile?.lastName ?? '');
    _usernameController = TextEditingController(text: profile?.username ?? '');

    _gender = profile?.gender ?? 'Male';

    if (profile?.dob != null) {
      try {
        _birthday = DateTime.parse(profile!.dob!);
      } catch (e) {
        _birthday = null;
      }
    } else {
      _birthday = null;
    }

    _loadLanguages();
  }

  Future<void> _loadLanguages() async {
    try {
      final languages = await _configService.getSupportedLanguages();
      final profile = Provider.of<AuthProvider>(context, listen: false).profile;

      if (languages.isEmpty) {
        // Fallback to default languages if config fails
        _supportedLanguages = [
          Language(code: 'en', name: 'English', nativeName: 'English'),
          Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
          Language(code: 'es', name: 'Spanish', nativeName: 'Español'),
          Language(code: 'fr', name: 'French', nativeName: 'Français'),
          Language(code: 'de', name: 'German', nativeName: 'Deutsch'),
        ];
      } else {
        _supportedLanguages = languages;
      }

      setState(() {
        if (profile?.language != null) {
          try {
            _selectedLanguage = _supportedLanguages.firstWhere(
              (lang) => lang.code == profile!.language,
            );
          } catch (e) {
            // If user's language is not found, default to English or first available
            _selectedLanguage = _supportedLanguages.firstWhere(
              (lang) => lang.code == 'en',
              orElse: () => _supportedLanguages.first,
            );
          }
        } else {
          // Default to English if available, otherwise first language
          _selectedLanguage = _supportedLanguages.firstWhere(
            (lang) => lang.code == 'en',
            orElse: () => _supportedLanguages.first,
          );
        }
      });
    } catch (e) {
      // Fallback to minimal language set if everything fails
      setState(() {
        _supportedLanguages = [
          Language(code: 'en', name: 'English', nativeName: 'English'),
          Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
        ];
        _selectedLanguage = _supportedLanguages.first;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Using default languages. Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _updateProfile() async {
    if (_firstNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your first name')),
      );
      return;
    }

    if (_usernameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a username')),
      );
      return;
    }

    // Basic username validation
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(_usernameController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Username can only contain letters, numbers, and underscores')),
      );
      return;
    }

    if (_usernameController.text.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Username must be at least 3 characters long')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final token = await _authService.getToken();

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final requestBody = {
        'firstName': _firstNameController.text,
        'lastName': _lastNameController.text,
        'username': _usernameController.text,
        'gender': _gender,
      };

      if (_birthday != null) {
        requestBody['dob'] = DateFormat('yyyy-MM-dd').format(_birthday!);
      }

      if (_selectedLanguage != null) {
        requestBody['language'] = _selectedLanguage!.code;
      }

      final response = await http.post(
        Uri.parse('${Config.baseApiUrl}/profile/updateProfile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        await Provider.of<AuthProvider>(context, listen: false).fetchProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );
          Navigator.pop(context);
        }
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to update profile');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
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

  Future<void> _showEditProfileDialog(BuildContext context) async {
    final profile = Provider.of<AuthProvider>(context, listen: false).profile;
    _firstNameController.text = profile?.firstName ?? '';
    _lastNameController.text = profile?.lastName ?? '';
    _usernameController.text = profile?.username ?? '';

    _gender = profile?.gender ?? 'Male';
    if (profile?.dob != null) {
      try {
        _birthday = DateTime.parse(profile!.dob!);
      } catch (e) {
        _birthday = null;
      }
    } else {
      _birthday = null;
    }

    // Reload selected language
    if (profile?.language != null && _supportedLanguages.isNotEmpty) {
      _selectedLanguage = _supportedLanguages.firstWhere(
        (lang) => lang.code == profile!.language,
        orElse: () => _supportedLanguages.first,
      );
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Edit Profile',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    label: 'First Name',
                    controller: _firstNameController,
                    icon: Icons.person,
                  ),
                  _buildTextField(
                    label: 'Last Name',
                    controller: _lastNameController,
                    icon: Icons.person,
                  ),
                  _buildTextField(
                    label: 'Username',
                    controller: _usernameController,
                    icon: Icons.alternate_email,
                  ),
                  _buildTextField(
                    label: 'Phone Number',
                    initialValue:
                        '${profile?.dialCode ?? ''} ${profile?.phone ?? ''}',
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                    readOnly: true,
                  ),
                  _buildDropdownField(
                    label: 'Gender',
                    value: _gender,
                    icon: Icons.wc,
                    items: ['Male', 'Female', 'Other'],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          _gender = value;
                        });
                      }
                    },
                  ),
                  _buildLanguageDropdownField(
                    label: 'Language',
                    value: _selectedLanguage,
                    icon: Icons.language,
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          _selectedLanguage = value;
                        });
                      }
                    },
                  ),
                  _buildDateField(
                    label: 'Date of Birth',
                    value: _birthday,
                    icon: Icons.calendar_today,
                    onDateSelected: (date) {
                      setDialogState(() {
                        _birthday = date;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _isLoading ? null : _updateProfile,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Text(
                                'Save',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.white),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<void> _uploadPhoto(File imageFile) async {
    setState(() {
      _isUploadingPhoto = true;
    });

    try {
      final token = await _authService.getToken();

      if (token == null) {
        throw Exception('Not authenticated');
      }

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Config.baseApiUrl}/profile/uploadPhoto'),
      );

      request.headers.addAll({
        'Authorization': 'Bearer $token',
      });

      request.files.add(
        await http.MultipartFile.fromPath(
          'photo',
          imageFile.path,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        await Provider.of<AuthProvider>(context, listen: false).fetchProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile photo updated successfully')),
          );
        }
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to upload photo');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image != null) {
        await _uploadPhoto(File(image.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  String _getLanguageDisplayName(String languageCode) {
    final language = _supportedLanguages.firstWhere(
      (lang) => lang.code == languageCode,
      orElse: () => Language(
          code: languageCode, name: languageCode, nativeName: languageCode),
    );
    return '${language.nativeName} (${language.name})';
  }

  Widget _buildTextField({
    required String label,
    String? initialValue,
    TextEditingController? controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        initialValue: initialValue,
        keyboardType: keyboardType,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required IconData icon,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: items.map((String value) {
          return DropdownMenuItem<String>(value: value, child: Text(value));
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildLanguageDropdownField({
    required String label,
    required Language? value,
    required IconData icon,
    required Function(Language?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<Language>(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        value: value,
        items: _supportedLanguages.map((Language language) {
          return DropdownMenuItem<Language>(
            value: language,
            child: Text('${language.nativeName} (${language.name})'),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? value,
    required IconData icon,
    required Function(DateTime?) onDateSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          suffixIcon: value != null
              ? IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () {
                    onDateSelected(null);
                  },
                )
              : null,
        ),
        readOnly: true,
        controller: TextEditingController(
          text: value != null
              ? DateFormat('dd/MM/yyyy').format(value)
              : 'Select date',
        ),
        onTap: () async {
          DateTime? pickedDate = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
          );
          if (pickedDate != null) {
            onDateSelected(pickedDate);
          }
        },
      ),
    );
  }

  Widget _buildProfileInfo({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final profile = authProvider.profile;
        if (profile == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final fullName = [
          profile.firstName,
          profile.lastName,
        ].where((name) => name != null && name.isNotEmpty).join(' ');

        final displayGender = profile.gender ?? 'Not specified';
        final displayBirthday = profile.dob != null
            ? (() {
                try {
                  final date = DateTime.parse(profile.dob!);
                  return DateFormat('dd MMMM yyyy').format(date);
                } catch (e) {
                  return '-';
                }
              })()
            : '-';

        final displayLanguage = profile.language != null
            ? _getLanguageDisplayName(profile.language!)
            : 'Not specified';

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text('Profile'),
            backgroundColor: Colors.white,
            elevation: 1,
            iconTheme: const IconThemeData(color: Colors.black),
            titleTextStyle: const TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showEditProfileDialog(context),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundImage: profile.photo != null
                          ? NetworkImage(Config.getPhotoUrl(profile.photo))
                          : null,
                      child: profile.photo == null
                          ? Text(
                              '${(profile.firstName?.substring(0, 1).toUpperCase() ?? "")}'
                              '${(profile.lastName?.substring(0, 1).toUpperCase() ?? "")}',
                              style: const TextStyle(fontSize: 36),
                            )
                          : null,
                    ),
                    if (_isUploadingPhoto)
                      const Positioned.fill(
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white),
                          onPressed: _pickAndUploadImage,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  fullName.isEmpty ? 'No Name' : fullName,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Column(
                  children: [
                    _buildProfileInfo(
                      label: 'Phone',
                      value: '${profile.dialCode ?? ''} ${profile.phone}',
                      icon: Icons.phone,
                    ),
                    if (profile.username != null &&
                        profile.username!.isNotEmpty)
                      _buildProfileInfo(
                        label: 'Username',
                        value: '@${profile.username}',
                        icon: Icons.alternate_email,
                      ),
                    _buildProfileInfo(
                      label: 'Gender',
                      value: displayGender,
                      icon: Icons.wc,
                    ),
                    _buildProfileInfo(
                      label: 'Date of Birth',
                      value: displayBirthday,
                      icon: Icons.calendar_today,
                    ),
                    _buildProfileInfo(
                      label: 'Language',
                      value: displayLanguage,
                      icon: Icons.language,
                    ),
                    _buildProfileInfo(
                      label: 'Status',
                      value:
                          Config.wordToUpperCase(profile.status ?? 'No status'),
                      icon: Icons.info,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton(
                    onPressed: () async {
                      final shouldLogout = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Logout'),
                          content:
                              const Text('Are you sure you want to logout?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'Logout',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (shouldLogout == true && mounted) {
                        await authProvider.logout();
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Logout',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
