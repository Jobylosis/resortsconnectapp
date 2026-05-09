import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import 'firebase_options.dart';
import 'login_page.dart';
import 'theme.dart';
import 'theme_provider.dart';
import 'dashboards/tourist_dashboard.dart';
import 'dashboards/owner_dashboard.dart';
import 'dashboards/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Replace red screen with a clean error message
  ErrorWidget.builder = (details) => Material(
    child: Container(
      color: Colors.black,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          "Rendering Error: ${details.exception}",
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Enable offline persistence
    FirebaseDatabase.instance.setPersistenceEnabled(true);
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Resort Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: theme.themeMode,
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
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnapshot.data;
        if (user == null) return const LoginPage();

        if (!user.emailVerified) {
          return const VerificationTimerPage();
        }

        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref("users/${user.uid}").onValue,
          builder: (context, dbSnapshot) {
            if (dbSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            if (!dbSnapshot.hasData || !dbSnapshot.data!.snapshot.exists) {
              return _errorPage("User profile not found", Icons.person_off);
            }

            final data = Map<String, dynamic>.from(dbSnapshot.data!.snapshot.value as Map);

            if (data['isBanned'] == true) {
              return _bannedPage();
            }

            String role = (data['role'] ?? 'Tourist').toString().toUpperCase();
            if (role == 'OWNER') return const OwnerDashboard();
            if (role == 'ADMIN') return const AdminDashboard();
            return const TouristDashboard();
          },
        );
      },
    );
  }

  Widget _bannedPage() => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.gavel_rounded, size: 100, color: AppTheme.primaryAccent),
            const SizedBox(height: 24),
            const Text(
              "Your account is currently banned",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              "Please contact the admin via email for more information.\n\nresortconnect2026@gmail.com",
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(200, 50),
              ),
              child: const Text("BACK TO LOGIN"),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _errorPage(String message, IconData icon) => Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: AppTheme.primaryAccent),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text("Back to Login")),
        ],
      ),
    ),
  );
}

// ✅ Automated Email Verification Check
class VerificationTimerPage extends StatefulWidget {
  const VerificationTimerPage({super.key});
  @override
  State<VerificationTimerPage> createState() => _VerificationTimerPageState();
}

class _VerificationTimerPageState extends State<VerificationTimerPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Check every 3 seconds if email is verified
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await FirebaseAuth.instance.currentUser?.reload();
      if (FirebaseAuth.instance.currentUser?.emailVerified == true) {
        timer.cancel();
        if (mounted) setState(() {}); // Trigger AuthWrapper rebuild
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_rounded, size: 100, color: AppTheme.secondaryAccent),
              const SizedBox(height: 32),
              Text("Verify Your Email", style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              const Text(
                "We've sent a link to your email. Please click it to continue. This page will update automatically once verified.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.currentUser?.sendEmailVerification(),
                child: const Text("RESEND EMAIL"),
              ),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text("Back to Login"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
