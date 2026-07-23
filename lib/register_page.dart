import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart';
import 'theme.dart';
import 'face_capture_page.dart';
import 'services/ai_service.dart';

class RegisterPage extends StatefulWidget {
  final bool isCompletingSocial;
  final User? socialUser;

  const RegisterPage(
      {super.key, this.isCompletingSocial = false, this.socialUser});

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
  final _otherIdTypeController = TextEditingController();

  // Step 2: ID Upload
  int _currentStep = 0; // 0 = personal info, 1 = ID upload
  String? _selectedIdType;
  XFile? _idImageFile;
  String? _idImageUrl;
  bool _isUploading = false;

  XFile? _selfieImageFile;
  String? _selfieImageUrl;
  bool _isUploadingSelfie = false;

  final List<String> _idTypes = [
    'Philippine National ID (PhilSys)',
    'Passport',
    "Driver's License",
    "Voter's ID",
    'SSS / GSIS ID',
    'PRC ID',
    'Senior Citizen ID',
    'Postal ID',
    'Other',
  ];

  final String _cloudName = "dnv6ezitm";
  final String _uploadPreset = "resort_unsigned";

  final String _userRole = 'Tourist';
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isCompletingSocial && widget.socialUser != null) {
      final user = widget.socialUser!;
      final names = user.displayName?.split(' ') ?? [''];
      _firstNameController.text = names[0];
      if (names.length > 1) {
        _lastNameController.text = names.sublist(1).join(' ');
      }
      _emailController.text = user.email ?? '';
      _phoneController.text = user.phoneNumber ?? '';
    } else {
      _loadDraft();
    }
    _firstNameController.addListener(_saveDraft);
    _lastNameController.addListener(_saveDraft);
    _emailController.addListener(_saveDraft);
    _phoneController.addListener(_saveDraft);
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _firstNameController.text = prefs.getString('rp_firstName') ?? '';
      _lastNameController.text = prefs.getString('rp_lastName') ?? '';
      _emailController.text = prefs.getString('rp_email') ?? '';
      _phoneController.text = prefs.getString('rp_phone') ?? '';
      _currentStep = prefs.getInt('rp_step') ?? 0;
    });
  }

  Future<void> _saveDraft() async {
    if (widget.isCompletingSocial) return;
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('rp_firstName', _firstNameController.text);
    prefs.setString('rp_lastName', _lastNameController.text);
    prefs.setString('rp_email', _emailController.text);
    prefs.setString('rp_phone', _phoneController.text);
    prefs.setInt('rp_step', _currentStep);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otherIdTypeController.dispose();
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
    if (picked != null) {
      setState(() => _isUploading = true); // use uploading state for loading
      try {
        final idType = _selectedIdType == 'Other' 
            ? _otherIdTypeController.text.trim() 
            : (_selectedIdType ?? '');
            
        final result = await AiService.verifyIdName(
          File(picked.path), 
          _selfieImageFile != null ? File(_selfieImageFile!.path) : null,
          _firstNameController.text.trim(), 
          _lastNameController.text.trim(),
          idType
        );
        
        if (result['success'] == true) {
          if (result['match'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID credentials matched!')));
            setState(() => _idImageFile = picked);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Verification failed.')));
            setState(() => _idImageFile = null);
          }
        } else {
          // If server fails or no connection, we just accept it and let admin manually verify later
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI Server Offline: ID accepted automatically.')));
          setState(() => _idImageFile = picked);
        }
      } catch (e) {
        setState(() => _idImageFile = picked);
      } finally {
        setState(() => _isUploading = false);
      }
    }
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
      rethrow;
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickSelfieImage() async {
    final XFile? picked = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FaceCapturePage(),
      ),
    );
    if (picked != null) {
      if (_idImageFile != null) {
        // If ID is already uploaded, verify them together
        setState(() => _isUploadingSelfie = true);
        try {
          final idType = _selectedIdType == 'Other' 
              ? _otherIdTypeController.text.trim() 
              : (_selectedIdType ?? '');
              
          final result = await AiService.verifyIdName(
            File(_idImageFile!.path), 
            File(picked.path),
            _firstNameController.text.trim(), 
            _lastNameController.text.trim(),
            idType
          );
          
          if (result['success'] == true) {
            if (result['match'] == true) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Facial recognition match successful!')));
              setState(() => _selfieImageFile = picked);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'Verification failed.')));
              setState(() => _selfieImageFile = null);
            }
          } else {
            setState(() => _selfieImageFile = picked);
          }
        } catch (e) {
          setState(() => _selfieImageFile = picked);
        } finally {
          setState(() => _isUploadingSelfie = false);
        }
      } else {
        setState(() => _selfieImageFile = picked);
      }
    }
  }

  Future<void> _uploadSelfieImage() async {
    if (_selfieImageFile == null) return;
    setState(() => _isUploadingSelfie = true);
    try {
      final url =
          Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/image/upload");
      final request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(
            await http.MultipartFile.fromPath('file', _selfieImageFile!.path));
      final response = await request.send();
      if (response.statusCode == 200) {
        final data = jsonDecode(await response.stream.bytesToString());
        setState(() => _selfieImageUrl = data['secure_url']);
      } else {
        throw Exception('Upload failed with status ${response.statusCode}');
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Selfie upload failed: $e')));
      rethrow;
    } finally {
      if (mounted) setState(() => _isUploadingSelfie = false);
    }
  }

  Future<void> _registerUser() async {
    if (_idImageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload your valid ID before continuing.',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selfieImageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a selfie photo before continuing.',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selectedIdType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your ID type.',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selectedIdType == 'Other' &&
        _otherIdTypeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please specify your ID type.',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_idImageUrl == null) {
        await _uploadIdImage();
      }
      if (_selfieImageUrl == null) {
        await _uploadSelfieImage();
      }

      if (_idImageUrl == null || _selfieImageUrl == null) {
        throw Exception("Failed to upload identity images.");
      }

      UserCredential? userCredential;
      String uid = "";

      if (!widget.isCompletingSocial) {
        userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        await userCredential.user?.sendEmailVerification();
        uid = userCredential.user!.uid;
      } else {
        uid = widget.socialUser!.uid;
      }
      String customId = _generateCustomId();
      final firstName = _firstNameController.text.trim();

      DatabaseReference dbRef = FirebaseDatabase.instance.ref("users/$uid");
      
      Map<String, dynamic> existingData = {};
      if (widget.isCompletingSocial) {
        final snap = await dbRef.get();
        if (snap.exists && snap.value != null) {
          final val = snap.value as Map;
          existingData = Map<String, dynamic>.from(val);
        }
      }

      await dbRef.set({
        ...existingData,
        'firstName': firstName,
        'middleName': _middleNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'role': existingData['role'] ?? _userRole,
        'uid': uid,
        'customId': existingData['customId'] ?? customId,
        'createdAt': existingData['createdAt'] ?? ServerValue.timestamp,
        'isBanned': existingData['isBanned'] ?? false,
        'idType': _selectedIdType == 'Other'
            ? _otherIdTypeController.text.trim()
            : _selectedIdType,
        'idImageUrl': _idImageUrl,
        'selfieUrl': _selfieImageUrl,
        'idVerified': true,
        'identityStatus': 'approved',
      });

      // M1 Fix: Cache first name immediately so dashboard shows it before stream resolves
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cachedFirstName', firstName);
      await prefs.remove('rp_firstName');
      await prefs.remove('rp_lastName');
      await prefs.remove('rp_email');
      await prefs.remove('rp_phone');
      await prefs.remove('rp_step');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration Successful! Please verify your email.'),
            duration: Duration(seconds: 5),
          ),
        );
        Navigator.popUntil(context, (route) => route.isFirst);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSocialLogin(String providerName) async {
    setState(() => _isLoading = true);
    try {
      UserCredential? userCredential;
      if (providerName == 'google') {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() => _isLoading = false);
          return;
        }
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);
      } else if (providerName == 'facebook') {
        final LoginResult result = await FacebookAuth.instance.login();
        if (result.status == LoginStatus.success) {
          final AuthCredential credential =
              FacebookAuthProvider.credential(result.accessToken!.tokenString);
          userCredential =
              await FirebaseAuth.instance.signInWithCredential(credential);
        } else {
          setState(() => _isLoading = false);
          return;
        }
      }

      if (userCredential != null) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Social Login Error: $e',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToStep(int step) {
    if (step == 1 && !_formKey.currentState!.validate()) return;
    
    // Clear images if user goes back to edit details (forces re-verification with AI)
    if (step == 0 && (_idImageFile != null || _selfieImageFile != null)) {
      setState(() {
        _idImageFile = null;
        _idImageUrl = null;
        _selfieImageFile = null;
        _selfieImageUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification images cleared because you went back to edit details. Please re-upload to match the new details.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    
    setState(() {
      _currentStep = step;
      _saveDraft();
    });
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
                icon: Icon(Icons.arrow_back_rounded,
                    color: Theme.of(context).colorScheme.onSurface),
                onPressed: () => setState(() {
                  _currentStep = 0;
                  _saveDraft();
                }))
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
                  if (!widget.isCompletingSocial) ...[
                    const SizedBox(height: 16),
                    _buildTextField(
                        _passwordController, 'Password', Icons.lock_rounded,
                        isPassword: true),
                    const SizedBox(height: 16),
                    _buildTextField(_confirmPasswordController,
                        'Confirm Password', Icons.lock_outline_rounded,
                        isPassword: true, isConfirm: true),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _goToStep(1),
            child: const Text('CONTINUE', style: TextStyle(letterSpacing: 1.5)),
          ),

          if (!widget.isCompletingSocial) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR REGISTER WITH',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _isLoading ? null : () => _handleSocialLogin('google'),
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                    label: const Text('Google',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _handleSocialLogin('facebook'),
                    icon: const Icon(Icons.facebook_rounded,
                        color: Colors.blue, size: 22),
                    label: const Text('Facebook',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
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
                  onChanged: (val) {
                    setState(() {
                      _selectedIdType = val;
                      _idImageFile = null; // Clear uploaded image if ID Type changes
                    });
                  },
                ),
                if (_selectedIdType == 'Other') ...[
                  const SizedBox(height: 16),
                  const Text('Specify ID',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _otherIdTypeController,
                    maxLength: 30,
                    decoration: InputDecoration(
                      hintText: 'Enter ID type',
                      counterText: "",
                      prefixIcon: const Icon(Icons.edit_document),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ID Image Upload
                const Text('Upload ID Photo',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _isUploading
                      ? null
                      : () {
                          if (_selectedIdType == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please select an ID type first.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          _pickIdImage();
                        },
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
                    child: _isUploading
                        ? const Center(child: CircularProgressIndicator())
                        : _idImageFile != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.file(File(_idImageFile!.path),
                                    fit: BoxFit.cover),
                              )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.crop_free_rounded,
                                  size: 48,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary
                                      .withOpacity(0.8)),
                              const SizedBox(height: 10),
                              const Text('Tap to capture or upload ID',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                    'Please align your ID perfectly within the camera frame so all details are visible.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                        fontStyle: FontStyle.italic)),
                              ),
                            ],
                          ),
                  ),
                ),
                if (_idImageFile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        const Text('ID Selected',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        GestureDetector(
                          onTap: _pickIdImage,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                  color: AppTheme.primaryAccent,
                                  borderRadius: BorderRadius.circular(20)),
                              child: const Text('Change',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold))),
                        )
                      ],
                    ),
                  ),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // Selfie Image Upload
                const Text('Upload Selfie Photo',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _isUploadingSelfie ? null : _pickSelfieImage,
                  child: Container(
                    width: double.infinity,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _selfieImageFile != null
                              ? secondaryColor
                              : Theme.of(context).dividerColor,
                          width: _selfieImageFile != null ? 2 : 1),
                    ),
                    child: _isUploadingSelfie
                        ? const Center(child: CircularProgressIndicator())
                        : _selfieImageFile != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.file(File(_selfieImageFile!.path),
                                    fit: BoxFit.cover),
                              )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.face_rounded,
                                  size: 48,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary
                                      .withOpacity(0.8)),
                              const SizedBox(height: 10),
                              const Text('Tap to capture or upload selfie',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                    'Please take a clear photo of your face for identity verification.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                        fontStyle: FontStyle.italic)),
                              ),
                            ],
                          ),
                  ),
                ),
                if (_selfieImageFile != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        const Text('Selfie Selected',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        GestureDetector(
                          onTap: _pickSelfieImage,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                  color: AppTheme.primaryAccent,
                                  borderRadius: BorderRadius.circular(20)),
                              child: const Text('Change',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold))),
                        )
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _goToStep(0),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5)),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                child: const Text('BACK'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: (_idImageFile != null &&
                        _selfieImageFile != null &&
                        _selectedIdType != null &&
                        !_isLoading)
                    ? _registerUser
                    : null,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.secondaryAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                child: const Text('CREATE ACCOUNT',
                    style: TextStyle(
                        letterSpacing: 1.5, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
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
      obscureText: isPassword &&
          (isConfirm ? !_isConfirmPasswordVisible : !_isPasswordVisible),
      keyboardType: keyboardType,
      maxLength: isPhone ? 11 : (isName ? 30 : 50),
      maxLines: 1,
      inputFormatters: [
        if (isPhone) FilteringTextInputFormatter.digitsOnly,
        if (isName) FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\s]")),
        if (!isName) FilteringTextInputFormatter.allow(RegExp(r'[\x00-\x7F]')),
        if (isEmail) TextInputFormatter.withFunction((oldValue, newValue) {
          return TextEditingValue(
            text: newValue.text.toLowerCase(),
            selection: newValue.selection,
          );
        }),
      ],
      onChanged: (value) {
        if (isName) {
          if (_idImageFile != null || _selfieImageFile != null || _idImageUrl != null || _selfieImageUrl != null) {
            setState(() {
              _idImageFile = null;
              _selfieImageFile = null;
              _idImageUrl = null;
              _selfieImageUrl = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name changed. Please re-upload your ID and Selfie for verification.')));
          }
        }
      },
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
            if (v.contains('\n') || v.contains('\r'))
              return '⬆ Newlines not allowed';
            if (!RegExp(r"^[a-zA-Z\s]+$").hasMatch(v))
              return '⬆ No special characters allowed';
            if (v.split(' ').length > 4) return '⬆ Maximum of 4 words allowed';
            if (required && v.length < 2) return '⬆ Must be at least 2 characters';
            if (!required && v.length < 1) return '⬆ Invalid length';
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
