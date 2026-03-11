import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';
import 'login_page.dart';

import 'dashboards/tourist_dashboard.dart';
import 'dashboards/owner_dashboard.dart';
import 'dashboards/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resort Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        final user = snapshot.data;
        if (user != null) {
          // SECURITY: Check if email is verified
          if (!user.emailVerified) {
            return const VerificationPendingPage();
          }

          return StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref("users/${user.uid}").onValue,
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (userSnapshot.hasData && userSnapshot.data!.snapshot.exists) {
                Map<dynamic, dynamic> userData = userSnapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                
                // SECURITY: Check if user is banned
                if (userData['isBanned'] == true) {
                  FirebaseAuth.instance.signOut();
                  return const BannedUserPage();
                }

                String role = userData['role'] ?? 'Tourist';
                switch (role) {
                  case 'Owner':
                    return const OwnerDashboard();
                  case 'Admin':
                    return const AdminDashboard();
                  default:
                    return const TouristDashboard();
                }
              }
              return const LoginPage();
            },
          );
        }
        return const LoginPage();
      },
    );
  }
}

// Security UI: Page shown when email is not verified
class VerificationPendingPage extends StatelessWidget {
  const VerificationPendingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.email_outlined, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              const Text('Verify your email', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text(
                'We sent a link to your email address. Please click it to verify your account and continue.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.currentUser?.sendEmailVerification(),
                child: const Text('Resend Verification Email'),
              ),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Security UI: Page shown when user is banned
class BannedUserPage extends StatelessWidget {
  const BannedUserPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.gavel_rounded, size: 80, color: Colors.red),
              SizedBox(height: 24),
              Text('Account Restricted', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              Text(
                'Your account has been suspended for violating our terms of service. Please contact support if you believe this is an error.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
