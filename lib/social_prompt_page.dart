import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/auth_service.dart';
import 'theme.dart';

class SocialPromptPage extends StatelessWidget {
  final User user;

  const SocialPromptPage({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_off_rounded, size: 64, color: AppTheme.primaryAccent),
              const SizedBox(height: 24),
              const Text(
                'Account Not Found',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryAccent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'This email is not registered yet.\nWould you like to create an account?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => AuthService.signOut(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('No, cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Change source to register so main.dart renders RegisterPage
                        AuthService.socialAuthSource = 'register';
                        // Force AuthWrapper to rebuild by reloading user
                        user.reload();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Yes, create account'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
