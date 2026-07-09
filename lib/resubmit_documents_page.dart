import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

import 'theme.dart';

class ResubmitDocumentsPage extends StatefulWidget {
  final String rejectionReason;

  const ResubmitDocumentsPage({super.key, required this.rejectionReason});

  @override
  State<ResubmitDocumentsPage> createState() => _ResubmitDocumentsPageState();
}

class _ResubmitDocumentsPageState extends State<ResubmitDocumentsPage> {
  final String _cloudName = 'dth7r65f4';
  final String _uploadPreset = 'ResortsConnectImages';

  String? _selectedIdType;
  XFile? _idImageFile;
  XFile? _selfieImageFile;
  String? _idImageUrl;
  String? _selfieImageUrl;

  bool _isLoading = false;

  final List<String> _idTypes = [
    'Passport',
    'Driver\'s License',
    'National ID',
    'Postal ID',
    'Voter\'s ID',
    'Other'
  ];

  final TextEditingController _otherIdTypeController = TextEditingController();

  Future<void> _pickImage(bool isSelfie) async {
    final picker = ImagePicker();
    final picked = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text(isSelfie ? 'Take a Selfie' : 'Take a Photo'),
              onTap: () async {
                final f = await picker.pickImage(
                    source: ImageSource.camera,
                    preferredCameraDevice: isSelfie ? CameraDevice.front : CameraDevice.rear,
                    imageQuality: 70);
                if (ctx.mounted) Navigator.pop(ctx, f);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                final f = await picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 70);
                if (ctx.mounted) Navigator.pop(ctx, f);
              },
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        if (isSelfie) {
          _selfieImageFile = picked;
        } else {
          _idImageFile = picked;
        }
      });
    }
  }

  Future<String> _uploadImageToCloudinary(XFile file) async {
    final url = Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/image/upload");
    final request = http.MultipartRequest("POST", url)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final response = await request.send();
    if (response.statusCode == 200) {
      final data = jsonDecode(await response.stream.bytesToString());
      return data['secure_url'];
    } else {
      throw Exception('Upload failed with status ${response.statusCode}');
    }
  }

  Future<void> _submitDocuments() async {
    if (_idImageFile == null || _selfieImageFile == null || _selectedIdType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload both images and select an ID type.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      _idImageUrl = await _uploadImageToCloudinary(_idImageFile!);
      _selfieImageUrl = await _uploadImageToCloudinary(_selfieImageFile!);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseDatabase.instance.ref("users/${user.uid}").update({
          'idType': _selectedIdType == 'Other' ? _otherIdTypeController.text.trim() : _selectedIdType,
          'idImageUrl': _idImageUrl,
          'selfieUrl': _selfieImageUrl,
          'identityStatus': 'pending',
          'idVerified': false,
          'rejectionReason': null, // Clear the reason
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Documents resubmitted successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resubmit Documents', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.darkBg, Color(0xFF1A0505)],
          ),
        ),
        child: SafeArea(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Verification Rejected', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Reason: ${widget.rejectionReason}', style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 4),
                          const Text('Please upload clear, valid documents to resubmit for verification.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Select ID Type', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.borderDark),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          hint: const Text('Select ID Type'),
                          value: _selectedIdType,
                          dropdownColor: AppTheme.darkSurface,
                          items: _idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (val) => setState(() => _selectedIdType = val),
                        ),
                      ),
                    ),
                    if (_selectedIdType == 'Other') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _otherIdTypeController,
                        decoration: InputDecoration(
                          labelText: 'Specify ID Type',
                          filled: true,
                          fillColor: AppTheme.darkSurface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text('Upload Valid ID', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 8),
                    _buildImagePickerBox(
                      file: _idImageFile,
                      onTap: () => _pickImage(false),
                      placeholderIcon: Icons.badge_outlined,
                      placeholderText: 'Tap to upload ID',
                    ),
                    const SizedBox(height: 24),
                    const Text('Upload Selfie with ID', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 8),
                    _buildImagePickerBox(
                      file: _selfieImageFile,
                      onTap: () => _pickImage(true),
                      placeholderIcon: Icons.face_retouching_natural_rounded,
                      placeholderText: 'Tap to take selfie',
                    ),
                    const SizedBox(height: 40),
                    ElevatedButton(
                      onPressed: _submitDocuments,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppTheme.primaryAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('RESUBMIT DOCUMENTS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('Log out', style: TextStyle(color: Colors.white54)),
                    )
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildImagePickerBox({required XFile? file, required VoidCallback onTap, required IconData placeholderIcon, required String placeholderText}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: file != null ? AppTheme.primaryAccent : AppTheme.borderDark, width: 2),
        ),
        child: file != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(File(file.path), fit: BoxFit.cover, width: double.infinity),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(placeholderIcon, size: 48, color: Colors.white54),
                  const SizedBox(height: 8),
                  Text(placeholderText, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w500)),
                ],
              ),
      ),
    );
  }
}
