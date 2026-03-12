import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'theme_provider.dart';
import 'theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final String _cloudName = "dnv6ezitm";
  final String _uploadPreset = "resort_unsigned";

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _gcashNumberController = TextEditingController();
  final _gcashNameController = TextEditingController();
  
  String? _profilePicUrl;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _gcashNumberController.dispose();
    _gcashNameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    final snapshot = await FirebaseDatabase.instance.ref("users/${user?.uid}").get();
    
    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      _firstNameController.text = data['firstName'] ?? '';
      _middleNameController.text = data['middleName'] ?? '';
      _lastNameController.text = data['lastName'] ?? '';
      _phoneController.text = data['phoneNumber'] ?? '';
      _gcashNumberController.text = data['gcashNumber'] ?? '';
      _gcashNameController.text = data['gcashName'] ?? '';
      _profilePicUrl = data['profilePicUrl'];
    }
    setState(() => _isLoading = false);
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (file != null) {
      setState(() => _isUploading = true);
      try {
        final url = Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/image/upload");
        final request = http.MultipartRequest("POST", url)
          ..fields['upload_preset'] = _uploadPreset
          ..files.add(await http.MultipartFile.fromPath('file', file.path));

        final response = await request.send();
        if (response.statusCode == 200) {
          final responseData = await response.stream.bytesToString();
          final String newUrl = jsonDecode(responseData)['secure_url'];
          setState(() => _profilePicUrl = newUrl);
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload Failed: $e")));
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      await FirebaseDatabase.instance.ref("users/${user?.uid}").update({
        'firstName': _firstNameController.text.trim(),
        'middleName': _middleNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'gcashNumber': _gcashNumberController.text.trim(),
        'gcashName': _gcashNameController.text.trim(),
        'profilePicUrl': _profilePicUrl,
      });

      final snapshot = await FirebaseDatabase.instance.ref("users/${user?.uid}/role").get();
      if (snapshot.value == 'Owner') {
        await FirebaseDatabase.instance.ref("properties/${user?.uid}").update({
          'gcashNumber': _gcashNumberController.text.trim(),
          'gcashName': _gcashNameController.text.trim(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.primaryAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: const Text('Account Settings', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        actions: [
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () => themeProvider.toggleTheme(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _isUploading ? null : _pickAndUploadImage,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
                          ),
                          child: CircleAvatar(
                            radius: 70,
                            backgroundColor: Theme.of(context).colorScheme.surface,
                            backgroundImage: _profilePicUrl != null ? NetworkImage(_profilePicUrl!) : null,
                            child: _profilePicUrl == null 
                              ? Icon(Icons.person_rounded, size: 70, color: secondaryColor.withOpacity(0.2))
                              : null,
                          ),
                        ),
                        if (_isUploading)
                          const CircularProgressIndicator(),
                        Positioned(
                          bottom: 5,
                          right: 5,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: secondaryColor, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.surface, width: 3)),
                            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildSectionCard('Personal Information', [
                    _buildTextField(_firstNameController, 'First Name', Icons.person_rounded),
                    const SizedBox(height: 16),
                    _buildTextField(_middleNameController, 'Middle Name', Icons.person_outline_rounded),
                    const SizedBox(height: 16),
                    _buildTextField(_lastNameController, 'Last Name', Icons.person_rounded),
                    const SizedBox(height: 16),
                    _buildTextField(
                      _phoneController, 
                      'Phone Number', 
                      Icons.phone_android_rounded,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 11,
                      validator: (val) => val?.length != 11 ? 'Must be 11 digits' : null,
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _buildSectionCard('GCash Details', [
                    Text('Used for booking down payments and verifications.', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 20),
                    _buildTextField(_gcashNumberController, 'GCash Number', Icons.mobile_friendly_rounded, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 11),
                    const SizedBox(height: 16),
                    _buildTextField(_gcashNameController, 'GCash Registered Name', Icons.badge_rounded),
                  ]),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    child: _isSaving 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('SAVE CHANGES', style: TextStyle(letterSpacing: 1)),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType, List<TextInputFormatter>? inputFormatters, int? maxLength, String? Function(String?)? validator,}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
        counterText: "",
      ),
      validator: validator ?? (value) => value!.isEmpty ? 'Required' : null,
    );
  }
}
