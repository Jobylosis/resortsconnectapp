import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';
import 'theme.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Step 2: ID Upload
  int _currentStep = 0; // 0 = personal info, 1 = ID upload
  String? _selectedIdType;
  XFile? _idImageFile;
  String? _idImageUrl;
  bool _isUploading = false;

  final List<String> _idTypes = [
    'Philippine National ID (PhilSys)',
    'Passport',
    "Driver's License",
    "Voter's ID",
    'SSS / GSIS ID',
    'PRC ID',
    'Senior Citizen ID',
    'Postal ID',
  ];

  final String _cloudName = "dnv6ezitm";
  final String _uploadPreset = "resort_unsigned";

  final String _userRole = 'Tourist';
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _generateCustomId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    String id =
        Iterable.generate(6, (index) => chars[random.nextInt(chars.length)])
            .join();
    return "RC-$id";
  }

  Future<void> _pickIdImage() async {
    final picker = ImagePicker();
    final picked = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take a Photo'),
              onTap: () async {
                final f = await picker.pickImage(
                    source: ImageSource.camera, imageQuality: 70);
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
    if (picked != null) setState(() => _idImageFile = picked);
  }

  Future<void> _uploadIdImage() async {
    if (_idImageFile == null) return;
    setState(() => _isUploading = true);
    try {
      final url =
          Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/image/upload");
      final request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = _uploadPreset
        ..files
            .add(await http.MultipartFile.fromPath('file', _idImageFile!.path));
      final response = await request.send();
      if (response.statusCode == 200) {
        final data = jsonDecode(await response.stream.bytesToString());
        setState(() => _idImageUrl = data['secure_url']);
      } else {
        throw Exception('Upload failed with status ${response.statusCode}');
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _registerUser() async {
    if (_idImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please upload your valid ID before continuing.')),
      );
      return;
    }
    if (_selectedIdType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your ID type.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await userCredential.user?.sendEmailVerification();
      String customId = _generateCustomId();
      final firstName = _firstNameController.text.trim();

      DatabaseReference dbRef =
          FirebaseDatabase.instance.ref("users/${userCredential.user!.uid}");
      await dbRef.set({
        'firstName': firstName,
        'middleName': _middleNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'role': _userRole,
        'uid': userCredential.user!.uid,
        'customId': customId,
        'createdAt': ServerValue.timestamp,
        'isBanned': false,
        'idType': _selectedIdType,
        'idImageUrl': _idImageUrl,
        'idVerified': false,
      });

      // M1 Fix: Cache first name immediately so dashboard shows it before stream resolves
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cachedFirstName', firstName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration Successful! Please verify your email.'),
            duration: Duration(seconds: 5),
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = 'Registration Failed';
      if (e.code == 'email-already-in-use') {
        msg = 'This email is already registered.';
      } else if (e.code == 'weak-password') {
        msg = 'The password is too weak.';
      } else if (e.code == 'invalid-email') {
        msg = 'The email address is invalid.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToStep(int step) {
    if (step == 1 && !_formKey.currentState!.validate()) return;
    setState(() => _currentStep = step);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentStep == 0 ? 'Create Account' : 'Identity Verification',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        leading: _currentStep == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _currentStep = 0))
            : null,
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
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: _currentStep == 0
                    ? _buildStep1(secondaryColor)
                    : _buildStep2(secondaryColor),
              ),
      ),
    );
  }

  Widget _buildStep1(Color secondaryColor) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress indicator
          _buildProgressBar(0),
          const SizedBox(height: 24),

          Image.asset(
            'assets/ResortConnectLogo.png',
            height: 80,
            errorBuilder: (_, __, ___) => Icon(Icons.beach_access_rounded,
                size: 80, color: secondaryColor),
          ),
          const SizedBox(height: 12),
          Text('Join Resort Connect',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: secondaryColor, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text('Step 1 of 2 — Personal Details',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 32),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildTextField(
                      _firstNameController, 'First Name', Icons.person_rounded,
                      isName: true),
                  const SizedBox(height: 16),
                  _buildTextField(_middleNameController,
                      'Middle Name (Optional)', Icons.person_outline_rounded,
                      required: false, isName: true),
                  const SizedBox(height: 16),
                  _buildTextField(
                      _lastNameController, 'Last Name', Icons.person_rounded,
                      isName: true),
                  const SizedBox(height: 16),
                  _buildTextField(
                      _emailController, 'Email Address', Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress, isEmail: true),
                  const SizedBox(height: 16),
                  _buildTextField(_phoneController, 'Phone Number',
                      Icons.phone_android_rounded,
                      keyboardType: TextInputType.phone, isPhone: true),
                  const SizedBox(height: 16),
                  _buildTextField(
                      _passwordController, 'Password', Icons.lock_rounded,
                      isPassword: true),
                  const SizedBox(height: 16),
                  _buildTextField(_confirmPasswordController,
                      'Confirm Password', Icons.lock_outline_rounded,
                      isPassword: true, isConfirm: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _goToStep(1),
            child: const Text('CONTINUE', style: TextStyle(letterSpacing: 1.5)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStep2(Color secondaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProgressBar(1),
        const SizedBox(height: 24),

        Text('Identity Verification',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('Step 2 of 2 — Upload a valid government ID',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: secondaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: secondaryColor.withOpacity(0.2))),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: secondaryColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      'Your ID is encrypted and used only for verification purposes.',
                      style: TextStyle(
                          fontSize: 12,
                          color: secondaryColor,
                          fontWeight: FontWeight.w600))),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ID Type Dropdown
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ID Type',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedIdType,
                  hint: const Text('Select your ID type'),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.badge_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  items: _idTypes
                      .map((type) => DropdownMenuItem(
                          value: type,
                          child:
                              Text(type, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedIdType = val),
                ),
                const SizedBox(height: 24),

                // ID Image Upload
                const Text('Upload ID Photo',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _isUploading ? null : _pickIdImage,
                  child: Container(
                    width: double.infinity,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _idImageFile != null
                              ? secondaryColor
                              : Theme.of(context).dividerColor,
                          width: _idImageFile != null ? 2 : 1),
                    ),
                    child: _idImageFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.file(File(_idImageFile!.path),
                                fit: BoxFit.cover),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_rounded,
                                  size: 48,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary
                                      .withOpacity(0.5)),
                              const SizedBox(height: 10),
                              const Text('Tap to take or upload a photo',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('Front side of your ID',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                  ),
                ),
                if (_idImageFile != null && _idImageUrl == null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isUploading ? null : _uploadIdImage,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_rounded, size: 18),
                      label: Text(
                          _isUploading ? 'Uploading...' : 'Upload ID Photo'),
                    ),
                  ),
                ],
                if (_idImageUrl != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Colors.green[600], size: 18),
                      const SizedBox(width: 8),
                      const Text('ID uploaded successfully',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.green,
                              fontSize: 13)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed:
              (_idImageUrl != null && _selectedIdType != null && !_isLoading)
                  ? _registerUser
                  : null,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondaryAccent,
              foregroundColor: Colors.black),
          child: const Text('CREATE ACCOUNT',
              style:
                  TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildProgressBar(int activeStep) {
    return Row(
      children: [0, 1].map((step) {
        final isActive = step <= activeStep;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
                right: step == 0 ? 6 : 0, left: step == 1 ? 6 : 0),
            height: 5,
            decoration: BoxDecoration(
              color: isActive
                  ? AppTheme.secondaryAccent
                  : Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = true,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    bool isPhone = false,
    bool isConfirm = false,
    bool isName = false,
    bool isEmail = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && (isConfirm ? !_isConfirmPasswordVisible : !_isPasswordVisible),
      keyboardType: keyboardType,
      maxLength: isPhone ? 11 : 50,
      inputFormatters: [
        if (isPhone) FilteringTextInputFormatter.digitsOnly,
        if (isName) FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s'-]")),
        FilteringTextInputFormatter.allow(RegExp(r'[\x00-\x7F]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    (isConfirm ? _isConfirmPasswordVisible : _isPasswordVisible)
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withOpacity(0.3)),
                onPressed: () => setState(() {
                  if (isConfirm) {
                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                  } else {
                    _isPasswordVisible = !_isPasswordVisible;
                  }
                }),
              )
            : null,
        counterText: "",
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty))
          return '⬆ Required';
        if (value != null && value.trim().isNotEmpty) {
          final v = value.trim();
          if (isName) {
            if (!RegExp(r"^[a-zA-Z\s'-]+$").hasMatch(v))
              return '⬆ Only letters allowed';
            if (v.length < 2) return '⬆ Must be at least 2 characters';
          }
          if (isEmail) {
            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v))
              return '⬆ Enter a valid email';
          }
          if (isPhone) {
            if (v.length != 11) return '⬆ Must be 11 digits';
            if (!v.startsWith('09')) return '⬆ Must start with 09';
          }
          if (isPassword) {
            if (v.length < 8) return '⬆ At least 8 characters';
            if (!RegExp(r'[A-Z]').hasMatch(v))
              return '⬆ Add at least one uppercase letter';
            if (!RegExp(r'[a-z]').hasMatch(v))
              return '⬆ Add at least one lowercase letter';
            if (!RegExp(r'[0-9]').hasMatch(v))
              return '⬆ Add at least one number';
            if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v))
              return '⬆ Add at least one special character';
          }
          if (isConfirm && v != _passwordController.text.trim())
            return '⬆ Passwords do not match';
        }
        return null;
      },
    );
  }
}
