import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:resortconnectapp/services/ai_service.dart';
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
  String? _gcashQrUrl;
  String? _customId;
  String? _idImageUrl;
  String? _selfieImageUrl;
  String? _identityStatus;
  
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
    final snapshot =
        await FirebaseDatabase.instance.ref("users/${user?.uid}").get();

    if (snapshot.exists) {
      Map data = snapshot.value as Map;
      _firstNameController.text = data['firstName'] ?? '';
      _middleNameController.text = data['middleName'] ?? '';
      _lastNameController.text = data['lastName'] ?? '';
      _phoneController.text = data['phoneNumber'] ?? '';
      _gcashNumberController.text = data['gcashNumber'] ?? '';
      _gcashNameController.text = data['gcashName'] ?? '';
      _profilePicUrl = data['profilePicUrl'];
      _gcashQrUrl = data['gcashQrUrl'];
      _customId = data['customId'];
      _idImageUrl = data['idImageUrl'];
      _selfieImageUrl = data['selfieImageUrl'];
      _identityStatus = data['identityStatus'] ?? 'unverified';
    }
    setState(() => _isLoading = false);
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);

    if (file != null) {
      setState(() => _isUploading = true);
      try {
        final url = Uri.parse(
            "https://api.cloudinary.com/v1_1/$_cloudName/image/upload");
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
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Upload Failed: $e")));
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _pickAndUploadQrImage() async {
    final picker = ImagePicker();
    final XFile? file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (file != null) {
      setState(() => _isUploading = true);
      try {
        final url = Uri.parse(
            "https://api.cloudinary.com/v1_1/$_cloudName/image/upload");
        final request = http.MultipartRequest("POST", url)
          ..fields['upload_preset'] = _uploadPreset
          ..files.add(await http.MultipartFile.fromPath('file', file.path));

        final response = await request.send();
        if (response.statusCode == 200) {
          final responseData = await response.stream.bytesToString();
          final String newUrl = jsonDecode(responseData)['secure_url'];
          setState(() => _gcashQrUrl = newUrl);
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Upload Failed: $e")));
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _pickAndVerifyIdentityImage(bool isSelfie) async {
    final picker = ImagePicker();
    final XFile? file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (file != null) {
      setState(() => _isUploading = true);
      
      // Run AI Face Detection!
      bool hasFace = await AiService.detectFace(File(file.path));
      if (!hasFace) {
        setState(() => _isUploading = false);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
               content: Text("Upload Rejected: No human face detected in the image."), backgroundColor: Colors.red));
        }
        return;
      } else {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
               content: Text("AI Verification Passed: Face detected."), backgroundColor: Colors.green));
        }
      }

      try {
        final url = Uri.parse(
            "https://api.cloudinary.com/v1_1/$_cloudName/image/upload");
        final request = http.MultipartRequest("POST", url)
          ..fields['upload_preset'] = _uploadPreset
          ..files.add(await http.MultipartFile.fromPath('file', file.path));

        final response = await request.send();
        if (response.statusCode == 200) {
          final responseData = await response.stream.bytesToString();
          final String newUrl = jsonDecode(responseData)['secure_url'];
          setState(() {
            if (isSelfie) {
               _selfieImageUrl = newUrl;
            } else {
               _idImageUrl = newUrl;
            }
            _identityStatus = 'pending'; // Automatically pending when they upload
          });
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Upload Failed: $e")));
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
        'gcashQrUrl': _gcashQrUrl,
        'idImageUrl': _idImageUrl,
        'selfieImageUrl': _selfieImageUrl,
        'identityStatus': _identityStatus,
      });

      final snapshot =
          await FirebaseDatabase.instance.ref("users/${user?.uid}/role").get();
      if (snapshot.value == 'Owner') {
        await FirebaseDatabase.instance.ref("properties/${user?.uid}").update({
          'gcashNumber': _gcashNumberController.text.trim(),
          'gcashName': _gcashNameController.text.trim(),
          'gcashQrUrl': _gcashQrUrl,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.primaryAccent),
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
        title: const Text('Account Settings',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        actions: [
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded),
            onPressed: () => themeProvider.toggleTheme(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
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
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10))
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 70,
                              backgroundColor:
                                  Theme.of(context).colorScheme.surface,
                              backgroundImage: _profilePicUrl != null
                                  ? NetworkImage(_profilePicUrl!)
                                  : null,
                              child: _profilePicUrl == null
                                  ? Icon(Icons.person_rounded,
                                      size: 70,
                                      color: secondaryColor.withOpacity(0.2))
                                  : null,
                            ),
                          ),
                          if (_isUploading) const CircularProgressIndicator(),
                          Positioned(
                            bottom: 5,
                            right: 5,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: secondaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color:
                                          Theme.of(context).colorScheme.surface,
                                      width: 3)),
                              child: const Icon(Icons.camera_alt_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_customId != null)
                      Text(
                        _customId!,
                        style: TextStyle(
                            color: secondaryColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            letterSpacing: 1.5),
                      ),
                    const SizedBox(height: 32),
                    _buildSectionCard('Personal Information', [
                      _buildTextField(_firstNameController, 'First Name',
                          Icons.person_rounded, validator: (value) {
                        if (value == null || value.trim().isEmpty)
                          return 'Required';
                        if (value.trim().length < 2) return 'Min 2 characters';
                        if (!RegExp(r"^[a-zA-Z\s]+$").hasMatch(value.trim()))
                          return 'Letters only';
                        return null;
                      }),
                      const SizedBox(height: 16),
                      _buildTextField(_middleNameController, 'Middle Name',
                          Icons.person_outline_rounded, required: false,
                          validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          if (value.trim().length < 2)
                            return 'Min 2 characters';
                          if (!RegExp(r"^[a-zA-Z\s]+$")
                              .hasMatch(value.trim())) return 'Letters only';
                        }
                        return null;
                      }),
                      const SizedBox(height: 16),
                      _buildTextField(_lastNameController, 'Last Name',
                          Icons.person_rounded, validator: (value) {
                        if (value == null || value.trim().isEmpty)
                          return 'Required';
                        if (value.trim().length < 2) return 'Min 2 characters';
                        if (!RegExp(r"^[a-zA-Z\s]+$").hasMatch(value.trim()))
                          return 'Letters only';
                        return null;
                      }),
                      const SizedBox(height: 16),
                      _buildTextField(
                        _phoneController,
                        'Phone Number',
                        Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        maxLength: 11,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty)
                            return 'Required';
                          if (val.trim().length != 11)
                            return 'Must be 11 digits';
                          if (!val.trim().startsWith('09'))
                            return 'Must start with 09';
                          return null;
                        },
                      ),
                    ]),
                    const SizedBox(height: 24),
                    _buildSectionCard('GCash Details', [
                      Text('Used for booking down payments and verifications.',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 20),
                      _buildTextField(
                        _gcashNumberController,
                        'GCash Number',
                        Icons.mobile_friendly_rounded,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        maxLength: 11,
                        validator: (val) {
                          if (val != null && val.trim().isNotEmpty) {
                            if (val.trim().length != 11)
                              return 'Must be 11 digits';
                            if (!val.trim().startsWith('09'))
                              return 'Must start with 09';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(_gcashNameController,
                          'GCash Registered Name', Icons.badge_rounded,
                          required: false,
                          validator: (value) {
                        if (value != null && value.trim().isNotEmpty) {
                          if (!RegExp(r"^[a-zA-Z\s]+$").hasMatch(value.trim()))
                            return 'Letters and spaces only (No special characters)';
                        }
                        return null;
                      }),
                      const SizedBox(height: 16),
                      Text('GCash QR Code (For easy booking payments)',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (_gcashQrUrl != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 16.0),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(_gcashQrUrl!, width: 80, height: 80, fit: BoxFit.cover),
                                  ),
                                  Positioned(
                                    top: -10,
                                    right: -10,
                                    child: IconButton(
                                      icon: const Icon(Icons.cancel, color: Colors.red),
                                      onPressed: () => setState(() => _gcashQrUrl = null),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: _isUploading ? null : _pickAndUploadQrImage,
                            icon: const Icon(Icons.qr_code_2),
                            label: Text(_gcashQrUrl == null ? 'Upload QR Code' : 'Change QR Code'),
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 24),
                    _buildSectionCard('Identity Verification', [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: _identityStatus == 'verified' ? Colors.green.withOpacity(0.1) : (_identityStatus == 'rejected' ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1)), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Icon(_identityStatus == 'verified' ? Icons.verified : (_identityStatus == 'rejected' ? Icons.error : Icons.pending), color: _identityStatus == 'verified' ? Colors.green : (_identityStatus == 'rejected' ? Colors.red : Colors.orange)),
                          const SizedBox(width: 12),
                          Text('Status: ${_identityStatus?.toUpperCase() ?? 'PENDING'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ])
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _isUploading ? null : () => _pickAndVerifyIdentityImage(false),
                              child: Container(
                                height: 120,
                                decoration: BoxDecoration(
                                    color: secondaryColor.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: secondaryColor, width: 1)),
                                child: _idImageUrl != null
                                    ? ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.network(_idImageUrl!, fit: BoxFit.cover))
                                    : const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.badge, color: Colors.grey), Text('Upload ID', style: TextStyle(color: Colors.grey))])),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GestureDetector(
                              onTap: _isUploading ? null : () => _pickAndVerifyIdentityImage(true),
                              child: Container(
                                height: 120,
                                decoration: BoxDecoration(
                                    color: secondaryColor.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: secondaryColor, width: 1)),
                                child: _selfieImageUrl != null
                                    ? ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.network(_selfieImageUrl!, fit: BoxFit.cover))
                                    : const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.face, color: Colors.grey), Text('Upload Selfie', style: TextStyle(color: Colors.grey))])),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('SAVE CHANGES',
                              style: TextStyle(letterSpacing: 1)),
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

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon,
      {TextInputType? keyboardType,
      List<TextInputFormatter>? inputFormatters,
      int? maxLength,
      String? Function(String?)? validator,
      bool required = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: [
        ...?inputFormatters,
        FilteringTextInputFormatter.deny(RegExp(
            r'[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]',
            unicode: true)),
      ],
      maxLength: maxLength,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
        counterText: "",
      ),
      validator: validator ??
          (value) {
            if (required && (value == null || value.trim().isEmpty))
              return 'Required';
            return null;
          },
    );
  }
}
