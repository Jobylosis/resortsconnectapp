import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
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

  final String _userRole = 'Tourist'; 
  bool _isPasswordVisible = false;
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

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await userCredential.user?.sendEmailVerification();

      DatabaseReference ref = FirebaseDatabase.instance.ref("users/${userCredential.user!.uid}");
      await ref.set({
        'firstName': _firstNameController.text.trim(),
        'middleName': _middleNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'role': _userRole, 
        'uid': userCredential.user!.uid,
        'createdAt': ServerValue.timestamp,
        'isBanned': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration Successful! Please check your email to verify your account.'),
            duration: Duration(seconds: 5),
          )
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Auth Error')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(themeProvider.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () => themeProvider.toggleTheme(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Join Resort Connect', 
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: secondaryColor, letterSpacing: -0.5),
                      textAlign: TextAlign.center
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start your journey today', 
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center
                    ),
                    const SizedBox(height: 40),
                    
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            _buildTextField(_firstNameController, 'First Name', Icons.person_rounded),
                            const SizedBox(height: 16),
                            _buildTextField(_middleNameController, 'Middle Name (Optional)', Icons.person_outline_rounded, required: false),
                            const SizedBox(height: 16),
                            _buildTextField(_lastNameController, 'Last Name', Icons.person_rounded),
                            const SizedBox(height: 16),
                            _buildTextField(_emailController, 'Email Address', Icons.email_rounded, keyboardType: TextInputType.emailAddress),
                            const SizedBox(height: 16),
                            _buildTextField(_phoneController, 'Phone Number', Icons.phone_android_rounded, keyboardType: TextInputType.phone, isPhone: true),
                            const SizedBox(height: 16),
                            _buildTextField(_passwordController, 'Password', Icons.lock_rounded, isPassword: true),
                            const SizedBox(height: 16),
                            _buildTextField(_confirmPasswordController, 'Confirm Password', Icons.lock_outline_rounded, isPassword: true, isConfirm: true),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 32),

                    ElevatedButton(
                      onPressed: _registerUser,
                      child: const Text('CREATE ACCOUNT', style: TextStyle(letterSpacing: 1.5)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller, 
    String label, 
    IconData icon, 
    {bool required = true, TextInputType keyboardType = TextInputType.text, bool isPassword = false, bool isPhone = false, bool isConfirm = false}
  ) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      keyboardType: keyboardType,
      maxLength: isPhone ? 11 : 50,
      inputFormatters: isPhone ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: isPassword ? IconButton(
          icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.3)),
          onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
        ) : null,
        counterText: "",
      ),
      validator: (value) {
        if (required && (value == null || value.isEmpty)) return 'Required';
        if (isPhone) {
          if (value!.length != 11) return 'Must be 11 digits';
          if (!value.startsWith('09')) return 'Must start with 09';
        }
        if (isPassword && value!.length < 8) return 'Min 8 chars';
        if (isConfirm && value != _passwordController.text) return 'Passwords do not match';
        return null;
      },
    );
  }
}
