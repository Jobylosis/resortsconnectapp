import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

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
      // 1. Create User in Auth
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 2. Send Email Verification
      await userCredential.user?.sendEmailVerification();

      // 3. Save to Realtime Database
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
        'isBanned': false, // Explicitly set default
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
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
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
                    const Text('Join Resort Connect', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepPurple), textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    
                    TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(labelText: 'First Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                      textCapitalization: TextCapitalization.words,
                      maxLength: 50,
                      validator: (value) => value!.isEmpty ? 'Enter your first name' : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _middleNameController,
                      decoration: const InputDecoration(labelText: 'Middle Name (Optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                      textCapitalization: TextCapitalization.words,
                      maxLength: 50,
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(labelText: 'Last Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                      textCapitalization: TextCapitalization.words,
                      maxLength: 50,
                      validator: (value) => value!.isEmpty ? 'Enter your last name' : null,
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                      keyboardType: TextInputType.emailAddress,
                      maxLength: 100,
                      validator: (value) => value!.isEmpty ? 'Enter your email' : null,
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone), counterText: ""),
                      maxLength: 11,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Enter your phone number';
                        if (value.length != 11) return 'Must be exactly 11 digits';
                        if (!value.startsWith('09')) return 'Must start with 09';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password', 
                        border: const OutlineInputBorder(), 
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                        ),
                      ),
                      obscureText: !_isPasswordVisible,
                      maxLength: 50,
                      validator: (value) => (value == null || value.length < 8) ? 'Min 8 chars' : null,
                    ),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _confirmPasswordController,
                      decoration: const InputDecoration(labelText: 'Confirm Password', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock_outline)),
                      obscureText: !_isPasswordVisible,
                      maxLength: 50,
                      validator: (value) => value != _passwordController.text ? 'Passwords do not match' : null,
                    ),
                    const SizedBox(height: 32),

                    ElevatedButton(
                      onPressed: _registerUser,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Create Account'),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}
